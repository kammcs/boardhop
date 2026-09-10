# Boardhop

A mobile client for Azure DevOps Services (iOS and Android, phones and tablets) built with Flutter. It blends the Jira mobile experience for boards and work items with the GitHub mobile experience for repositories and pull request review.

Boardhop is an independent product by kammcs. It works with Azure DevOps but is not affiliated with or endorsed by Microsoft.

## Status

Discovery is complete and the stack is decided: Flutter (see [research/08-stack-comparison.md](research/08-stack-comparison.md)). The research, decisions, and spike results live in [research/](research/), starting with the [feasibility summary](research/00-feasibility-summary.md). The Flutter app is scaffolded (sign-in through Microsoft Authenticator, organization discovery, project list, and a diagnostics page that doubles as the sign-in spike). Current state and the ordered plan are in [NEXT-STEPS.md](NEXT-STEPS.md).

## Repository layout

| Path | Contents |
|---|---|
| `lib/core/` | Build-time config, the Azure DevOps HTTP client (host routing, pinned `api-version`, rate-limit tracking, typed errors) |
| `lib/auth/` | `msal_auth` wrapper (broker sign-in, per-tenant silent tokens) and the auth bloc |
| `lib/data/` | drift database, models, repositories |
| `lib/features/` | One folder per screen area: auth, orgs, projects, work_items, boards, pull_requests, pipelines, activity, diagnostics |
| `assets/msal_config.json` | Android MSAL configuration (authority, broker, account mode, CP1 capability) |
| `packages/msal_auth/` | Vendored msal_auth plugin with claims-challenge support (see its README) |
| `research/` | Discovery documents, settled decisions, competitive research, naming |
| `research/verification/` | Anonymous probes of public Azure DevOps projects that prove API shapes |
| `research/spikes/` | Authenticated spike scripts and consolidated results against a test org |

## Running the app

Requirements: Flutter 3.47 or later, the Entra client ID, and either a real device with Microsoft Authenticator (broker sign-in) or an Android emulator (browser fallback). `tool/start-emulator.ps1` starts the Pixel 10 Pro AVD with DNS settings that work on Windows hosts with VPN adapters.

1. Copy `.env.example` to `.env` and set `BOARDHOP_CLIENT_ID`. The file is gitignored.
2. Android only: copy `android/secret.properties.example` to `android/secret.properties` and set your debug signature hash. The hash must also be registered on the app registration as an Android redirect URI (see [research/09-entra-app-registration.md](research/09-entra-app-registration.md)).
3. Run:

```
flutter pub get
dart run build_runner build
flutter run --dart-define-from-file=.env
```

Tests and analysis:

```
flutter analyze
flutter test
```

## Running the spikes

The spike scripts take credentials only from environment variables and never store them. See [research/spikes/README.md](research/spikes/README.md).
