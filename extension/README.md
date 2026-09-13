# Boardhop Marketplace extension

The customer-side piece of the notification design (`research/06-notification-relay-and-extension.md`):
a private Azure DevOps extension that contributes a **Boardhop** hub to **Organization settings** and to
every project's **Project settings**, where an administrator connects the organization to the Boardhop
relay and creates, repairs or removes the relay's fourteen service-hook subscriptions per project.

It is the UI twin of `relay/tool/hooks.dart`: `src/plan.ts` is a faithful port of
`relay/tool/src/hooks_lib.dart` (the planned set, the create body, `matchesPlan`) and of
`relay/lib/src/hooks/hook_kind.dart` (the routing labels). If one of those changes, change this too —
the relay only accepts a delivery from a subscription id it has registered under a `kind` that belongs
to its event type, so drift here silently stops notifications.

## Layout

| file | what it is |
|---|---|
| `vss-extension.json` | the manifest: two hub contributions, three scopes, the file list |
| `hub.html` | the page shell and all of the CSS (host theme variables with fallbacks) |
| `src/plan.ts` | pure: the 14 planned subscriptions, `kindFor`, `subscriptionBody`, `matchesPlan`, `reconcile` |
| `src/relay.ts` | pure `fetch`: the three hook-authenticated relay routes |
| `src/ado.ts` | Azure DevOps REST over `fetch` with the extension's access token |
| `src/store.ts` | the one document in the Extension Data Service (`{ relayUrl, updatedAt, updatedBy }`) |
| `src/hub.ts` | the UI and the orchestration |
| `test/*.test.ts` | `node:test`; only the pure modules, so no SDK and no network |
| `overview.md` | the Marketplace listing text |

`src/plan.ts` and `src/relay.ts` import nothing but each other, which is what lets `node --test` run
them: everything that needs the SDK lives in `ado.ts`, `store.ts` and `hub.ts`.

### Why `fetch` and not the REST clients

`azure-devops-extension-api` ships **AMD** modules only. esbuild cannot consume them — it resolves
`import { getClient } from "azure-devops-extension-api"` to `undefined` with a warning and bundles a
page that fails at runtime. So the package is a **types-only** dependency here (`import type`, erased at
build time) and both the Core and the Service Hooks calls go over `fetch`, with exactly the auth and
base url `Common/Client.js` would have used: `Bearer ${await SDK.getAccessToken()}` against
`ILocationService.getServiceLocation()`. That also keeps `api-version=7.1` pinned per operation as
CLAUDE.md requires; the generated `ServiceHooksRestClient` pins `7.2-preview.1`, which no spike in this
repo has exercised.

## Build, test, package

```sh
cd extension
npm install
npm run build        # esbuild src/hub.ts -> dist/hub.js (iife, es2020)
npm test             # bundles test/*.test.ts and runs node --test
npm run typecheck    # tsc --noEmit, strict
npm run package      # build + tfx extension create -> build/KammCS.boardhop-<version>.vsix
```

`dist/`, `dist-test/`, `build/` and `node_modules/` are gitignored; the committed files are the
manifest, `package.json`, `package-lock.json`, `tsconfig.json`, `src/`, `test/`, `hub.html`, `images/`,
`overview.md` and this README.

`images/logo.png` is the 128x128 Marketplace icon, made from `assets/brand/logo.png`:

```sh
python -c "from PIL import Image; im=Image.open('assets/brand/logo.png').convert('RGBA'); im.resize((128,128), Image.LANCZOS).save('extension/images/logo.png','PNG',optimize=True)"
```

## Publish

The publisher is **KammCS** and the extension is **private**: it is installable only by organizations it
has been shared with. The token is the Marketplace PAT in the repo's gitignored `.env`
(`BOARDHOP_MARKETPLACE_PAT`, Marketplace: Manage, all organizations). Pass it on the command line;
never put it in a file in this folder.

```sh
cd extension
npx tfx-cli extension publish --manifest-globs vss-extension.json --share-with puremedia --token <BOARDHOP_MARKETPLACE_PAT>
```

Bump `version` in `vss-extension.json` for every publish (the Marketplace refuses a re-publish of the
same version); keep `package.json`'s `version` in step. `npm run publish` runs the same command without
`--token`, for when the token is already in the environment.

To share with another organization later: `npx tfx-cli extension share --publisher KammCS --extension-id boardhop --share-with <org> --token <PAT>`.

## Installing it as an organization administrator

A private extension does not appear in the Marketplace. Once kammcs has shared it with the
organization:

1. **Organization settings → Extensions → Shared** — "Boardhop" is listed there.
2. Open it, **Get it free**, pick the organization, **Install**. This needs a **Project Collection
   Administrator**; it is the step that grants the three scopes (project read, service hooks
   read/write, extension data read/write).
3. The **Boardhop** page then appears under **Organization settings**, and under every project's
   **Project settings**.

## Runbook: onboarding an organization

1. **kammcs sets the organization's hook secret on the relay.** On the box, so the plaintext never
   travels: `cd relay && dart run tool/hooks.dart secret --org <org>` writes it to
   `.hooks-secret-<org>` (mode 600, gitignored) and PUTs only its sha256 to the relay. That plaintext
   **is** the "organization key".
2. **Hand the key to the organization's administrator** over a channel you would send a password on.
   It is never stored by the extension; they type it in each session.
3. **The administrator opens the Boardhop hub** (Organization settings → Boardhop), checks that the
   relay URL is `https://boardhop.relay.kammcs.com`, pastes the key and presses **Check connection**.
   "Connected · N subscriptions registered with the relay" means the key and the org are right; the
   relay's uniform 404 ("does not know this organization or the key is wrong") is what every auth
   failure looks like, by design.
4. **Enable the projects.** **Enable all projects**, or **Enable** per project. Each one creates the
   fourteen subscriptions in Azure DevOps and registers them with the relay in one pass. A project the
   administrator is not an administrator of says so on its row and the run continues.
5. **Check the row**: 14 / 14 hooks, an `enabled` badge, and the same count under Relay.
6. Later, **Repair** deletes anything not `enabled`, any duplicate and anything of ours that no longer
   matches the plan, re-creates what is missing and re-registers; **Remove** deletes our subscriptions
   in Azure DevOps and the relay's rows for that project.

**Rotating the key** means re-creating the subscriptions: Azure DevOps stores the password inside each
subscription and there is no safe in-place edit. Set a new secret, then **Remove** and **Enable** every
project. Deliveries in that window are lost, so do it in a quiet minute.
