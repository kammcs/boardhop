/**
 * The pure half of the extension: the fourteen planned service-hook
 * subscriptions, the routing label each one carries, the create body and the
 * match rule.
 *
 * This is a faithful port of `relay/tool/src/hooks_lib.dart` and
 * `relay/lib/src/hooks/hook_kind.dart`. It must stay byte-compatible with them:
 * the relay only accepts a delivery from a subscription id it has registered,
 * with a `kind` that belongs to its event type, so drift here silently stops
 * notifications. Nothing in this file imports the SDK, so `node --test` runs it.
 */

/** The Azure DevOps API version every call pins (CLAUDE.md). */
export const apiVersion = "7.1";

/** Basic-auth username of every subscription; matches the relay's ingest. */
export const hookUsername = "hook";

/** Where the relay lives unless an administrator points it elsewhere. */
export const defaultRelayUrl = "https://boardhop.relay.kammcs.com";

/** One subscription the beta wants to exist, before it has an id. */
export interface PlannedSubscription {
  readonly publisherId: string;
  readonly eventType: string;
  readonly resourceVersion: string;
  /**
   * The publisher inputs other than `projectId`: the ones that actually narrow
   * the event carry a value, every other input the publisher exposes is sent as
   * an empty string, which is what the Azure DevOps web UI sends for "any"
   * (proven by spike w21, used by w22 and w24).
   */
  readonly filters: Readonly<Record<string, string>>;
}

/** One row of `HookKind` (relay/lib/src/hooks/hook_kind.dart). */
export interface HookKindRow {
  readonly label: string;
  readonly eventType: string;
  readonly notificationType?: string;
}

/**
 * Every routing label the relay knows, in the order the enum declares them.
 * `stage.state` is listed because the relay routes it, but the beta does not
 * subscribe to it (research/14 section 1 leaves it for later).
 */
export const hookKinds: readonly HookKindRow[] = Object.freeze([
  { label: "pr.created", eventType: "git.pullrequest.created" },
  { label: "pr.updated.push", eventType: "git.pullrequest.updated", notificationType: "PushNotification" },
  {
    label: "pr.updated.reviewers",
    eventType: "git.pullrequest.updated",
    notificationType: "ReviewersUpdateNotification",
  },
  { label: "pr.updated.status", eventType: "git.pullrequest.updated", notificationType: "StatusUpdateNotification" },
  { label: "pr.updated.vote", eventType: "git.pullrequest.updated", notificationType: "ReviewerVoteNotification" },
  { label: "pr.comment", eventType: "ms.vss-code.git-pullrequest-comment-event" },
  { label: "pr.merged", eventType: "git.pullrequest.merged" },
  { label: "wi.created", eventType: "workitem.created" },
  { label: "wi.updated", eventType: "workitem.updated" },
  { label: "wi.commented", eventType: "workitem.commented" },
  { label: "build.complete", eventType: "build.complete" },
  { label: "run.state", eventType: "ms.vss-pipelines.run-state-changed-event" },
  { label: "stage.state", eventType: "ms.vss-pipelines.stage-state-changed-event" },
  { label: "approval.pending", eventType: "ms.vss-pipelinechecks-events.approval-pending" },
  { label: "approval.completed", eventType: "ms.vss-pipelinechecks-events.approval-completed" },
]);

/**
 * The kind a subscription for `eventType` with this `notificationType` filter
 * produces, or undefined when the relay would refuse the post.
 *
 * Port of `HookKind.fromEventTypeAndFilter`: an empty or absent filter means
 * "any", which only resolves for events that have a single kind; a filter value
 * the relay does not know falls back to the event's single kind, because such a
 * filter narrows nothing that matters to routing.
 */
export function kindFor(eventType: string, notificationType?: string | null): string | undefined {
  const wanted = notificationType ? notificationType : undefined;
  for (const kind of hookKinds) {
    if (kind.eventType === eventType && kind.notificationType === wanted) return kind.label;
  }
  for (const kind of hookKinds) {
    if (kind.eventType === eventType && kind.notificationType === undefined) return kind.label;
  }
  return undefined;
}

/** Filter inputs shared by the four git PR events that take reviewers. */
const prInputs: Readonly<Record<string, string>> = Object.freeze({
  repository: "",
  branch: "",
  pullrequestCreatedBy: "",
  pullrequestReviewersContains: "",
});

/** The four values `git.pullrequest.updated` accepts (spike s41). */
export const prNotificationTypes: readonly string[] = Object.freeze([
  "PushNotification",
  "ReviewersUpdateNotification",
  "StatusUpdateNotification",
  "ReviewerVoteNotification",
]);

/**
 * The beta's subscription set: **14 subscriptions over 11 distinct event ids**
 * (`git.pullrequest.updated` is subscribed four times, once per
 * `notificationType`, because the body does not say what changed).
 */
const plan: PlannedSubscription[] = [
  { publisherId: "tfs", eventType: "git.pullrequest.created", resourceVersion: "1.0", filters: { ...prInputs } },
  ...prNotificationTypes.map((notificationType) => ({
    publisherId: "tfs",
    eventType: "git.pullrequest.updated",
    resourceVersion: "1.0",
    filters: { ...prInputs, notificationType },
  })),
  {
    publisherId: "tfs",
    eventType: "ms.vss-code.git-pullrequest-comment-event",
    resourceVersion: "2.0",
    filters: { repository: "", branch: "" },
  },
  // w24: it fires on every merge *attempt*, so only the failures are wanted.
  {
    publisherId: "tfs",
    eventType: "git.pullrequest.merged",
    resourceVersion: "1.0",
    filters: { ...prInputs, mergeResult: "Unsuccessful" },
  },
  // 5.1-preview.3 is the only work item version whose identity fields
  // (AssignedTo, CreatedBy, ChangedBy) are objects with an `id`; 1.0 and
  // 3.1-preview.3 send "Name <mail>" strings (spikes w27/w28).
  {
    publisherId: "tfs",
    eventType: "workitem.created",
    resourceVersion: "5.1-preview.3",
    filters: { areaPath: "", workItemType: "" },
  },
  {
    publisherId: "tfs",
    eventType: "workitem.updated",
    resourceVersion: "5.1-preview.3",
    filters: { areaPath: "", workItemType: "", changedFields: "" },
  },
  // Subscribed, then dropped by the relay: the body names nobody by id, so the
  // matching `workitem.updated` is what notifies (research/14 section 5.2 rule 3).
  {
    publisherId: "tfs",
    eventType: "workitem.commented",
    resourceVersion: "5.1-preview.3",
    filters: { areaPath: "", workItemType: "" },
  },
  {
    publisherId: "tfs",
    eventType: "build.complete",
    resourceVersion: "2.0",
    filters: { definitionName: "", buildStatus: "" },
  },
  // Never notifies: it is the only event that gives the run's requester as an
  // identity, which the approval events need (research/14 section 1.4).
  {
    publisherId: "pipelines",
    eventType: "ms.vss-pipelines.run-state-changed-event",
    resourceVersion: "5.1-preview.1",
    filters: { pipelineId: "", runStateId: "", runResultId: "" },
  },
  {
    publisherId: "pipelines",
    eventType: "ms.vss-pipelinechecks-events.approval-pending",
    resourceVersion: "5.1-preview.1",
    filters: { pipelineId: "", stageName: "", environmentName: "" },
  },
  {
    publisherId: "pipelines",
    eventType: "ms.vss-pipelinechecks-events.approval-completed",
    resourceVersion: "5.1-preview.1",
    filters: { pipelineId: "", stageName: "", environmentName: "" },
  },
];

export const plannedSubscriptions: readonly PlannedSubscription[] = Object.freeze(plan);

/** How many distinct Azure DevOps event ids the plan covers (11 for 14 rows). */
export function plannedEventIdCount(): number {
  return new Set(plannedSubscriptions.map((plan) => plan.eventType)).size;
}

/** The `notificationType` filter, for the four PR update kinds only. */
export function notificationTypeOf(plan: PlannedSubscription): string | undefined {
  const value = plan.filters["notificationType"];
  return value ? value : undefined;
}

/** The routing label this planned subscription will be registered under. */
export function planKind(plan: PlannedSubscription): string {
  const kind = kindFor(plan.eventType, notificationTypeOf(plan));
  if (!kind) throw new Error(`no HookKind for ${plan.eventType} / ${notificationTypeOf(plan)}`);
  return kind;
}

/** The non-empty filters: the only ones `matchesPlan` compares. */
export function activeFilters(plan: PlannedSubscription): Record<string, string> {
  const active: Record<string, string> = {};
  for (const [key, value] of Object.entries(plan.filters)) {
    if (value !== "") active[key] = value;
  }
  return active;
}

/** The create body, shaped exactly like the one spikes w22/w24 proved works. */
export function subscriptionBody(options: {
  plan: PlannedSubscription;
  projectId: string;
  url: string;
  secret: string;
}): Record<string, unknown> {
  const { plan, projectId, url, secret } = options;
  return {
    publisherId: plan.publisherId,
    eventType: plan.eventType,
    resourceVersion: plan.resourceVersion,
    consumerId: "webHooks",
    consumerActionId: "httpRequest",
    publisherInputs: { projectId, ...plan.filters },
    consumerInputs: {
      url,
      basicAuthUsername: hookUsername,
      basicAuthPassword: secret,
      resourceDetailsToSend: "all",
      messagesToSend: "text",
      detailedMessagesToSend: "text",
    },
  };
}

export function trimTrailingSlashes(url: string): string {
  return url.trim().replace(/\/+$/, "");
}

/** `{relayUrl}/hooks/{org}` with no trailing slash, whatever relayUrl ends with. */
export function hookUrlFor(relayUrl: string, org: string): string {
  return `${trimTrailingSlashes(relayUrl)}/hooks/${org}`;
}

/** The prefix every org's ingest url starts with. */
export function hookUrlPrefix(relayUrl: string): string {
  return `${trimTrailingSlashes(relayUrl)}/hooks/`;
}

/** A subscription as Azure DevOps returns it; only the fields we read. */
export interface AdoSubscription {
  id?: string;
  eventType?: string;
  status?: string;
  resourceVersion?: string;
  publisherInputs?: Record<string, unknown>;
  consumerInputs?: Record<string, unknown>;
  [key: string]: unknown;
}

function str(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : undefined;
}

export function publisherInputsOf(sub: AdoSubscription): Record<string, unknown> {
  const inputs = sub.publisherInputs;
  return inputs && typeof inputs === "object" ? inputs : {};
}

export function consumerInputsOf(sub: AdoSubscription): Record<string, unknown> {
  const inputs = sub.consumerInputs;
  return inputs && typeof inputs === "object" ? inputs : {};
}

export function projectIdOf(sub: AdoSubscription): string | undefined {
  return str(publisherInputsOf(sub)["projectId"]);
}

export function consumerUrlOf(sub: AdoSubscription): string | undefined {
  return str(consumerInputsOf(sub)["url"]);
}

/**
 * True when `sub` is already the subscription `plan` would create: same event,
 * same narrowing filter, same project, same url.
 *
 * Port of `matchesPlan` in hooks_lib.dart. Only the filters the plan actually
 * narrows on are compared - a subscription created by hand with `repository`
 * left unset is still the same subscription for the relay's purposes - but a
 * plan with no narrowing filter must not match one that *is* narrowed.
 */
export function matchesPlan(
  sub: AdoSubscription,
  plan: PlannedSubscription,
  options: { projectId: string; url: string },
): boolean {
  if (str(sub.eventType) !== plan.eventType) return false;
  if (projectIdOf(sub) !== options.projectId) return false;
  if (consumerUrlOf(sub) !== options.url) return false;
  const inputs = publisherInputsOf(sub);
  const active = activeFilters(plan);
  for (const [key, value] of Object.entries(active)) {
    if (str(inputs[key]) !== value) return false;
  }
  for (const key of ["notificationType", "mergeResult"]) {
    if (!(key in active) && str(inputs[key]) !== undefined) return false;
  }
  return true;
}

/** The subscriptions of `subs` that belong to this project and this relay. */
export function oursFor(
  subs: readonly AdoSubscription[],
  options: { projectId: string; url: string },
): AdoSubscription[] {
  return subs.filter((sub) => projectIdOf(sub) === options.projectId && consumerUrlOf(sub) === options.url);
}

/** One row of the relay's registry. */
export interface RegistryRow {
  subId: string;
  eventType: string;
  kind: string;
  projectId?: string;
  projectName?: string;
}

/**
 * The registry rows for the subscriptions we own in one project: every
 * subscription whose event type and filter resolve to a kind the relay routes.
 */
export function registryRowsFor(
  subs: readonly AdoSubscription[],
  options: { projectId: string; projectName: string },
): RegistryRow[] {
  const rows: RegistryRow[] = [];
  for (const sub of subs) {
    const subId = str(sub.id);
    const eventType = str(sub.eventType);
    if (!subId || !eventType) continue;
    const kind = kindFor(eventType, str(publisherInputsOf(sub)["notificationType"]));
    if (!kind) continue;
    rows.push({ subId, eventType, kind, projectId: options.projectId, projectName: options.projectName });
  }
  return rows;
}

/** The subscription statuses Azure DevOps reports, worst last. */
const statusRank: Record<string, number> = {
  enabled: 0,
  onProbation: 1,
  disabledByUser: 2,
  disabledByInactiveIdentity: 3,
  disabledBySystem: 4,
};

/** The worst status among `subs`, or undefined when there are none. */
export function worstStatus(subs: readonly AdoSubscription[]): string | undefined {
  let worst: string | undefined;
  for (const sub of subs) {
    const status = str(sub.status) ?? "unknown";
    if (worst === undefined || (statusRank[status] ?? 9) > (statusRank[worst] ?? 9)) worst = status;
  }
  return worst;
}

/** True when a subscription is healthy; anything else is what Repair deletes. */
export function isHealthy(sub: AdoSubscription): boolean {
  return str(sub.status) === "enabled";
}

/**
 * What Enable and Repair have to do for one project.
 *
 * `toDelete` is empty unless `repair`: then it is the unhealthy subscriptions,
 * every duplicate (a second subscription matching a plan row we already have)
 * and anything of ours that matches no plan row at all.
 * `toCreate` is the plan rows nothing usable matches.
 */
export function reconcile(options: {
  subs: readonly AdoSubscription[];
  projectId: string;
  url: string;
  repair: boolean;
}): { toCreate: PlannedSubscription[]; toDelete: AdoSubscription[] } {
  const { subs, projectId, url, repair } = options;
  const ours = oursFor(subs, { projectId, url });
  const toDelete: AdoSubscription[] = [];
  const toCreate: PlannedSubscription[] = [];
  const kept = new Set<AdoSubscription>();

  for (const plan of plannedSubscriptions) {
    const matching = ours.filter((sub) => matchesPlan(sub, plan, { projectId, url }));
    if (repair) {
      // Keep the first healthy one; every other match for this row goes.
      const keeper = matching.find(isHealthy);
      for (const sub of matching) {
        if (sub !== keeper) toDelete.push(sub);
      }
      if (keeper) kept.add(keeper);
      else toCreate.push(plan);
    } else if (matching.length === 0) {
      toCreate.push(plan);
    } else {
      for (const sub of matching) kept.add(sub);
    }
  }

  if (repair) {
    // Ours that match no plan row at all (an older plan, or a hand-made one).
    for (const sub of ours) {
      if (!kept.has(sub) && !toDelete.includes(sub)) toDelete.push(sub);
    }
  }
  return { toCreate, toDelete };
}
