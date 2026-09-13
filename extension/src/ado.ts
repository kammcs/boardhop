/**
 * The Azure DevOps half: projects and service-hook subscriptions.
 *
 * These go over `fetch` with the extension's own access token rather than
 * through the REST clients in `azure-devops-extension-api`, for two reasons:
 * that package ships AMD modules only (esbuild resolves its imports to
 * `undefined`), and its generated clients pin `api-version=7.2-preview.1` while
 * every proven request body in this repo is pinned to 7.1 (CLAUDE.md). The auth
 * and base-url handling below is exactly what `Common/Client.js` does:
 * `Bearer ${await SDK.getAccessToken()}` against the location service's url.
 */

import * as SDK from "azure-devops-extension-sdk";
import type { ILocationService } from "azure-devops-extension-api/Common/CommonServices";

import { AdoSubscription, apiVersion } from "./plan";

/** Contribution id of the host's location service. */
export const locationServiceId = "ms.vss-features.location-service";

/** A call to Azure DevOps that did not answer 2xx. */
export class AdoError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = "AdoError";
  }

  /** The caller is signed in but is not an administrator of this project. */
  get isForbidden(): boolean {
    return this.status === 403;
  }
}

export interface AdoProject {
  id: string;
  name: string;
  description?: string;
}

let cachedBaseUrl: string | undefined;
let cachedToken: { value: string; at: number } | undefined;

/**
 * The organization's REST base url, ending in a slash.
 *
 * The location service knows it for every host shape (dev.azure.com, a legacy
 * visualstudio.com account, Azure DevOps Server); `https://dev.azure.com/{org}/`
 * is only the fallback for when that call is unavailable.
 */
export async function orgBaseUrl(org: string): Promise<string> {
  if (cachedBaseUrl) return cachedBaseUrl;
  try {
    const location = await SDK.getService<ILocationService>(locationServiceId);
    const url = await location.getServiceLocation();
    // Only trust an answer that looks like an Azure DevOps Services host; the
    // signature of `getServiceLocation()` with no arguments is the host's own
    // location, but a surprise here would send 14 writes to the wrong place.
    if (url && /^https:\/\/([^/]+\.)?(dev\.azure\.com|visualstudio\.com)\//i.test(url.endsWith("/") ? url : `${url}/`)) {
      cachedBaseUrl = url.endsWith("/") ? url : `${url}/`;
      return cachedBaseUrl;
    }
  } catch {
    // Fall through to the well-known hosted url.
  }
  cachedBaseUrl = `https://dev.azure.com/${encodeURIComponent(org)}/`;
  return cachedBaseUrl;
}

/** The extension's access token, reused for a minute so a 14-call run is quick. */
async function accessToken(): Promise<string> {
  const now = Date.now();
  if (cachedToken && now - cachedToken.at < 60_000) return cachedToken.value;
  const value = await SDK.getAccessToken();
  cachedToken = { value, at: now };
  return value;
}

interface AdoRequest {
  method: string;
  path: string;
  query?: Record<string, string | undefined>;
  body?: unknown;
  org: string;
}

/** One REST call, with the api-version pinned and the body decoded. */
async function call<T>(request: AdoRequest): Promise<{ json: T; headers: Headers }> {
  const base = await orgBaseUrl(request.org);
  const url = new URL(request.path, base);
  url.searchParams.set("api-version", apiVersion);
  for (const [key, value] of Object.entries(request.query ?? {})) {
    if (value !== undefined && value !== "") url.searchParams.set(key, value);
  }

  const headers: Record<string, string> = {
    Authorization: `Bearer ${await accessToken()}`,
    Accept: "application/json",
  };
  if (request.body !== undefined) headers["Content-Type"] = "application/json";

  let response: Response;
  try {
    response = await fetch(url.toString(), {
      method: request.method,
      headers,
      body: request.body === undefined ? undefined : JSON.stringify(request.body),
    });
  } catch (error) {
    throw new AdoError(`could not reach Azure DevOps: ${error instanceof Error ? error.message : String(error)}`, 0);
  }

  const text = await response.text();
  if (!response.ok) {
    // Azure DevOps puts a human sentence in `message`; anything else is noise.
    let message = `HTTP ${response.status}`;
    try {
      const parsed = JSON.parse(text) as { message?: string };
      if (parsed && typeof parsed.message === "string" && parsed.message.trim() !== "") message = parsed.message.trim();
    } catch {
      // Not JSON: keep the status line.
    }
    throw new AdoError(message, response.status);
  }
  const json = (text === "" ? {} : JSON.parse(text)) as T;
  return { json, headers: response.headers };
}

/** Every project in the organization the caller can see. */
export async function listProjects(org: string): Promise<AdoProject[]> {
  const projects: AdoProject[] = [];
  let continuationToken: string | undefined;
  do {
    const { json, headers } = await call<{ value?: AdoProject[] }>({
      org,
      method: "GET",
      path: "_apis/projects",
      query: { $top: "500", continuationToken },
    });
    for (const project of json.value ?? []) {
      if (project && project.id && project.name) projects.push({ id: project.id, name: project.name });
    }
    continuationToken = headers.get("x-ms-continuationtoken") ?? undefined;
  } while (continuationToken);
  return projects.sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Every webhook subscription in the organization.
 *
 * There is no project filter on this route, so the caller narrows on
 * `publisherInputs.projectId` and `consumerInputs.url` (`oursFor` in plan.ts).
 */
export async function listWebhookSubscriptions(org: string): Promise<AdoSubscription[]> {
  const { json } = await call<{ value?: AdoSubscription[] }>({
    org,
    method: "GET",
    path: "_apis/hooks/subscriptions",
    query: { consumerId: "webHooks" },
  });
  return json.value ?? [];
}

/** Creates one subscription from the body `plan.ts` builds. */
export async function createSubscription(org: string, body: Record<string, unknown>): Promise<AdoSubscription> {
  const { json } = await call<AdoSubscription>({ org, method: "POST", path: "_apis/hooks/subscriptions", body });
  return json;
}

/** Deletes one subscription by id. */
export async function deleteSubscription(org: string, subscriptionId: string): Promise<void> {
  await call<unknown>({ org, method: "DELETE", path: `_apis/hooks/subscriptions/${encodeURIComponent(subscriptionId)}` });
}
