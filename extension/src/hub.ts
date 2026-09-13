/**
 * The Boardhop hub: one page, contributed twice (Organization settings and
 * Project settings), that connects an organization to the Boardhop relay and
 * provisions the relay's service-hook subscriptions per project.
 *
 * Plain TypeScript and DOM, styled with the CSS variables the SDK's
 * `applyTheme` writes onto `:root`, so the page follows the host's light and
 * dark themes. No React, no azure-devops-ui.
 *
 * The organization key the administrator types is used as the basic-auth
 * password of the subscriptions and as the relay's credential. It is held in
 * the password field for the length of the session and written nowhere else.
 */

import * as SDK from "azure-devops-extension-sdk";

import {
  AdoError,
  AdoProject,
  createSubscription,
  deleteSubscription,
  listProjects,
  listWebhookSubscriptions,
} from "./ado";
import {
  AdoSubscription,
  consumerUrlOf,
  hookUrlFor,
  oursFor,
  planKind,
  plannedSubscriptions,
  projectIdOf,
  reconcile,
  registryRowsFor,
  subscriptionBody,
  trimTrailingSlashes,
  worstStatus,
} from "./plan";
import { RelayClient, RelayError, RelayRegistry, relayCountFor } from "./relay";
import { loadSettings, saveSettings } from "./store";

const planned = plannedSubscriptions.length;

/** Everything the page knows. */
interface State {
  org: string;
  /** Set only in the project hub; then the page shows that project alone. */
  scopedProject?: { id: string; name: string };
  relayUrl: string;
  updatedAt?: string;
  updatedBy?: string;
  projects: AdoProject[];
  /** Every webhook subscription in the organization, refreshed as we act. */
  subs: AdoSubscription[];
  /** What the relay answered the last time the key was checked. */
  registry?: RelayRegistry;
  subsError?: string;
  busy: boolean;
}

const state: State = { org: "", relayUrl: "", projects: [], subs: [], busy: false };

interface Row {
  project: AdoProject;
  tr: HTMLTableRowElement;
  hooksCell: HTMLTableCellElement;
  statusCell: HTMLTableCellElement;
  relayCell: HTMLTableCellElement;
  messageRow: HTMLTableRowElement;
  messageCell: HTMLTableCellElement;
  buttons: HTMLButtonElement[];
}

const rows = new Map<string, Row>();

let relayUrlInput: HTMLInputElement;
let keyInput: HTMLInputElement;
let relayStatus: HTMLParagraphElement;
let settingsNote: HTMLParagraphElement;
let projectsNote: HTMLParagraphElement;
let tableBody: HTMLTableSectionElement;
let enableAllButton: HTMLButtonElement;
let refreshButton: HTMLButtonElement;
let checkButton: HTMLButtonElement;
let saveButton: HTMLButtonElement;

// ---------------------------------------------------------------- DOM helpers

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  options: { className?: string; text?: string; attrs?: Record<string, string> } = {},
  children: (Node | string)[] = [],
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  if (options.className) node.className = options.className;
  if (options.text !== undefined) node.textContent = options.text;
  for (const [name, value] of Object.entries(options.attrs ?? {})) node.setAttribute(name, value);
  for (const child of children) node.append(child);
  return node;
}

function messageOf(error: unknown): string {
  if (error instanceof AdoError || error instanceof RelayError) return error.message;
  return error instanceof Error ? error.message : String(error);
}

function setStatus(node: HTMLElement, text: string, tone: "ok" | "warn" | "error" | "muted" = "muted"): void {
  node.textContent = text;
  node.className = `status status-${tone}`;
}

// ------------------------------------------------------------------ rendering

function buildShell(): void {
  const app = document.getElementById("app");
  if (!app) throw new Error("no #app element");
  app.textContent = "";

  const scope = state.scopedProject
    ? `Project "${state.scopedProject.name}" in ${state.org}`
    : `Organization ${state.org}`;

  app.append(
    el("header", { className: "page-header" }, [
      el("h1", { text: "Boardhop" }),
      el("p", {
        className: "subtitle",
        text: `Push notifications for Boardhop, the mobile client for Azure DevOps. ${scope}.`,
      }),
    ]),
    buildRelaySection(),
    buildProjectsSection(),
    buildDisclosureSection(),
  );
}

function buildRelaySection(): HTMLElement {
  relayUrlInput = el("input", {
    className: "input",
    attrs: { type: "url", id: "relay-url", spellcheck: "false", autocomplete: "off", placeholder: "https://…" },
  });
  keyInput = el("input", {
    className: "input",
    attrs: { type: "password", id: "org-key", autocomplete: "off", placeholder: "from kammcs" },
  });
  checkButton = el("button", { className: "button button-primary", text: "Check connection" });
  saveButton = el("button", { className: "button", text: "Save relay URL" });
  relayStatus = el("p", { className: "status status-muted", text: "Not checked yet." });
  settingsNote = el("p", { className: "note" });

  checkButton.addEventListener("click", () => void checkConnection());
  saveButton.addEventListener("click", () => void persistRelayUrl());

  return el("section", { className: "card" }, [
    el("h2", { text: "Relay" }),
    el("div", { className: "field" }, [
      el("label", { text: "Relay URL", attrs: { for: "relay-url" } }),
      relayUrlInput,
      el("span", { className: "hint", text: "Where the service hooks post. Stored for the whole organization." }),
    ]),
    el("div", { className: "field" }, [
      el("label", { text: "Organization key", attrs: { for: "org-key" } }),
      keyInput,
      el("span", {
        className: "hint",
        text: "Ask kammcs for it. It is never stored by this extension - type it again next time.",
      }),
    ]),
    el("div", { className: "buttons" }, [checkButton, saveButton]),
    relayStatus,
    settingsNote,
  ]);
}

function buildProjectsSection(): HTMLElement {
  enableAllButton = el("button", { className: "button button-primary", text: "Enable all projects" });
  refreshButton = el("button", { className: "button", text: "Refresh" });
  projectsNote = el("p", { className: "status status-muted", text: "Loading projects…" });
  enableAllButton.addEventListener("click", () => void enableAllProjects());
  refreshButton.addEventListener("click", () => void refresh());

  tableBody = el("tbody");
  const table = el("table", { className: "projects" }, [
    el("thead", {}, [
      el("tr", {}, [
        el("th", { text: "Project" }),
        el("th", { text: `Hooks in Azure DevOps` }),
        el("th", { text: "Status" }),
        el("th", { text: "Relay" }),
        el("th", { text: "Actions", attrs: { class: "actions-header" } }),
      ]),
    ]),
    tableBody,
  ]);

  const header = el("div", { className: "section-header" }, [
    el("h2", { text: state.scopedProject ? "Project" : "Projects" }),
    el("div", { className: "buttons" }, state.scopedProject ? [refreshButton] : [enableAllButton, refreshButton]),
  ]);

  return el("section", { className: "card" }, [header, projectsNote, table]);
}

function buildDisclosureSection(): HTMLElement {
  return el("section", { className: "card disclosure" }, [
    el("h2", { text: "What leaves the tenant" }),
    el("p", {
      text:
        "With the shared relay, hook metadata leaves this organization and lands on the kammcs relay: " +
        "ids, links, event types and sometimes a title. Comments, descriptions and code never do. " +
        "Notifications are enriched on the phone with the signed-in user's own token, so the content of " +
        "a work item, pull request or comment is fetched from Azure DevOps by that user and never passes " +
        "through the relay, Apple or Google.",
    }),
    el("p", {
      className: "note",
      text: "The relay stores only subscription ids, event types, the routing label and the project name and id.",
    }),
  ]);
}

function renderRows(): void {
  tableBody.textContent = "";
  rows.clear();
  const visible = state.scopedProject
    ? state.projects.filter((project) => project.id === state.scopedProject?.id)
    : state.projects;

  for (const project of visible) {
    const hooksCell = el("td", { className: "num", text: "…" });
    const statusCell = el("td");
    const relayCell = el("td", { className: "num", text: "—" });

    const enable = el("button", { className: "button button-primary small", text: "Enable" });
    const repair = el("button", { className: "button small", text: "Repair" });
    const remove = el("button", { className: "button small button-danger", text: "Remove" });
    enable.addEventListener("click", () => void provision(project, { repair: false }));
    repair.addEventListener("click", () => void provision(project, { repair: true }));
    remove.addEventListener("click", () => void removeProject(project));

    const tr = el("tr", {}, [
      el("td", { className: "project-name", text: project.name }),
      hooksCell,
      statusCell,
      relayCell,
      el("td", { className: "actions" }, [el("div", { className: "buttons" }, [enable, repair, remove])]),
    ]);
    const messageCell = el("td", { className: "row-message", attrs: { colspan: "5" } });
    const messageRow = el("tr", { className: "message-row" }, [messageCell]);
    messageRow.hidden = true;

    tableBody.append(tr, messageRow);
    rows.set(project.id, {
      project,
      tr,
      hooksCell,
      statusCell,
      relayCell,
      messageRow,
      messageCell,
      buttons: [enable, repair, remove],
    });
  }

  if (visible.length === 0) projectsNote.textContent = "No projects found.";
  refreshRowCounts();
}

/** The counts and badges, from whatever `state.subs` and `state.registry` hold. */
function refreshRowCounts(): void {
  const url = hookUrlFor(state.relayUrl, state.org);
  for (const row of rows.values()) {
    const ours = oursFor(state.subs, { projectId: row.project.id, url });
    row.hooksCell.textContent = state.subsError ? "?" : `${ours.length} / ${planned}`;
    row.hooksCell.className = `num ${!state.subsError && ours.length === planned ? "num-ok" : ""}`;

    row.statusCell.textContent = "";
    const worst = worstStatus(ours);
    if (worst) row.statusCell.append(badge(worst));
    else if (!state.subsError) row.statusCell.append(el("span", { className: "badge badge-muted", text: "none" }));

    const relayCount = relayCountFor(state.registry, row.project.id);
    row.relayCell.textContent = relayCount === undefined ? "—" : `${relayCount}`;
  }
}

function badge(status: string): HTMLElement {
  const tone = status === "enabled" ? "ok" : status === "onProbation" ? "warn" : "error";
  const text = status === "enabled" ? "enabled" : status;
  return el("span", { className: `badge badge-${tone}`, text });
}

function setRowMessage(row: Row, text: string, tone: "ok" | "warn" | "error" | "muted" = "muted"): void {
  row.messageCell.textContent = text;
  row.messageCell.className = `row-message status-${tone}`;
  row.messageRow.hidden = text === "";
}

function setBusy(busy: boolean): void {
  state.busy = busy;
  const controls = [enableAllButton, refreshButton, checkButton, saveButton];
  for (const button of controls) button.disabled = busy;
  for (const row of rows.values()) for (const button of row.buttons) button.disabled = busy;
}

// -------------------------------------------------------------------- actions

function relayClient(): RelayClient {
  return new RelayClient({ relayUrl: state.relayUrl, org: state.org });
}

/** The key as typed, or undefined after focusing the field and saying so. */
function requireKey(onMissing: (message: string) => void): string | undefined {
  const key = keyInput.value.trim();
  if (key === "") {
    onMissing("Enter the organization key first - ask kammcs for it.");
    keyInput.focus();
    return undefined;
  }
  return key;
}

function currentRelayUrl(): string {
  const typed = trimTrailingSlashes(relayUrlInput.value);
  return typed === "" ? state.relayUrl : typed;
}

async function persistRelayUrl(): Promise<void> {
  state.relayUrl = currentRelayUrl();
  relayUrlInput.value = state.relayUrl;
  try {
    const saved = await saveSettings(state.relayUrl);
    state.updatedAt = saved.updatedAt;
    state.updatedBy = saved.updatedBy;
    renderSettingsNote();
    refreshRowCounts();
  } catch (error) {
    setStatus(relayStatus, `Could not save the relay URL: ${messageOf(error)}`, "error");
  }
}

function renderSettingsNote(): void {
  if (!state.updatedAt) {
    settingsNote.textContent = "";
    return;
  }
  const when = new Date(state.updatedAt);
  const stamp = Number.isNaN(when.getTime()) ? state.updatedAt : when.toLocaleString();
  settingsNote.textContent = state.updatedBy ? `Saved by ${state.updatedBy} on ${stamp}.` : `Saved on ${stamp}.`;
}

async function checkConnection(): Promise<void> {
  const key = requireKey((message) => setStatus(relayStatus, message, "warn"));
  if (!key) return;
  state.relayUrl = currentRelayUrl();
  relayUrlInput.value = state.relayUrl;
  setBusy(true);
  setStatus(relayStatus, "Checking…", "muted");
  try {
    const registry = await relayClient().listSubscriptions(key);
    state.registry = registry;
    const count = registry.subscriptions.length;
    setStatus(relayStatus, `Connected · ${count} subscription${count === 1 ? "" : "s"} registered with the relay`, "ok");
    await persistRelayUrl();
    refreshRowCounts();
  } catch (error) {
    state.registry = undefined;
    if (error instanceof RelayError && error.isUnknownOrgOrKey) {
      setStatus(relayStatus, "The relay does not know this organization or the key is wrong.", "error");
    } else {
      setStatus(relayStatus, `Could not reach the relay: ${messageOf(error)}`, "error");
    }
    refreshRowCounts();
  } finally {
    setBusy(false);
  }
}

/** Replaces a project's subscriptions in `state.subs` after we changed them. */
function replaceSubs(projectId: string, url: string, kept: AdoSubscription[]): void {
  const others = state.subs.filter((sub) => !(projectIdOf(sub) === projectId && consumerUrlOf(sub) === url));
  state.subs = [...others, ...kept];
}

async function provision(project: AdoProject, options: { repair: boolean }): Promise<void> {
  const row = rows.get(project.id);
  if (!row) return;
  const key = requireKey((message) => setRowMessage(row, message, "warn"));
  if (!key) return;
  setBusy(true);
  try {
    await provisionOne(project, key, options);
  } finally {
    setBusy(false);
  }
}

/** The shared body of Enable, Repair and Enable-all. Never throws on a 403. */
async function provisionOne(project: AdoProject, key: string, options: { repair: boolean }): Promise<boolean> {
  const row = rows.get(project.id);
  if (!row) return false;
  const url = hookUrlFor(state.relayUrl, state.org);
  setRowMessage(row, "Reading subscriptions…");
  try {
    const all = await listWebhookSubscriptions(state.org);
    state.subs = all;
    state.subsError = undefined;
    const { toCreate, toDelete } = reconcile({ subs: all, projectId: project.id, url, repair: options.repair });
    let kept = oursFor(all, { projectId: project.id, url }).filter((sub) => !toDelete.includes(sub));

    let done = 0;
    for (const sub of toDelete) {
      done += 1;
      setRowMessage(row, `Deleting ${done} of ${toDelete.length}…`);
      if (sub.id) await deleteSubscription(state.org, sub.id);
    }
    done = 0;
    for (const plan of toCreate) {
      done += 1;
      setRowMessage(row, `Creating ${planKind(plan)} (${done} of ${toCreate.length})…`);
      const created = await createSubscription(
        state.org,
        subscriptionBody({ plan, projectId: project.id, url, secret: key }),
      );
      kept = [...kept, created];
    }

    replaceSubs(project.id, url, kept);
    refreshRowCounts();

    setRowMessage(row, "Registering with the relay…");
    const registryRows = registryRowsFor(kept, { projectId: project.id, projectName: project.name });
    const result = await relayClient().putProjectSubscriptions(key, project.id, registryRows);
    state.registry = await relayClient().listSubscriptions(key);
    refreshRowCounts();
    setRowMessage(
      row,
      `${kept.length} of ${planned} hooks in Azure DevOps, ${result.subscriptions} registered with the relay.`,
      kept.length === planned ? "ok" : "warn",
    );
    return true;
  } catch (error) {
    if (error instanceof AdoError && error.isForbidden) {
      setRowMessage(row, "You are not a project administrator here.", "error");
      return false;
    }
    if (error instanceof RelayError && error.isUnknownOrgOrKey) {
      setRowMessage(row, "The relay does not know this organization or the key is wrong.", "error");
      return false;
    }
    setRowMessage(row, messageOf(error), "error");
    return false;
  }
}

async function removeProject(project: AdoProject): Promise<void> {
  const row = rows.get(project.id);
  if (!row) return;
  const key = requireKey((message) => setRowMessage(row, message, "warn"));
  if (!key) return;
  const url = hookUrlFor(state.relayUrl, state.org);
  setBusy(true);
  try {
    const all = await listWebhookSubscriptions(state.org);
    state.subs = all;
    const ours = oursFor(all, { projectId: project.id, url });
    let done = 0;
    for (const sub of ours) {
      done += 1;
      setRowMessage(row, `Deleting ${done} of ${ours.length}…`);
      if (sub.id) await deleteSubscription(state.org, sub.id);
    }
    replaceSubs(project.id, url, []);
    refreshRowCounts();

    setRowMessage(row, "Removing from the relay…");
    const result = await relayClient().deleteProjectSubscriptions(key, project.id);
    state.registry = await relayClient().listSubscriptions(key);
    refreshRowCounts();
    setRowMessage(row, `Removed ${ours.length} hooks and ${result.removed} relay rows.`, "ok");
  } catch (error) {
    if (error instanceof AdoError && error.isForbidden) setRowMessage(row, "You are not a project administrator here.", "error");
    else setRowMessage(row, messageOf(error), "error");
  } finally {
    setBusy(false);
  }
}

async function enableAllProjects(): Promise<void> {
  const key = requireKey((message) => setStatus(relayStatus, message, "warn"));
  if (!key) return;
  setBusy(true);
  try {
    let ok = 0;
    for (const row of [...rows.values()]) {
      setStatus(relayStatus, `Enabling ${row.project.name}…`, "muted");
      if (await provisionOne(row.project, key, { repair: false })) ok += 1;
    }
    setStatus(relayStatus, `Enabled ${ok} of ${rows.size} projects.`, ok === rows.size ? "ok" : "warn");
  } finally {
    setBusy(false);
  }
}

async function refresh(): Promise<void> {
  setBusy(true);
  try {
    await loadProjects();
    await loadSubscriptions();
    const key = keyInput.value.trim();
    if (key !== "") {
      try {
        state.registry = await relayClient().listSubscriptions(key);
      } catch {
        state.registry = undefined;
      }
    }
    refreshRowCounts();
  } finally {
    setBusy(false);
  }
}

async function loadProjects(): Promise<void> {
  try {
    state.projects = await listProjects(state.org);
    projectsNote.textContent = state.scopedProject
      ? "Hooks are created for this project only."
      : `${state.projects.length} project${state.projects.length === 1 ? "" : "s"} in this organization.`;
    projectsNote.className = "status status-muted";
  } catch (error) {
    state.projects = state.scopedProject ? [{ id: state.scopedProject.id, name: state.scopedProject.name }] : [];
    setStatus(projectsNote, `Could not list projects: ${messageOf(error)}`, "error");
  }
  renderRows();
}

async function loadSubscriptions(): Promise<void> {
  try {
    state.subs = await listWebhookSubscriptions(state.org);
    state.subsError = undefined;
  } catch (error) {
    state.subs = [];
    state.subsError = messageOf(error);
    setStatus(
      projectsNote,
      `Could not read service hook subscriptions: ${state.subsError}. A Project Collection Administrator can.`,
      "error",
    );
  }
  refreshRowCounts();
}

// ----------------------------------------------------------------------- boot

async function main(): Promise<void> {
  await SDK.init({ applyTheme: true, loaded: false });
  await SDK.ready();

  state.org = SDK.getHost().name;
  try {
    // Present only in the project hub; `getWebContext` throws rather than
    // returning undefined when the host sent no page context at all.
    const project = SDK.getWebContext()?.project;
    if (project && project.id) state.scopedProject = { id: project.id, name: project.name };
  } catch {
    // Organization hub: no project scope.
  }

  const settings = await loadSettings();
  state.relayUrl = trimTrailingSlashes(settings.relayUrl);
  state.updatedAt = settings.updatedAt;
  state.updatedBy = settings.updatedBy;

  buildShell();
  relayUrlInput.value = state.relayUrl;
  renderSettingsNote();
  renderRows();

  SDK.notifyLoadSucceeded();

  await loadProjects();
  await loadSubscriptions();
  SDK.resize();
}

main().catch((error: unknown) => {
  const app = document.getElementById("app");
  if (app) {
    app.textContent = "";
    app.append(
      el("section", { className: "card" }, [
        el("h2", { text: "Boardhop could not start" }),
        el("p", { className: "status status-error", text: messageOf(error) }),
      ]),
    );
  }
  try {
    SDK.notifyLoadFailed(messageOf(error));
  } catch {
    // The handshake itself failed; nothing to notify.
  }
});
