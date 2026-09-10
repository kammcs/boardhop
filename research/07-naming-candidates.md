# 07 — Naming Candidates

## Constraints

Per Microsoft's trademark and brand guidelines for third-party applications:

- The app name and icon **must not** contain "Azure", "DevOps", "Azure DevOps", or any other Microsoft trademark, and must not be confusingly similar to one.
- A plain-text compatibility statement — e.g. "works with Azure DevOps" or "for Azure DevOps Services" — is allowed **only** in the store description/subtitle copy, never in the app name or icon.
- Beyond the Microsoft-specific rule, the name should also be short (1-2 words), easy to pronounce, and read as "developer-grade" the way Linear, Raycast, Tower, Working Copy, Fork, and Kaleidoscope do — i.e. evoke the product without literally describing it.
- Target evocations: boards/flow, pull-request review, shipping/pipelines, the DevOps "infinity loop," or a pocket/companion client.

## Method and limits

Checks were done with web search only (no App Store Connect / Google Play Console API access, no domain registrar/WHOIS API access). For each shortlisted name:

- **App Store / Play Store conflict** — searched for an existing app of that name, particularly in developer tools.
- **Domain status** — inferred from whether a live site, parked/for-sale listing, or GitHub project surfaced at the obvious `.com` / `.app` / `.dev`. This is **not** a WHOIS lookup — every domain verdict below is marked **unverified** and should be confirmed in a registrar before committing to a name.
- **Trademark risk** — flagged when an existing commercial product (not just an unrelated hobby app) uses the same or a confusingly similar name, especially in developer tools/SaaS.
- **Common-word risk** — flagged when the name is (or is built from) ordinary English words that are already heavily used across app stores, which makes branded search/ASO harder.

Nothing here is legal advice; a proper trademark clearance search (USPTO TESS, EUIPO, live App Store/Play Store category browse) is still needed before filing or launch.

## Shortlist evaluation

| Name | Meaning / evocation | App Store conflict | Play Store conflict | Domain status (unverified) | Trademark risk | Verdict |
|---|---|---|---|---|---|---|
| **Boardhop** | Hopping between Kanban boards/projects; boards + mobility | None found | None found (only unrelated "Board"/board-game apps) | `boardhop.com` parked/listed for sale via HugeDomains (registered, but resellable — unverified); no evidence of `.app`/`.dev` use | Low — no existing software product found under this name | **Strong** |
| **Pocket Pipeline** | Pocket/companion client + CI/CD pipelines | None found under this exact phrase | None found under this exact phrase | No site found at `pocketpipeline.com` / `.app` / `.dev` (unverified — absence of results is not proof of availability) | Low for the phrase; "Pipeline" alone is generic CI/CD vocabulary (Azure Pipelines, GitLab Pipelines, Jenkins Pipeline, Pipeline CRM, PipelineApp.io) so it is not ownable on its own | **Strong**, but two words is less "one-word brand" than the Linear/Raycast bar |
| **Diffly** | "Diff" (PR review) + friendly "-ly" suffix | None found as a mobile app | None found as a mobile app | Multiple *existing web products* already use it: `diffly.io` (Stripe environment comparison), `diffly.co` (win-loss analysis SaaS), `diffly.net` ("see every change, side by side" — a diff-viewer, conceptually identical to our PR-diff feature), plus open-source GitHub repos named diffly | Moderate — no mobile-app collision, but the name is already live in the diff/comparison tooling space, including one product with near-identical positioning (`diffly.net`) | **Good, with caution** |
| **Loopline** | The DevOps "infinite loop" | None found as a mobile app | One unrelated "Loopline" wire-puzzle game | `loopline.com` referenced as a premium resale listing; `loopline-systems.com` and `theloopline.com` are live sites (different businesses) | **Elevated** — "Loopline Systems" is an established, funded B2B HR/performance-management software company (Berlin, founded 2014) with an active product and terms-of-service asserting its marks; same broad category (SaaS for teams) | Caution — usable but has the highest real trademark exposure of the batch |
| **Reviewloop** | PR review + infinity loop | Developer listed as "Loop Review, LLC" exists, but no exact-name PR app found | ReviewLoop is a live Shopify App Store app (product-review collection) | `reviewloop.io` is a live, active commercial site | Moderate — different category (e-commerce reviews vs. dev tools) but the exact name and a matching `.io` domain are already in commercial use | Caution |
| **Mergeloop** | PR merge + infinity loop | "Merge Fleet Loop" exists (unrelated game) | "Merge Loop" is a live mobile puzzle/merge game | `mergeloop.dev` appears to be an active indie-developer handle/brand (seen on Bluesky) | Moderate — not a dev-tools collision, but the `.dev` handle is already claimed by another software-adjacent identity | Caution |
| **PR Pilot** | Pull-request companion/"pilot" | No exact iOS app found | No exact Android app found | `pr-pilot.ai`, `docs.pr-pilot.ai` are live | **High** — "PR Pilot" is an existing, actively marketed GitHub Marketplace product ("PR Pilot AI," an AI agent for GitHub issues/PRs) in the *exact same problem space* (pull-request tooling); also "PR" is ambiguous with "public relations," hurting ASO | Avoid |
| **Shipdeck** | Shipping/pipelines + "deck" (dashboard/nautical) | "ShipDesk" (different spelling) shipping-logistics app exists | "Ship Deck Fish & Chips" (unrelated) | `shipdeck.dev` (AI project-management tool) and `shipdeck.com` (dev-team issue tracker/Kanban board) are both **live commercial products for software teams** | **High** — direct collision with two live products in the same broad developer-tools category | Avoid |

## Ranked top 3

1. **Boardhop** — No app-store, domain-registration-signal, or trademark conflicts turned up; the boards/Kanban evocation is on-brand and it reads as a distinct, ownable coined word rather than a common phrase, which also makes it easier to rank for branded search.
2. **Pocket Pipeline** — Cleanly evokes both the "companion client" and "pipelines/shipping" angles with no name collisions found, though as two ordinary English words it is closer to a descriptive tagline than a one-word brand like Linear or Tower, and "Pipeline" alone is heavily used elsewhere so exact-phrase branding matters.
3. **Diffly** — Best captures the PR/diff-review core of the app and sounds the most "developer-grade" of the group, but ship it with eyes open: `diffly.io`, `diffly.co`, and especially `diffly.net` (a diff-viewing tool with near-identical framing) are already live, so a domain and trademark clearance pass is needed before committing.

Names to avoid despite fitting the theme well: **PR Pilot** and **Shipdeck** both collide with existing, actively marketed developer-tools products in the same problem space, and **Loopline** collides with an established, funded HR-software company — all three carry meaningfully higher trademark exposure than the top 3.

## Full brainstorm list (25+)

**Boards/flow:** Boardhop, Boardline, Boardmate*, Cardflow*, Flowdeck*, Kanbo, Swimlane, Loopwork

**Pull-request/review:** Diffly, Diffpocket, Diffhop, Reviewly, Reviewhub, Reviewmate, Reviewloop*, PR Pilot*, Branchmate*, Branchly

**Shipping/pipelines:** Shipdeck*, Shipmate*, Shiplog, Pipely**, Pipehop, Pocket Pipeline, Pipeworks, Ship Pilot

**Infinity loop:** Loopline*, Mergeloop*, Loopcheck, Taskloop, Devloop

**Companion/pocket client:** Pocket Ops, Pocketwork, DevPilot, Codeboard, Flowpilot, Boardpilot

`*` = checked in the extended search pass (beyond the 8-name shortlist table above): Boardmate, Cardflow, Flowdeck, Branchmate, and Shipmate all turned up existing App Store/Play Store apps of the same name (board-game companions, trading-card/study apps, an Apple-dev IDE tool, a parking/branch-banking app, and a cruise-tracker respectively), which is why none were promoted into the final ranked shortlist.

`**` = checked briefly; "Pipely" already exists as a live "Flow Connect Puzzle" game on Google Play (unrelated category, but an exact-name collision), which is why it did not make the final shortlist either.
