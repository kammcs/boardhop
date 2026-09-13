/**
 * The extension data store: the one document this extension persists.
 *
 * `{ relayUrl, updatedAt, updatedBy }` at collection scope, so every
 * administrator of the organization - and the mobile app, which reads the same
 * document with the user's own token - sees the same relay. The organization
 * key is deliberately **not** here: it is never persisted anywhere, by anyone.
 */

import * as SDK from "azure-devops-extension-sdk";
import type { IExtensionDataManager, IExtensionDataService } from "azure-devops-extension-api/Common/CommonServices";

import { defaultRelayUrl } from "./plan";

/** Contribution id of the host's extension data service. */
export const extensionDataServiceId = "ms.vss-features.extension-data-service";

/** The collection the settings document lives in. */
export const settingsCollection = "boardhop";

/** The document id. One document, organization-wide. */
export const settingsDocumentId = "settings";

export interface Settings {
  id: string;
  relayUrl: string;
  updatedAt?: string;
  updatedBy?: string;
}

/** Collection scope: one document for the whole organization. */
const documentOptions = { scopeType: "Default", scopeValue: "Current" };

let manager: Promise<IExtensionDataManager> | undefined;

function dataManager(): Promise<IExtensionDataManager> {
  if (!manager) {
    manager = (async () => {
      const service = await SDK.getService<IExtensionDataService>(extensionDataServiceId);
      return service.getExtensionDataManager(SDK.getExtensionContext().id, await SDK.getAccessToken());
    })();
  }
  return manager;
}

/**
 * The stored settings, or the defaults when nothing has been saved yet.
 *
 * A missing document is a 404 from the data service, which is the normal state
 * of a freshly installed extension, so it is not an error.
 */
export async function loadSettings(): Promise<Settings> {
  try {
    const manager = await dataManager();
    const doc = (await manager.getDocument(settingsCollection, settingsDocumentId, documentOptions)) as
      | Partial<Settings>
      | undefined;
    const relayUrl = typeof doc?.relayUrl === "string" && doc.relayUrl.trim() !== "" ? doc.relayUrl.trim() : defaultRelayUrl;
    return { id: settingsDocumentId, relayUrl, updatedAt: doc?.updatedAt, updatedBy: doc?.updatedBy };
  } catch {
    return { id: settingsDocumentId, relayUrl: defaultRelayUrl };
  }
}

/** Writes the relay url, stamped with who changed it and when. */
export async function saveSettings(relayUrl: string): Promise<Settings> {
  let updatedBy = "";
  try {
    const user = SDK.getUser();
    updatedBy = user?.displayName || user?.name || "";
  } catch {
    // `getUser` throws when the host sent no user context; the stamp is optional.
  }
  const doc: Settings = {
    id: settingsDocumentId,
    relayUrl: relayUrl.trim(),
    updatedAt: new Date().toISOString(),
    updatedBy,
  };
  const manager = await dataManager();
  const saved = (await manager.setDocument(settingsCollection, doc, documentOptions)) as Settings;
  return saved ?? doc;
}
