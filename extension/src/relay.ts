/**
 * The relay half: the three hook-authenticated routes the hub calls.
 *
 * Pure `fetch`, no SDK, so `node --test` covers it. The organization key is a
 * parameter of every call and is never stored, logged or put in a message: it
 * exists for the length of the request that carries it.
 *
 *   GET    /v1/orgs/{org}/subscriptions
 *   PUT    /v1/orgs/{org}/projects/{projectId}/subscriptions
 *   DELETE /v1/orgs/{org}/projects/{projectId}/subscriptions
 *
 * Every authentication failure answers 404 with an empty object, so the routes
 * cannot be probed - which is why a 404 is reported as "unknown organization or
 * wrong key" rather than as a missing route.
 */

import { RegistryRow, trimTrailingSlashes } from "./plan";

/** Basic-auth username the relay's ingest and admin routes expect. */
export const relayUsername = "hook";

/** base64 of an ASCII string, in the browser and in node. */
function base64(text: string): string {
  const globalBtoa = (globalThis as { btoa?: (data: string) => string }).btoa;
  if (globalBtoa) return globalBtoa(text);
  // Node's test runner has no btoa in every version; Buffer always works.
  const bufferCtor = (globalThis as { Buffer?: { from(s: string, e: string): { toString(e: string): string } } }).Buffer;
  if (bufferCtor) return bufferCtor.from(text, "utf-8").toString("base64");
  throw new Error("no base64 encoder available");
}

/** `Basic base64("hook:" + key)` - the header every relay call carries. */
export function basicAuthHeader(key: string): string {
  return `Basic ${base64(`${relayUsername}:${key}`)}`;
}

/** A relay call that did not answer 2xx. */
export class RelayError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = "RelayError";
  }

  /** True when the relay answered its "everything I refuse" 404. */
  get isUnknownOrgOrKey(): boolean {
    return this.status === 404;
  }
}

/** What `GET /v1/orgs/{org}/subscriptions` answers. */
export interface RelayRegistry {
  org: string;
  subscriptions: RegistryRow[];
}

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export interface RelayClientOptions {
  relayUrl: string;
  org: string;
  /** Injected by the tests; the hub passes the window's own `fetch`. */
  fetchImpl?: FetchLike;
}

export class RelayClient {
  private readonly base: string;
  private readonly org: string;
  private readonly doFetch: FetchLike;

  constructor(options: RelayClientOptions) {
    this.base = trimTrailingSlashes(options.relayUrl);
    this.org = options.org;
    this.doFetch = options.fetchImpl ?? ((input, init) => fetch(input, init));
  }

  /** The org's whole registry, as the relay has it. */
  async listSubscriptions(key: string): Promise<RelayRegistry> {
    const json = await this.send("GET", `/v1/orgs/${encodeURIComponent(this.org)}/subscriptions`, key);
    const rows = Array.isArray((json as RelayRegistry).subscriptions) ? (json as RelayRegistry).subscriptions : [];
    return { org: this.org, subscriptions: rows };
  }

  /** Replaces this project's rows; every other project's are left alone. */
  async putProjectSubscriptions(
    key: string,
    projectId: string,
    rows: readonly RegistryRow[],
  ): Promise<{ subscriptions: number; total: number }> {
    const json = (await this.send("PUT", this.projectPath(projectId), key, rows)) as Record<string, unknown>;
    return { subscriptions: numberOf(json["subscriptions"]), total: numberOf(json["total"]) };
  }

  /** Takes this project's rows out of the registry. */
  async deleteProjectSubscriptions(key: string, projectId: string): Promise<{ removed: number; total: number }> {
    const json = (await this.send("DELETE", this.projectPath(projectId), key)) as Record<string, unknown>;
    return { removed: numberOf(json["removed"]), total: numberOf(json["total"]) };
  }

  private projectPath(projectId: string): string {
    return `/v1/orgs/${encodeURIComponent(this.org)}/projects/${encodeURIComponent(projectId)}/subscriptions`;
  }

  private async send(method: string, path: string, key: string, body?: unknown): Promise<unknown> {
    const headers: Record<string, string> = {
      Authorization: basicAuthHeader(key),
      Accept: "application/json",
    };
    if (body !== undefined) headers["Content-Type"] = "application/json";

    let response: Response;
    try {
      response = await this.doFetch(`${this.base}${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch (error) {
      throw new RelayError(`could not reach ${this.base}: ${messageOf(error)}`, 0);
    }

    const text = await response.text();
    let json: unknown = undefined;
    try {
      json = text === "" ? {} : JSON.parse(text);
    } catch {
      json = undefined;
    }
    if (!response.ok) {
      throw new RelayError(
        response.status === 404
          ? "the relay does not know this organization, or the key is wrong"
          : `the relay answered HTTP ${response.status}`,
        response.status,
      );
    }
    return json ?? {};
  }
}

function numberOf(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** How many of an org's registry rows belong to one project. */
export function relayCountFor(registry: RelayRegistry | undefined, projectId: string): number | undefined {
  if (!registry) return undefined;
  return registry.subscriptions.filter((row) => row.projectId === projectId).length;
}
