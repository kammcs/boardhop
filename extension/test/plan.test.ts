import assert from "node:assert/strict";
import { test } from "node:test";

import {
  AdoSubscription,
  activeFilters,
  hookUrlFor,
  hookUrlPrefix,
  isHealthy,
  kindFor,
  matchesPlan,
  oursFor,
  planKind,
  plannedEventIdCount,
  plannedSubscriptions,
  prNotificationTypes,
  reconcile,
  registryRowsFor,
  subscriptionBody,
  worstStatus,
} from "../src/plan";

const projectId = "11111111-2222-3333-4444-555555555555";
const url = "https://boardhop.relay.kammcs.com/hooks/puremedia";

/** A subscription as Azure DevOps returns it, for the matcher tests. */
function sub(options: {
  eventType: string;
  inputs?: Record<string, string>;
  url?: string;
  status?: string;
  id?: string;
}): AdoSubscription {
  return {
    id: options.id ?? "sub-1",
    eventType: options.eventType,
    status: options.status ?? "enabled",
    publisherInputs: { projectId, ...(options.inputs ?? {}) },
    consumerInputs: { url: options.url ?? url },
  };
}

test("the plan is 14 subscriptions over 11 distinct event ids", () => {
  assert.equal(plannedSubscriptions.length, 14);
  assert.equal(plannedEventIdCount(), 11);
  assert.equal(prNotificationTypes.length, 4);
  const updated = plannedSubscriptions.filter((plan) => plan.eventType === "git.pullrequest.updated");
  assert.equal(updated.length, 4);
  assert.deepEqual(
    updated.map((plan) => plan.filters["notificationType"]),
    ["PushNotification", "ReviewersUpdateNotification", "StatusUpdateNotification", "ReviewerVoteNotification"],
  );
});

test("every planned row maps to the routing label the relay expects", () => {
  assert.deepEqual(plannedSubscriptions.map(planKind), [
    "pr.created",
    "pr.updated.push",
    "pr.updated.reviewers",
    "pr.updated.status",
    "pr.updated.vote",
    "pr.comment",
    "pr.merged",
    "wi.created",
    "wi.updated",
    "wi.commented",
    "build.complete",
    "run.state",
    "approval.pending",
    "approval.completed",
  ]);
});

test("the plan does not subscribe to stage.state, which the relay still knows", () => {
  assert.equal(
    plannedSubscriptions.some((plan) => plan.eventType === "ms.vss-pipelines.stage-state-changed-event"),
    false,
  );
  assert.equal(kindFor("ms.vss-pipelines.stage-state-changed-event"), "stage.state");
});

test("the work item rows are created at resourceVersion 5.1-preview.3 (w27/w28)", () => {
  const workItemRows = plannedSubscriptions.filter((plan) => plan.eventType.startsWith("workitem."));
  assert.equal(workItemRows.length, 3);
  for (const plan of workItemRows) assert.equal(plan.resourceVersion, "5.1-preview.3");
});

test("every other resourceVersion matches the proven set", () => {
  const versions = new Map(plannedSubscriptions.map((plan) => [planKind(plan), plan.resourceVersion]));
  assert.equal(versions.get("pr.created"), "1.0");
  assert.equal(versions.get("pr.updated.vote"), "1.0");
  assert.equal(versions.get("pr.comment"), "2.0");
  assert.equal(versions.get("pr.merged"), "1.0");
  assert.equal(versions.get("build.complete"), "2.0");
  assert.equal(versions.get("run.state"), "5.1-preview.1");
  assert.equal(versions.get("approval.pending"), "5.1-preview.1");
  assert.equal(versions.get("approval.completed"), "5.1-preview.1");
});

test("pr.merged is narrowed to failed merges only (w24)", () => {
  const merged = plannedSubscriptions.find((plan) => plan.eventType === "git.pullrequest.merged");
  assert.ok(merged);
  assert.deepEqual(activeFilters(merged), { mergeResult: "Unsuccessful" });
});

test("kindFor falls back to the event's single kind for an unknown filter value", () => {
  assert.equal(kindFor("workitem.updated", "Whatever"), "wi.updated");
  // git.pullrequest.updated has no unfiltered kind, so it stays unroutable.
  assert.equal(kindFor("git.pullrequest.updated"), undefined);
  assert.equal(kindFor("git.pullrequest.updated", ""), undefined);
  assert.equal(kindFor("git.pullrequest.updated", "ReviewerVoteNotification"), "pr.updated.vote");
  assert.equal(kindFor("not.an.event"), undefined);
});

test("subscriptionBody is exactly the shape hooks_lib.dart produces", () => {
  const plan = plannedSubscriptions.find((p) => planKind(p) === "pr.updated.vote");
  assert.ok(plan);
  assert.deepEqual(subscriptionBody({ plan, projectId, url, secret: "s3cret" }), {
    publisherId: "tfs",
    eventType: "git.pullrequest.updated",
    resourceVersion: "1.0",
    consumerId: "webHooks",
    consumerActionId: "httpRequest",
    publisherInputs: {
      projectId,
      repository: "",
      branch: "",
      pullrequestCreatedBy: "",
      pullrequestReviewersContains: "",
      notificationType: "ReviewerVoteNotification",
    },
    consumerInputs: {
      url,
      basicAuthUsername: "hook",
      basicAuthPassword: "s3cret",
      resourceDetailsToSend: "all",
      messagesToSend: "text",
      detailedMessagesToSend: "text",
    },
  });
});

test("subscriptionBody sends every publisher input, empty for any", () => {
  const plan = plannedSubscriptions.find((p) => planKind(p) === "wi.updated");
  assert.ok(plan);
  const body = subscriptionBody({ plan, projectId, url, secret: "k" }) as {
    publisherInputs: Record<string, string>;
  };
  assert.deepEqual(body.publisherInputs, { projectId, areaPath: "", workItemType: "", changedFields: "" });
});

test("hook urls drop trailing slashes", () => {
  assert.equal(hookUrlFor("https://boardhop.relay.kammcs.com///", "puremedia"), url);
  assert.equal(hookUrlPrefix("https://boardhop.relay.kammcs.com/"), "https://boardhop.relay.kammcs.com/hooks/");
});

test("matchesPlan: a narrowed pr.updated matches only its own plan row", () => {
  const vote = plannedSubscriptions.find((p) => planKind(p) === "pr.updated.vote")!;
  const push = plannedSubscriptions.find((p) => planKind(p) === "pr.updated.push")!;
  const existing = sub({
    eventType: "git.pullrequest.updated",
    inputs: { notificationType: "ReviewerVoteNotification", repository: "" },
  });
  assert.equal(matchesPlan(existing, vote, { projectId, url }), true);
  assert.equal(matchesPlan(existing, push, { projectId, url }), false);
});

test("matchesPlan: an unnarrowed plan does not match a narrowed subscription", () => {
  const created = plannedSubscriptions.find((p) => planKind(p) === "pr.created")!;
  const narrowed = sub({ eventType: "git.pullrequest.created", inputs: { notificationType: "PushNotification" } });
  const plainOne = sub({ eventType: "git.pullrequest.created" });
  assert.equal(matchesPlan(narrowed, created, { projectId, url }), false);
  assert.equal(matchesPlan(plainOne, created, { projectId, url }), true);
});

test("matchesPlan: a different project or a different url never matches", () => {
  const created = plannedSubscriptions.find((p) => planKind(p) === "pr.created")!;
  const otherProject: AdoSubscription = {
    ...sub({ eventType: "git.pullrequest.created" }),
    publisherInputs: { projectId: "99999999-0000-0000-0000-000000000000" },
  };
  const otherUrl = sub({ eventType: "git.pullrequest.created", url: "https://example.invalid/hooks/puremedia" });
  assert.equal(matchesPlan(otherProject, created, { projectId, url }), false);
  assert.equal(matchesPlan(otherUrl, created, { projectId, url }), false);
});

test("matchesPlan: ignores filters the plan leaves as any", () => {
  const merged = plannedSubscriptions.find((p) => planKind(p) === "pr.merged")!;
  const handMade = sub({ eventType: "git.pullrequest.merged", inputs: { mergeResult: "Unsuccessful" } });
  assert.equal(matchesPlan(handMade, merged, { projectId, url }), true);
  const wrongResult = sub({ eventType: "git.pullrequest.merged", inputs: { mergeResult: "Succeeded" } });
  assert.equal(matchesPlan(wrongResult, merged, { projectId, url }), false);
});

test("oursFor keeps only this project's subscriptions on this relay", () => {
  const mine = sub({ eventType: "workitem.created" });
  const elsewhere = sub({ eventType: "workitem.created", url: "https://example.invalid/hooks/other" });
  assert.deepEqual(oursFor([mine, elsewhere], { projectId, url }), [mine]);
});

test("reconcile on an empty project creates all 14 and deletes nothing", () => {
  const { toCreate, toDelete } = reconcile({ subs: [], projectId, url, repair: false });
  assert.equal(toCreate.length, 14);
  assert.equal(toDelete.length, 0);
});

test("reconcile without repair leaves an unhealthy subscription alone", () => {
  const broken = sub({ eventType: "workitem.created", status: "disabledBySystem" });
  const enable = reconcile({ subs: [broken], projectId, url, repair: false });
  assert.equal(enable.toCreate.length, 13);
  assert.equal(enable.toDelete.length, 0);

  const repair = reconcile({ subs: [broken], projectId, url, repair: true });
  assert.equal(repair.toCreate.length, 14);
  assert.deepEqual(repair.toDelete, [broken]);
});

test("repair deletes duplicates and anything of ours that matches no plan row", () => {
  const first = sub({ eventType: "workitem.created", id: "a" });
  const duplicate = sub({ eventType: "workitem.created", id: "b" });
  const stray = sub({ eventType: "ms.vss-pipelines.stage-state-changed-event", id: "c" });
  const { toCreate, toDelete } = reconcile({ subs: [first, duplicate, stray], projectId, url, repair: true });
  assert.equal(toCreate.length, 13);
  assert.deepEqual(
    toDelete.map((s) => s.id),
    ["b", "c"],
  );
});

test("registryRowsFor labels every subscription the relay routes", () => {
  const rows = registryRowsFor(
    [
      sub({ eventType: "git.pullrequest.updated", inputs: { notificationType: "PushNotification" }, id: "a" }),
      sub({ eventType: "git.pullrequest.updated", id: "b" }),
      sub({ eventType: "build.complete", id: "c" }),
    ],
    { projectId, projectName: "DevOps Mobile App" },
  );
  assert.deepEqual(rows, [
    {
      subId: "a",
      eventType: "git.pullrequest.updated",
      kind: "pr.updated.push",
      projectId,
      projectName: "DevOps Mobile App",
    },
    { subId: "c", eventType: "build.complete", kind: "build.complete", projectId, projectName: "DevOps Mobile App" },
  ]);
});

test("worstStatus reports the worst state, and isHealthy only accepts enabled", () => {
  assert.equal(worstStatus([]), undefined);
  assert.equal(worstStatus([sub({ eventType: "build.complete" })]), "enabled");
  assert.equal(
    worstStatus([
      sub({ eventType: "build.complete" }),
      sub({ eventType: "workitem.created", status: "onProbation" }),
      sub({ eventType: "workitem.updated", status: "disabledBySystem" }),
    ]),
    "disabledBySystem",
  );
  assert.equal(isHealthy(sub({ eventType: "build.complete" })), true);
  assert.equal(isHealthy(sub({ eventType: "build.complete", status: "onProbation" })), false);
});
