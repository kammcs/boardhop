# Boardhop spikes

Small scripts that settle the unknowns listed in section 7 of [00-feasibility-summary.md](../00-feasibility-summary.md) and in [06-notification-relay-and-extension.md](../06-notification-relay-and-extension.md). Each writes a Markdown result into `results/` with the raw evidence and the TSTU cost of every call.

## Credentials

Scripts read only these environment variables. Nothing is stored in the repo.

```powershell
$env:ADO_ORG_URL = "https://dev.azure.com/puremedia"
$env:ADO_PROJECT = "<project name>"
$env:ADO_PAT     = "<personal access token>"
python research/spikes/s02_pat_profile_accounts.py
```

Kelly authorized using the PAT stored in the AzureDevOps MCP server entry for spike validation (2026-09-10). `_run_with_mcp_creds.py <script…>` loads it into the child process environment only:

```powershell
python research/spikes/_run_with_mcp_creds.py s05_multiline_format.py s10_board_schema_and_wef.py
```

Results and the consolidated findings are in [results/README.md](results/README.md).

## Read-only spikes (safe on any project)

| Script | Question it answers |
|---|---|
| `s02_pat_profile_accounts.py` | Do PATs work against the Profiles and Accounts APIs? Docs conflict. |
| `s02b_pat_scope_probe.py` | Which service areas the current PAT reaches; alternative identity endpoints. |
| `s05b_multiline_expand.py` | Which `$expand` and api-version combinations populate `multilineFieldsFormat`. |
| `s04_org_level_pr_list.py` | Is there an org-level PR list endpoint, and does `reviewerId` filter at org level? |
| `s05_multiline_format.py` | Does `multilineFieldsFormat` appear on work item reads, and at which api-version? |
| `s06_suggestion_wire_format.py` | What does a suggested-change comment look like on the wire? (search half) |
| `s09_activity_poll_cost.py` | TSTU cost of one Activity poll cycle. |
| `s10_board_schema_and_wef.py` | Board config, raw card settings and rule settings schema, WEF field names and values. |
| `s11_workitem_type_fields.py` | Type, state and field metadata for dynamic forms; `validateOnly` dry runs. |
| `s12_tenant_id.py` | Entra tenant ID behind the org, from Graph users' `domain`. |
| `s13_html_samples.py` | Collects real HTML description samples tagged by construct for spike F3 (writes gitignored `results/f3-samples.json`). |

## Write spikes (scratch project "DevOps Mobile App" only)

`scratch.py` pins the project and team name; work item patches verify the item belongs to the scratch project before writing.

| Script | Question | Status |
|---|---|---|
| `w00_inspect_scratch.py` | Read-only look at the scratch project. | Done |
| `w01_markdown_roundtrip.py` | Markdown write path, reversibility, comments API with Markdown. | Done |
| `w02_kanban_column_patch.py` | Does writing the WEF column field auto-derive `System.State`, and vice versa? | Done |
| `w03_pr_line_comment.py` | Seed a repo and PR through REST, post an anchored thread and a suggestion comment, push a second iteration, read tracking back. | Done (PR 8319 left active for visual check) |
| `w04_service_hook_payloads.py` | Capture "Minimal" webhook payload shapes for the five event types in document 06. | Not written: needs an HTTPS receiver and project-admin rights |

## App spikes (Flutter, on device or emulator)

| Spike | Question | Status |
|---|---|---|
| F1 | `msal_auth` sign-in, silent restore, org discovery, token size | Done 2026-09-10 on a Pixel 10 Pro / Android 17 emulator (browser fallback; Authenticator broker not yet exercised). Runner: the Diagnostics page in the app. |
| F2 | Claims challenge (CAE) through `msal_auth` | Done 2026-09-10: plugin vendored and patched (`packages/msal_auth`), `forceRefresh` and `claims` verified on the emulator, 401 retry wired into `AdoClient`. Real revocation event and iOS build still untested. |
| F3 | HTML round-trip through the candidate editors | Done 2026-09-10. Delta editors (Quill, Fleather) drop tables and mention identities; `html_editor_enhanced` is lossless on real content. Harness in `f3_harness/`, on-device probe in the app's Diagnostics. |
| F4–F5 | Kanban drag-and-drop, diff viewer | Not started |

## Not runnable here

The cross-tenant 401 hint needs a guest account. Publisher verification lead time is administrative.
