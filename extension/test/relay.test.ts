import assert from "node:assert/strict";
import { test } from "node:test";

import { RegistryRow } from "../src/plan";
import { RelayClient, RelayError, basicAuthHeader, relayCountFor } from "../src/relay";

const relayUrl = "https://boardhop.relay.kammcs.com";
const org = "puremedia";
const projectId = "11111111-2222-3333-4444-555555555555";

interface Call {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
}

/** A fetch that records what it was given and answers a canned response. */
function fakeFetch(status: number, payload: unknown, calls: Call[]) {
  return async (url: string, init?: RequestInit): Promise<Response> => {
    calls.push({
      url,
      method: init?.method ?? "GET",
      headers: (init?.headers ?? {}) as Record<string, string>,
      body: typeof init?.body === "string" ? init.body : undefined,
    });
    return new Response(JSON.stringify(payload), { status, headers: { "content-type": "application/json" } });
  };
}

test("the relay credential is Basic base64 of hook:key", () => {
  assert.equal(basicAuthHeader("abc123"), `Basic ${Buffer.from("hook:abc123", "utf-8").toString("base64")}`);
  assert.equal(basicAuthHeader("abc123"), "Basic aG9vazphYmMxMjM=");
});

test("listSubscriptions GETs the org route and returns its rows", async () => {
  const calls: Call[] = [];
  const rows: RegistryRow[] = [
    { subId: "a", eventType: "workitem.updated", kind: "wi.updated", projectId, projectName: "DevOps Mobile App" },
  ];
  const client = new RelayClient({
    relayUrl: `${relayUrl}/`,
    org,
    fetchImpl: fakeFetch(200, { org, subscriptions: rows }, calls),
  });

  const registry = await client.listSubscriptions("k3y");

  assert.deepEqual(registry.subscriptions, rows);
  assert.equal(calls.length, 1);
  assert.equal(calls[0]!.url, `${relayUrl}/v1/orgs/puremedia/subscriptions`);
  assert.equal(calls[0]!.method, "GET");
  assert.equal(calls[0]!.headers["Authorization"], basicAuthHeader("k3y"));
});

test("putProjectSubscriptions PUTs the project route with the rows as the body", async () => {
  const calls: Call[] = [];
  const rows: RegistryRow[] = [
    { subId: "a", eventType: "build.complete", kind: "build.complete", projectId, projectName: "P" },
  ];
  const client = new RelayClient({
    relayUrl,
    org,
    fetchImpl: fakeFetch(200, { org, projectId, subscriptions: 1, total: 14 }, calls),
  });

  const result = await client.putProjectSubscriptions("k3y", projectId, rows);

  assert.deepEqual(result, { subscriptions: 1, total: 14 });
  assert.equal(calls[0]!.method, "PUT");
  assert.equal(calls[0]!.url, `${relayUrl}/v1/orgs/puremedia/projects/${projectId}/subscriptions`);
  assert.equal(calls[0]!.headers["Content-Type"], "application/json");
  assert.deepEqual(JSON.parse(calls[0]!.body ?? "null"), rows);
});

test("deleteProjectSubscriptions DELETEs the project route", async () => {
  const calls: Call[] = [];
  const client = new RelayClient({
    relayUrl,
    org,
    fetchImpl: fakeFetch(200, { org, projectId, removed: 14, total: 0 }, calls),
  });

  const result = await client.deleteProjectSubscriptions("k3y", projectId);

  assert.deepEqual(result, { removed: 14, total: 0 });
  assert.equal(calls[0]!.method, "DELETE");
  assert.equal(calls[0]!.url, `${relayUrl}/v1/orgs/puremedia/projects/${projectId}/subscriptions`);
  assert.equal(calls[0]!.body, undefined);
});

test("an auth failure is the relay's 404, reported as unknown org or wrong key", async () => {
  const calls: Call[] = [];
  const client = new RelayClient({ relayUrl, org, fetchImpl: fakeFetch(404, {}, calls) });

  await assert.rejects(
    () => client.listSubscriptions("wrong"),
    (error: unknown) => {
      assert.ok(error instanceof RelayError);
      assert.equal(error.status, 404);
      assert.equal(error.isUnknownOrgOrKey, true);
      assert.match(error.message, /does not know this organization/);
      return true;
    },
  );
});

test("any other status is reported with its code", async () => {
  const client = new RelayClient({ relayUrl, org, fetchImpl: fakeFetch(500, {}, []) });
  await assert.rejects(
    () => client.listSubscriptions("k"),
    (error: unknown) => error instanceof RelayError && error.status === 500 && !error.isUnknownOrgOrKey,
  );
});

test("an unreachable relay is a RelayError with status 0 and no key in the message", async () => {
  const client = new RelayClient({
    relayUrl,
    org,
    fetchImpl: async () => {
      throw new Error("getaddrinfo ENOTFOUND");
    },
  });
  await assert.rejects(
    () => client.listSubscriptions("s3cret-key"),
    (error: unknown) => {
      assert.ok(error instanceof RelayError);
      assert.equal(error.status, 0);
      assert.equal(error.message.includes("s3cret-key"), false);
      return true;
    },
  );
});

test("relayCountFor counts one project's rows", () => {
  const registry = {
    org,
    subscriptions: [
      { subId: "a", eventType: "build.complete", kind: "build.complete", projectId },
      { subId: "b", eventType: "workitem.updated", kind: "wi.updated", projectId: "other" },
    ],
  };
  assert.equal(relayCountFor(registry, projectId), 1);
  assert.equal(relayCountFor(registry, "other"), 1);
  assert.equal(relayCountFor(undefined, projectId), undefined);
});
