# 11. Work item forms: creating and editing any work item

**Date:** 2026-09-12
**Status:** **Phases 0–5 complete 2026-09-12.** Plan agreed with Kelly (section 7); spikes run 2026-09-12 (section 9) and the plan adjusted where they disagreed. People picker re-decided the same day (section 7). Per-phase notes in section 8.
**Ask (Kelly):** the app cannot create work items. Research how the Azure DevOps web renders work item forms, including custom fields that depend on the work item type, and plan a create flow whose button sits in the Work app bar to the left of the Items/Board pill, with a form that fits a phone and a tablet differently.
**Method:** existing research (01 §2.7, §3.2, §9.3; 05 §5.1, §5.2), spike s11 (field metadata, `validateOnly`), w01 (Markdown on create), the Processes REST reference, and a review of what the app does today.

## 1. Where the app is today

- Writes on existing items only: title and description (`WorkItemEditPage`, HTML through `html_editor_enhanced`, Markdown as text), state and assignment through bottom sheets (`work_item_actions.dart`), comments, board column moves. Nothing creates an item.
- `WorkItemRepository.types()` already reads `wit/workitemtypes` (name, color, icon, states) and caches it for a day in memory. It does not read fields, transitions or any layout.
- The state sheet offers the flat state list, not the legal transitions (research/01 §2.7 warns about this). The form work fixes that as a side effect.
- The web form is data-driven per process. CloudCover 2.0 is an inherited Agile process with 18 types (three custom task types), ten User Story states and custom fields such as `Custom.QAStoryPoints` and `Custom.QAAssignee` (spike s11). The scratch project "DevOps Mobile App" is on a stock process. Together they are the two test beds.

## 2. What Azure DevOps gives us

All `api-version=7.1` unless noted. "Verified" means run against puremedia; the rest is from the reference and must be confirmed by the spikes in section 6.

| Need | Endpoint | Status |
|---|---|---|
| Types with color, icon, states, **transitions**, `xmlForm` | `GET {org}/{project}/_apis/wit/workitemtypes[/{type}]` | Verified (list). `transitions` is a map `fromState → [{to, actions}]` with `""` as the pre-creation state: the states a new item may start in. Strip `xmlForm` before caching. |
| Per-type field rules | `GET …/wit/workitemtypes/{type}/fields?$expand=All` | Verified: 71 fields for Bug, 1.12 TSTU, with `alwaysRequired`, `allowedValues`, `defaultValue`, `dependentFields`, `helpText`. Identity `allowedValues` carry `displayName`, `id`, `uniqueName`, `descriptor` (the Assigned To picker list). No field *type* here. |
| Field types | `GET {org}/_apis/wit/fields` (org-wide, one call) | Reference: `type` (`string`, `integer`, `double`, `dateTime`, `plainText`, `html`, `treePath`, `history`, `boolean`, `identity`, `picklistString`, `picklistInteger`, `picklistDouble`), `isIdentity`, `isPicklist`, `readOnly`, `usage`. Needed to choose the control when the layout gives none. |
| Which process a project uses | `GET {org}/_apis/projects/{id}?includeCapabilities=true` → `capabilities.processTemplate.templateTypeId` | Reference. The project repository already reads projects; add the capability. |
| **Form layout** | `GET {org}/_apis/work/processes/{processId}/workItemTypes/{witRefName}/layout` | Reference (Processes API, "Layout – Get"). `FormLayout { pages[] { id, label, pageType (custom/history/links/attachments), visible, locked, sections[] { id: Section1…Section4, groups[] { id, label, visible, controls[] { id (field reference name), label, controlType, readOnly, visible, order, watermark, isContribution } } } }, systemControls[] }`. Control types seen in the reference: `FieldControl`, `HtmlFieldControl`, `DateTimeControl`, `WorkItemClassificationControl`, `LinksControl`, `AttachmentsControl`, `LabelControl`, `WebpageControl`, `TestStepsControl`, `WorkItemLogControl`. **Unverified:** whether the caller needs process-level permission beyond `vso.work`, and how the response looks for a Hosted XML project (expected: 404 or 400, in which case `xmlForm` on the type holds the layout). |
| Backlog levels and type roles | `GET {org}/{project}/{team}/_apis/work/backlogconfiguration` | Reference (research/01 §3.2): `portfolioBacklogs[]`, `requirementBacklog`, `taskBacklog`, `hiddenBacklogs[]`, `bugsBehavior`, per-level `workItemTypes[]`. Drives the type chooser's first section. |
| Hidden types | `GET …/wit/workitemtypecategories` → `Microsoft.HiddenCategory` | Reference. Never offered. |
| Areas and iterations | `GET …/wit/classificationnodes/{areas\|iterations}?$depth=N` | Reference. Tree with `path`, `hasChildren`, iteration `attributes.startDate/finishDate`. |
| Team defaults | `GET {org}/{project}/{team}/_apis/work/teamsettings/teamfieldvalues` (default area) and `…/teamsettings/iterations?$timeframe=current` | `teamfieldvalues` verified by the board work; current iteration from the reference. |
| Tags | `GET …/wit/tags` (7.1-preview.1) | Reference. `System.Tags` is written as `a; b; c`. |
| Team templates | `GET {org}/{project}/{team}/_apis/wit/templates?workitemtypename=` and `…/templates/{id}` | Reference: `{ id, name, description, workItemTypeName, fields: {refName: value} }`. |
| **Create** | `POST {org}/{project}/_apis/wit/workitems/${type}` (JSON Patch, `application/json-patch+json`) with `?validateOnly=true` for the dry run | Verified by w01 (create with `/fields/*` and `/multilineFieldsFormat/System.Description = Markdown`). `validateOnly` verified on PATCH by s11; the same query parameter exists on create (reference). Errors come back as HTTP 400 with `customProperties.RuleValidationErrors[] { fieldReferenceName, fieldStatusFlags, errorMessage }`. |
| Update | `PATCH …/wit/workitems/{id}` with `test /rev` | Verified; `AdoStaleRevisionException` on 412 already handled. |
| Links | `add /relations/-` with `rel` (`System.LinkTypes.Hierarchy-Reverse` for parent, `-Forward` for child, `System.LinkTypes.Related`) and the target item `url` | Reference (research/01 §2.6); can be sent in the create patch. |
| Attachments | `POST …/wit/attachments?fileName=&uploadType=simple` (binary body) then `add /relations/-` with `rel: AttachedFile` | Reference; 60 MB, 100 per item. |
| Work item search for link targets | `POST almsearch…/workitemsearchresults` or WIQL `CONTAINS` on Title | Search is the code-search sibling already used; WIQL is the fallback when the extension is missing. |

What the metadata cannot express (research/05 §5.1): conditional rules ("Reason required when State is Closed", custom rules in inherited processes). `dependentFields` only says *which* fields may change when another does. The server is the authority, so every save is preceded by `validateOnly=true`, and a value that a rule cleared or set comes back in the validation response only as an error, not as a new value. The web re-evaluates rules live; the app re-runs the dry run when a field with dependents changes (debounced) and applies any field-level messages it gets.

## 3. How the web does it, and what to keep

The web form (new and existing items share it): a header row across the top (type icon, id or "New", title, then assigned to, state, area, iteration and tags on a second line), an optional Markdown/HTML toggle on new items, then the process layout: pages as tabs (Details, plus custom pages, then History, Links, Attachments), each page with up to four sections laid out as columns (Section1 wide on the left, Section2 and Section3 narrower on the right, Section4 full width beneath), each section holding groups (bordered cards with a label), each group holding controls in order. Required fields show a marker and a red outline; picklists are dropdowns; identity fields are a typeahead over the project's users; area and iteration are tree pickers; HTML fields are rich editors; the discussion sits under the layout. Save is in the toolbar and the form validates live.

Keep: the header row as the pinned identity of the item; groups as labeled cards; section order; required markers; live validation messages. Change for mobile: pages become sections or tabs, not both; sections collapse to a single column on a phone; every picker is a bottom sheet or a full-screen search; Save lives in the app bar; the discussion is not part of the create form.

## 4. Proposed design

### 4.1 Entry points

1. **Work app bar.** A `+` icon button (icon only on compact, icon and "New" label from medium up, matching the pill's rule) immediately left of the Items/Board `WorkViewSwitch`, on both views. It opens the type chooser.
2. **Board column.** A `+` row at the bottom of each column (and of each lane cell when lanes are on), like the web. It skips the chooser when the board has one type, otherwise offers the board's types only, and pre-fills State from the column's `stateMappings[type]`, the lane's field value, and the team's area and iteration. The card appears in that column on save.
3. **Child from a work item.** "Add child" in the detail page's overflow (and "Add related" behind the same sheet when links land). Pre-fills the parent link, Area and Iteration from the parent, and the child type from `backlogconfiguration` (the level below the parent's; a Task under a User Story; a User Story under a Feature; Bug follows `bugsBehavior`).

Home stays a shortcut-free page (Kelly's choice).

### 4.2 Type chooser

A bottom sheet on the phone, a popover menu under the button on a tablet. Rows are the type's icon in its process color plus the name, in this order: the backlog levels top-down (Epic, Feature, User Story or Product Backlog Item, Bug when it behaves as a requirement, then the task level with its custom task types), then a collapsed "Other" section with the remaining non-hidden, non-disabled types (Issue, Test Case, feedback and review types). When the team has templates for a type, the row expands to "Blank" plus the template names (a template pre-fills its `fields` map). The last used type per project is remembered and shown first.

### 4.3 The form engine

`WorkItemForm` renders from a `FormSpec` built once per project and type and cached for a day:

```
FormSpec
  type            WorkItemType (icon, color, states, transitions)
  fields          Map<refName, FieldSpec> (type, required, readOnly, allowedValues, defaultValue, helpText, dependentFields)
  header          [Title, State, AssignedTo, AreaPath, IterationPath, Tags]   (system controls, always present)
  pages[]         label, kind (details | custom | links | attachments), sections[] → groups[] → controls[] (FieldSpec + label + control type)
  source          processLayout | fieldList | xmlForm
```

Building it: type (already cached) + `fields?$expand=All` for that type + org `wit/fields` (once per org) + the process layout for the project's process. When the layout call fails (Hosted XML, permission, network) the spec falls back to **field list order**: required fields first, then the well-known common fields (Description, Repro Steps, Acceptance Criteria, Priority, Severity, Effort/Story Points as `backlogconfiguration.backlogFields` names them, Activity, Remaining Work), then the rest grouped by prefix (`Custom.*` as "Custom fields", `Microsoft.VSTS.*` by its middle segment, `System.*` last), skipping read-only and system bookkeeping fields (`*Count`, `*Level*`, `*Id`, `Rev`, `Watermark`, dates the server sets). The `xmlForm` path is a later refinement only if a Hosted XML customer appears.

Control mapping (layout `controlType` first, field `type` otherwise):

| Field / control | Widget |
|---|---|
| `string` with `allowedValues` or `picklist*` | Dropdown on tablet, bottom-sheet list on phone; `isLimitedToAllowedValues` false keeps a free-text option |
| `string` without values | Single-line `TextField`; Title is the pinned header field |
| `html` (`HtmlFieldControl`) | Collapsed preview card that opens the existing rich editor (`html_editor_enhanced`) full-screen; Markdown box when the item's format map says Markdown or the new item chose Markdown |
| `plainText` | Multi-line `TextField` |
| `integer`, `double` | Numeric `TextField` with the matching keyboard; picklist numeric as a list |
| `dateTime` | Date picker (time kept when the value has one) |
| `boolean` | Switch tile |
| `identity` | People picker sheet: the field's `allowedValues` cached a day, filtered as you type, recent assignees first, "Me" pinned at the top, "Unassigned" row; avatar through `AvatarStore` from the descriptor |
| `treePath` (`WorkItemClassificationControl`) | Tree picker sheet over `classificationnodes` (lazy children, search filter, current iteration marked) |
| Tags | Chip field with a suggestion list from `wit/tags` |
| State | Chip in the header opening the transition list from `transitions[current]` (`""` for a new item), colored by state category; Reason follows as a picklist when the transition changes it |
| `LinksControl` | Links page: list of relations with an "Add link" sheet (parent, child, related; target by id or title search) |
| `AttachmentsControl` | Attachments page: thumbnails and files, add from camera, photo library or file picker |
| `LabelControl`, `WebpageControl`, contributions | Skipped (a contribution shows its label with "Not available in the app") |
| `readOnly` controls | Shown as text when they have a value on an existing item, hidden on create |

Validation: required and picklist checks run locally as the user types; a debounced `validateOnly=true` runs when a field with `dependentFields` changes and on Save. Errors sit under their field, and the first error is scrolled into view. The dry run doubles as the "can I create this here" check before the user has typed much (permissions, bad defaults).

### 4.4 Phone (compact)

A full-screen route (`/work-items/new?type=…` and `/work-items/{id}/edit`). App bar: Close (with a discard confirmation when dirty), title "New Bug" or "#15503", Save as a filled text button. Body:

- **Pinned header** under the app bar: type chip, the Title field (multi-line, grows to three lines), then a wrapping row of chips: State, Assigned to, Area, Iteration, Tags. Chips show the value or the placeholder and open their pickers. This is the web's header row folded to phone width.
- **Sections** below, one per group of the Details page in web order, each a card with the group label and its controls stacked; long-text fields show a preview and open the editor. Groups start expanded; a group whose fields are all empty on an existing item starts collapsed.
- **Extra pages** (custom pages, Links, Attachments) follow as further sections at the bottom, each headed by the page label, so nothing hides behind a tab. History is not shown; the detail page has the discussion.
- The keyboard never covers the focused field: the body is a `CustomScrollView` with `keyboardDismissBehavior` on drag and the form scrolls the focused control into view (lesson from the thread composer).

### 4.5 Tablet (medium and expanded)

A centered `Dialog` over the current Work view, up to 960 dp wide and 90% of the height, so the list or board stays visible around it (the web opens a dialog too). Inside: the same app bar row (Close, title, Save), the header row laid out on one line (type, Title wide, then State, Assigned to) with Area, Iteration and Tags on a second line; below it the Details page's sections as columns: Section1 takes 60% and Sections 2 and 3 stack in the remaining 40%, Section4 spans the width, groups as cards in each. Custom pages, Links and Attachments become tabs across the top of the layout area (web-like, and there is room). Pickers are popover menus or anchored dropdowns rather than sheets. In the Work two-pane view the dialog covers both panes; when the dialog would be narrower than 640 dp (a small tablet in portrait) the phone layout is used inside it.

### 4.6 Save and after

Create: `POST …/workitems/${type}?validateOnly=true`, then the real POST with the same patch (fields, `/multilineFieldsFormat/System.Description` when Markdown was chosen, relations for parent and attachments, `System.Tags`). On success the new item is upserted into the cache, the form closes, a snackbar says "Bug #15510 created" with **Open**, and the origin refreshes (list re-query, board column, parent's children). Edit: the same form loaded with the item's values and `rev`; Save sends only changed fields with `test /rev`; a 412 opens the existing conflict flow. The current title-and-description edit page is removed once the form covers it.

Online only. A failed save keeps the form open with the error; leaving a dirty new form offers "Keep draft", stored per project and type in `CacheEntries` and offered the next time the chooser opens ("Resume draft: Bug 'Login fails…'"). Drafts never enter the pending-writes queue (Kelly's decision: no temporary ids).

### 4.7 Defaults

Team = the team of the board on screen, else the project's default team (`BoardRepository.defaultTeamId`). Area = the team's default `teamfieldvalues.defaultValue`; Iteration = the team's current iteration, else the team's backlog iteration; State = the first `""` transition target (the type's initial state); other fields from `defaultValue`; Assigned to empty. From a board column: State from the column mapping, the lane's field from the lane. From a parent: Area, Iteration and the parent link. From a template: its `fields` map on top of all of the above.

## 5. Data layer and code shape

- `lib/data/models/work_item_form.dart`: `FieldSpec`, `FormSpec`, `FormLayout` (pages/sections/groups/controls), `ClassificationNode`, `WorkItemTemplate`, `WorkItemDraft`, `ValidationError` (from `RuleValidationErrors`).
- `lib/data/repositories/work_item_form_repository.dart`: `formSpec(org, project, type)` assembling type + fields + org field types + layout with the fallback, cached in `CacheEntries` for 24 h under `form/{project}/{type}`; `classificationNodes(kind)`; `teamDefaults(team)`; `tags()`; `templates(team, type)`; `validate(...)`; `create(...)`; `uploadAttachment(...)`; `searchLinkTargets(...)`. Creation and the field rules go through the existing `AdoClient` with `application/json-patch+json`.
- `WorkItemRepository`: `transitionsFor(type)` (replaces the flat state list in the state sheet), `processId(project)` via the project read with capabilities.
- `lib/features/work_items/form/`: `WorkItemFormPage` (route, load, save, drafts), `WorkItemFormBody` (chooses the phone or tablet arrangement from the `Breakpoint`), `form_header.dart`, `form_group.dart`, one file per control (`picklist_field.dart`, `identity_picker.dart`, `tree_picker.dart`, `tags_field.dart`, `date_field.dart`, `rich_text_field.dart`, `links_section.dart`, `attachments_section.dart`), `type_chooser.dart`. `WorkItemFormState` is a `ChangeNotifier` holding values, dirty set, errors and the debounced validation.
- Router: `…/work-items/new` (query `type`, `state`, `lane`, `parent`, `template`), `…/work-items/:id/edit` replaces the current edit route. On tablets the same routes render inside the dialog (`showDialog` from the page, route kept so a deep link works).
- Tests: `FormSpec` building from recorded JSON (layout, fields, fallback ordering), control mapping per field type, default resolution, patch generation (only changed fields, format op, relations), validation error mapping, chooser ordering from a recorded `backlogconfiguration`, widget tests for the phone and tablet arrangements at both breakpoints and at large text.

Cost: the spec build is about 1.2 TSTU per type (s11) plus the layout call once per process; both cached a day and refreshed in the background when older. The dry run costs one write-sized call per Save and per dependent-field change (debounced to 800 ms), which is well under the 200 TSTU five-minute window.

## 6. Spikes before phase 1 (run 2026-09-12; results in section 9)

Read-only unless marked; results in `research/spikes/results/README.md`, raw output stays local.

1. **s24 process layout.** For CloudCover 2.0 (inherited) and DevOps Mobile App (stock): project capabilities → process id → layout for Bug, User Story, Task and one custom type. Record page/section/group/control shapes, control types met, whether custom fields appear with their `Custom.` reference names, and the status for a process the caller cannot read. Also read `wit/fields` once and note the field types of every control.
2. **s25 pickers and defaults.** `classificationnodes` depth and shape for both projects; `teamfieldvalues` and `iterations?$timeframe=current` for a team; `wit/tags`; `templates` for the scratch team; `backlogconfiguration` type roles and `bugsBehavior`; `workitemtypecategories` hidden set; `transitions[""]` for each type.
3. **w16 create with dry run (scratch project).** `validateOnly=true` create with a missing required field, an illegal picklist value and a bad state, then a real create of a Task with parent link, tags, Markdown description and a template; read it back. Confirms the error shape on create and that relations can ride in the create patch.
4. **w17 attachment (scratch project).** Upload a small PNG with `uploadType=simple`, attach it, confirm the relation and that the detail page's HTML image path (research/01 §10.3) can show it.

## 7. Decisions (interview with Kelly, 2026-09-12)

| Question | Decision |
|---|---|
| Fidelity to the web form | **Full form layout**: every page, group and control in web order, custom fields included. Source changed after spikes s24/s26: the type's `xmlForm` (works for every type) instead of the Processes layout API (refuses stock types). |
| Types offered | **Backlog types first, the rest under "Other"**: backlog levels from `backlogconfiguration`, then a collapsed section with the remaining non-hidden types. |
| Edit | **One form for create and edit.** The detail page's Edit opens the full form; the title-and-description page goes away. |
| Entry points | **Work app bar `+`, board column `+` (state and lane pre-filled), "Add child" from a work item.** Not on Home. |
| Tablet | **Centered web-like dialog** up to ~960 dp with the sections in columns; the list or board stays visible around it. |
| Phone | **Pinned header, sections stacked**: type, title and the core chips pinned; groups as collapsible cards; extra pages as sections at the bottom. |
| Offline | **Online only, local drafts.** No queued creates, no temporary ids. |
| People picker | **Team members plus Graph search** (decided 2026-09-12 after spike s25 found the type's allowed values empty in both projects): the current team's members as the cached offline list with recent assignees first, plus a project-scoped Graph subject query as you type (`vso.graph` is already granted). |
| Rich text on create | **Rich editor, following the project**: HTML editor by default, Markdown when the project or the user chooses it; the spike confirms the format op on create. |
| Area and iteration defaults | **The current board's team** (project default team elsewhere): its default area and current iteration. |
| Extras | **Team templates, links (parent, child, related), attachments** are in scope. |
| Layout unavailable | **Field-list fallback**: required and common fields first, then the rest grouped by prefix. After s26 this only covers a type whose `xmlForm` fails to parse. |

## 8. Phases

| Phase | Scope | Verify on |
|---|---|---|
| 0 | Spikes s24, s25, w16, w17; `FormSpec` models and repository with the fallback; tests from recorded JSON | Scratch project, CloudCover read-only |
| 1 | Type chooser; `+` in the Work app bar; phone form with header, groups, string/picklist/number/date/boolean controls, state transitions, identity picker, tree pickers, tags; dry-run validation; create; open on success | Emulator against the scratch project |

**Phase 1 landed 2026-09-12** and was verified on the phone emulator against the scratch project (Task #15542 created, #15543–#15545 from the error and snackbar checks). Two corrections to this plan: `System.AssignedTo` is sent as `"Display Name <unique>"`, because spike s29 found the work item store refuses the identity id that `teams/{id}/members` and `graph/storagekeys` both report; and `FieldSpec` carries no `isLimitedToAllowedValues` (the type's field read omits it, spike s25), so a field the process does not flag `isPicklist` keeps the free-text row and everything else is closed.
| 2 | Tablet dialog layout with columns and page tabs; rich-text field through the existing editor; Markdown choice | Tablet emulator, iPad simulator |
| 3 | Edit through the same form (replace `WorkItemEditPage`); transition-driven state sheet on the detail page | Scratch items 15503–15507 |
| 4 | Board column `+`, "Add child", templates, drafts | Scratch board (**landed 2026-09-12**, notes below) |
| 5 | Links page (add parent/child/related with search) and Attachments page (camera, library, files) | Scratch project (**landed 2026-09-12**, notes below) |

### Phase 2 notes (2026-09-12)

What deviated from §4.5 and §4.3 while building it:

- **The route is not a scrim over the Work view.** The `…/work-items/new` route lives inside the project shell's Work branch, so a pushed route replaces the branch's page and nothing of the list can show around it. From medium up the `+` therefore *shows the form with `showDialog`* over the live Work view (list or board underneath, which is what §4.5 asks for) and the route renders the same box centered on its own page, so a deep link still works at any width. The dialog must use `useRootNavigator: false`: the account's repositories are provided by the `/a/:account` shell route, and the root navigator sits above them.
- **The split comes from the layout's own sections.** `FormSection.percentWidth` drives it (the stock types are 50/50), three sections put the first in 60% and stack the rest in 40%, and a fourth spans the width beneath. Below 640 dp of *dialog* width the phone arrangement runs inside the dialog (checked at a 650 dp window, where the box is 602 dp).
- **Tabs.** Custom pages become tabs across the top of the layout area ("Details" first). The scratch process has none, so the tab bar is covered by a widget test with a synthetic custom page, not on the device; CloudCover 2.0 has custom types but the form may not be opened there (its dry run is a POST, and the hard rule keeps every write out of client projects).
- **One rich editor.** `html_editor_enhanced` now lives in `HtmlFieldEditor` (`lib/features/work_items/widgets/`), shared by `WorkItemEditPage` and the form's `RichTextControl`: the same toolbar, `adjustHeightForKeyboard: false`, the same JSON-string injection through the WebView and the same readiness retry (spike F3). The control itself is a card with the rendered value (`RichTextView`) and a pencil; it opens the editor full screen on a phone and as a large dialog on a tablet, Cancel/Done in the app bar. Its height is clamped to 520 dp so the list can scroll it clear of the keyboard.
- **Markdown choice.** A "Rich text / Markdown" segmented control shows only for `System.Description` on a new item. Switching with content asks first and then clears it, because Boardhop never converts between the two (research/00 §0). Markdown edits in a monospace box with a Preview toggle (`flutter_markdown_plus`), and `buildOps` adds `/multilineFieldsFormat/System.Description = Markdown` (spike w01). The last choice is remembered per project in `FormPrefs`.
- **Values are no longer escaped once the editor has touched them.** `WorkItemFormState.setRichValue` marks the field, so the patch carries the editor's HTML (or Markdown) verbatim; a long-text field filled as plain text still becomes one escaped `<div>`.
- **Pickers from medium up:** picklists drop an anchored `MenuAnchor` from their tile (with "Other value…" for a free-text field), and the people and tree pickers open as centered dialogs with the same content instead of full-height sheets.
- **Two fixes from the phase 1 review** (both from spike s30): the people search was scoped with the project *name*, which `graph/descriptors` rejects with HTTP 400 and silently widened the query to the whole organization — the form now resolves the project id through the single project read it already makes; and the iteration picker's Team section lists every iteration of the team (`work/teamsettings/iterations` without `$timeframe`, cached a day) with the current one marked, instead of only the current and backlog ones. The people list also keys on the unique name, so a team member and the same person from the Graph hit no longer appear twice.

Open after the spikes: how a template interacts with required-field validation (no team has templates yet; the chooser hides the section until one exists).

### Phase 3 notes (2026-09-12)

Edit through the same form, and what deviated from §4.3 and §4.6 while building it:

- **One page, two modes.** `WorkItemFormPage.edit(org, project, id)` loads the item (`refreshItem`, the cached copy first when the network is gone), its `formSpec` from the item's own type and the same pickers the create form uses; `WorkItemFormState` gained `isCreate: false`, the `original` item, a dirty set that survives a reload and a `readOnly` flag. The route `…/work-items/:id/edit` now builds that page, and the detail page's pencil shows the same box as a dialog from medium up (`showDialog(useRootNavigator: false)`, as the `+` does) and pushes the route on a phone. `WorkItemEditPage` is gone; `HtmlFieldEditor` stays and is used only by the form's rich text control.
- **Read-only controls.** `pageViewsFor` takes a `ControlFilter`; `rendersOnEdit` keeps the create fields and adds the read-only ones **that carry a value**, which render as text (`ReadOnlyControl`) and never enter the patch. The scratch process marks only `System.ChangedDate` read-only, and that is a header field, so this is covered by a widget test over a synthetic spec rather than on the device.
- **Long text is never re-escaped.** Every `html` field of an existing item counts as rich from the start, so the item's own HTML goes back out verbatim and an untouched field produces no op at all. The Markdown/HTML toggle stays hidden on an edit (`canChooseFormat` was already gated on `isCreate`).
- **State and Reason.** The state chip is an `ActionChip` on an existing item and opens `pickStateChange` — the same sheet the detail page uses — over `FormSpec.transitionsFrom(state)`. Moving to another state reveals Reason right under the chips as a picklist over the type's field rules, and **drops** the old reason without marking it dirty, so an unsent Reason lets the server pick the new state's default (New → Active came back as "Work started" on the emulator). Sending Reason is the user's choice; the server's rule error lands under the field.
- **Conflict.** A 412 sets `WorkItemFormState.conflict` and the header renders a banner with **Reload** and **Discard**; Reload re-reads the item and rebuilds the state on the new `rev` with the dirty fields laid on top (the body is keyed on an epoch so the title's controller is rebuilt), Discard re-reads and drops them. Nothing is ever force-written.
- **Save.** `validatePatch` (dry run with `test /rev`) then `WorkItemRepository.patch` with `buildEditOps`, which already opens with the guard — `patch` and `validatePatch` now skip adding a second `test /rev`. Save is disabled until the form is dirty, which needed the page to listen to the form state (it did not before; the Create button was always enabled so it never showed).
- **Offline.** The full form stays online-only: with no connection the cached item opens read-only behind "Editing needs a connection" with a Retry, and nothing is queued. The detail page's quick actions (state, assign, comment) keep the write queue exactly as they were.
- **Detail page state sheet.** `pickState` now lists `transitionsFrom(item.state)` and asks for a Reason in a second step when the type's rules mark `System.Reason` `alwaysRequired` — which no stock type does (spike s32), so that step is covered by the type's rules and a test, not by the scratch project. Transitions cost nothing extra: **the type list read already carries them** (spike s32); the detail page reads the `formSpec` only for the Reason rules, and that is cached for a day.
- **Shell re-tap (the phase 2 bug).** Re-tapping the current tab used to `go` to the branch root, dropping an open form without its `PopScope` ever running. `UnsavedWork` (a tiny registry of guards, `lib/features/shared/unsaved_work.dart`) lets the shell ask with the form's own discard dialog first, and a re-tap while already at the branch root does nothing. The `+` also stopped re-enabling because it stayed busy while awaiting a route that the reset had thrown away; it now clears as soon as the chooser closes.

### Phase 4 notes (2026-09-12)

The board column `+`, "Add child" / "Add related", team templates and drafts. What deviated from §4.1, §4.2, §4.6 and §4.7 while building it:

- **One `+` per column, and the lane comes from the chip row.** The board renders swimlanes as a filter chip row rather than as lane cells (milestone 1's second pass), so there are no lane cells to put a `+` in: every column gets one `NewCardRow` at the bottom (`lib/features/boards/widgets/new_card_row.dart`, a quiet card outline through `KanbanBoard.columnFooterBuilder`), and it pre-fills the lane that is *on screen* — the board's `fields.rowField` plus the selected lane name, skipped for "All lanes" and for the default lane, which carries no value. A **split column shows the `+` only in its Doing half**: both halves share the column's `stateMappings`, and a new card belongs in Doing.
- **The lane field never rides the create.** It is a per-team `WEF_…_Kanban.Lane` field that the type's `xmlForm` does not carry, so it is not one of the form's fields; it is written by the same follow-up patch as the state (`boardFollowUpOps`, `test /rev` first). Both ops are skipped when the created item already has that value.
- **The state chip shows the target state.** On a new item the chip stays read-only but now reads the column's state, with the tooltip "Created in New, then moved to Active", because the item is created in the type's initial state and moved by the second call (spike w18). If that second call fails the item still exists: the form closes and the snackbar says `User Story #15549 created in New (could not move to Active): <message>` with **Open**, and the board reloads either way.
- **The board's team is the project's default team.** The board is read without a team segment, so it *is* the default team's board; the page now resolves that team's id (`BoardRepository.defaultTeamId`) and passes it as `team=` into the form, which hands it to `teamDefaults(team:)`. A board of another team needs a team picker first (not in this phase).
- **A new card is tinted, not scrolled to.** `WorkItemCard` gained `flash`, an `AnimatedContainer` tint in `primaryContainer` for 1.8 s, the same idea as the favorites toast's row tint (that one is a page-local pattern, not a shared helper, so it was not reused).
- **"Add related" shows the whole chooser.** A related item can be of any type, so only "Add child" restricts the list — `BacklogTypes.childTypeNames` takes the level below the parent's, and the parent's own level when it is already the last one (a Task's child is a Task, an `asTasks` Bug's too). `bugsBehavior` needs no special case: the service already puts Bug in the requirement or the task level's `workItemTypes`. Both entries sit in the detail page's new overflow menu, and both route through `…/work-items/new?parent=15546&rel=child|related`; `rel=related` sends `System.LinkTypes.Related` instead of the parent link.
- **The detail page had no relations section**, so phase 4 adds a compact **Links** facts row (parent, then the children with their titles) resolved through one `WorkItemRepository.batch`; `WorkItem` now keeps the `relations[]` of the `$expand=all` read (dropped before), merged in the cache like the format map. The full Links page stays phase 5.
- **Templates.** Spike **w20** created the first one on the scratch team (Task, "Boardhop spike task", id `edae8a24-9850-401b-9d0c-7df212025c56`), which also showed that the **list** read carries no `fields` map, so the chooser's expansion names the templates and the single read fills them. Two fixes came out of that: the title field's controller now takes the **raw** value (`state.title` is trimmed, which ate the template's trailing space in `"[template] "`) with the caret after it, and an **empty** template list is re-read once per session instead of being trusted for a day — the team's first template would otherwise stay invisible until the cache aged out, which is exactly what happened on the emulator.
- **Drafts.** Closing a dirty *new* form asks **Keep draft / Discard / Cancel**; a save that cannot reach the server offers "Keep draft" in its banner. A draft keeps what the patch would send (`WorkItemFormState.draftValues()`: identities as `"Name <unique>"`, tags joined, dates ISO, long text already HTML), the format map, the relations and the **pre-fills** it was opened with (team, state, lane, laneField, parent, rel, template), so resuming lands in the same column, lane or parent. Resuming marks every restored field dirty and every restored `html` field rich, so nothing is escaped twice. The chooser lists them on top as `Resume draft: Task - Half typed - 5m ago` (the app's own relative wording, not "5 min ago") with a trailing delete icon; a successful create clears the draft, and one older than **30 days** is dropped on read (`WorkItemDraft.maxAge`).
- **The chooser from a column or from Add child is a sheet at every width.** `showTypeChooser` hangs its menu on the widget that opened it, and neither a column's `+` (inside a lazy list) nor an overflow item is a stable anchor, so both pass none and get the bottom sheet even on a tablet. The Work app bar's `+` still drops its menu under the button.
- **One helper opens the form everywhere.** `openWorkItemForm` and `loadTypeChooserData` (in `new_work_item_button.dart`) are now shared by the Work app bar `+`, the board column `+` and the detail page's Add child / Add related, so all three follow the same rule: route on a phone, dialog from medium up.

### Follow-up: the detail page reads the layout too (2026-09-12)

Kelly: CloudCover 2.0 User Story **#15303** carries `Custom.TestingPlan`, `Custom.QAStoryPoints`
and `Custom.QAAssignee`, and none of them were on the detail page — it rendered a fixed set (Area,
Iteration, Reason, Attachments, Created, Changed, then Description / Repro steps / Acceptance
criteria), so every custom field of every customized process was invisible although the page
already loaded the type's `FormSpec` for the state sheet.

- **The read view now comes from the same layout as the form.** `detailGroupsFor(spec, item)` runs
  `pageViewsFor` with a new `rendersOnDetail(item)` filter: the Details page's groups in web order
  (columns flattened top-down), then any custom page's under its own label, keeping only the
  controls whose field has a **value** on the item — the web's behaviour, and the reason a field the
  layout does not carry is still never shown. Panels are dropped (`FormGroupView.isPanel`): Links
  and Attachments have their own sections, Development and Deployment belong to Azure DevOps.
- **Nothing is shown twice.** `detailShownFieldRefs` is `headerFieldRefs` plus `System.CreatedDate`
  and `Microsoft.VSTS.Common.Priority`, which the header carries as a chip; the bookkeeping fields
  were already out through `FieldSpec.isBookkeeping`.
- **An html control renders as a `RichTextView`** under the group's label (the control's own when
  the group holds several), in the item's own format; every other field is a `label → value` row,
  and `DetailFactRow` is now shared by the facts rows, the links rows and the groups so the labels
  line up in one 104 dp column.
- **One formatter for both pages.** `formatFieldValue(FieldSpec?, Object?)` (identity → display
  name with the small avatar, dateTime → an absolute short date with the time only when it carries
  one, double → trimmed so `1.0` reads "1", boolean → Yes/No, iterables joined) replaced
  `ReadOnlyControl.displayValue`, which the edit form's read-only controls now call as well.
- **The fallback stays.** While `_spec` is null (the first open of a cached item without a
  connection, or a refused type read) or the layout yields no group, the old fixed long-text list
  renders, so an offline open never loses the description.
- **What #15303 actually holds** (read-only spike `s38`): `Custom.TestingPlan` is set, and
  `Custom.QAStoryPoints` and `Custom.QAAssignee` are **not** — nor is `Microsoft.VSTS.Scheduling.
  StoryPoints`. So the detail page shows Acceptance Criteria, Testing Plan and Classification
  (Value area) there, and the two QA fields appear in the **edit** form, which renders every
  editable field of the layout whether it is filled or not (checked on the emulator: Planning
  shows QA Story Points empty, Priority 2, QA Assignee "Unassigned", Risk "Not set"). Bug
  **#3898**, reached through the shared query "Bugs To review", does carry them and its detail
  page now shows Planning with Story Points 1, QA Story Points 1 and its QA engineer as an
  identity row with an avatar.

### Phase 5 notes (2026-09-12)

The Links and Attachments pages, and the rich editor's "Insert image". What deviated from §4.3 and
§4.5 while building it:

- **Which panel is editable comes from the layout, not from a name.** `FormControl` now parses
  `LinksControlOptions/WorkItemLinkFilters[@FilterType="excludeAll"]`, which is what marks the
  **Development** group (Git branches, commits, pull requests, builds) as carrying no work item link
  at all; that group and **Deployment** (`DeploymentsControl`) render one line, *"Managed in Azure
  DevOps"*, while **Related Work** and the **Links** page are real, editable lists. The three
  disabled "Available after creation" cards are gone, and the `FormSpec` cache key was bumped to
  `form:spec2:` so a spec cached before the flag is re-read rather than showing Development as an
  always-empty link list.
- **The Links and Attachments pages are visible in both modes.** `pageViewsFor` now appends them
  after Details and the custom pages (History is still never shown): a section at the bottom on a
  phone under its own heading, a tab on a tablet. `FormGroupView.panel` (`FormPanelKind`) says which
  panel a group is.
- **Link kinds are mapped locally.** `wit/workitemrelationtypes` would cost a call that the page
  must work without offline, so `LinkKind` carries the six addable kinds (Parent, Child, Related,
  Predecessor, Successor, Duplicate of) plus Duplicate and an **Other** bucket for anything else,
  under its raw `rel`. "Duplicate" itself is shown but not offered: the pair is added from its
  "Duplicate of" end. Rows resolve through one `WorkItemRepository.batch` (title, type, state) and a
  target that cannot be read shows as its bare id.
- **Relations live in `WorkItemFormState`.** The item's own list is the base, removals are remembered
  by key and additions in a pending list, so `relations` is base − removed + added. The key cannot
  be the URL: the service **rewrites a relation's URL with the project GUID** and drops the
  `?fileName=` query (spike s37), so `WorkItemRelation.key` is the `rel` plus the **target id** of a
  work item link or the **attachment guid** of a file. Before that, an attachment written straight
  away stayed pending and the next Save was refused with "Relation already exists" (seen on the
  emulator). On
  create everything is an addition and rides in the create patch (spike w16) — including the parent
  of an "Add child", which is now a row on the Links page instead of only a line in the header. A
  second parent **replaces** the first in one patch. `buildRelationOps` resolves the removed keys to
  indices against the item it is given and emits them in **descending** order.
- **`test /rev` does not guard a relation patch** (spike s35): adding and removing a link left `rev`
  at 1 and `System.ChangedDate` untouched, while an attachment did bump both. So the save **re-reads
  the item** first, refuses on a moved revision (the conflict banner) and takes the removal indices
  from that copy — the narrowest window REST allows. Recorded in research/01 §2.6.
- **Links wait for Save, attachments do not.** An upload that is not attached is an orphan, so on an
  existing item the `AttachedFile` relation is patched the moment the upload finishes
  (`attachmentsOnly: true`, so a link the user added but has not saved is not dragged along), and
  `rebaseRelations` folds the server's list back in while keeping the still-pending link changes.
  That needed `WorkItemRepository.patch` to ask for **`$expand=relations`**: without it the response
  carries no relations, the rebase could not see the write, and the next Save was refused with
  "Relation already exists" (found on the emulator). It also stops every field patch from dropping
  the cached relations, since a patch bumps `rev` and the cache merge only keeps them at an equal one.
- **Attachments.** Rows are read off the relation: `attributes.name` (falling back to the URL's
  `?fileName=`), `attributes.resourceSize`, the guid from the URL. Images show a thumbnail fetched
  with the bearer token and cached by guid in memory and under `attachments/` in the app support
  directory; tapping one opens a full-screen `InteractiveViewer`. Any other file downloads to the
  temp directory and goes to the **share sheet** (`share_plus`, already a dependency) rather than
  `open_filex` — one dependency fewer and the user picks the app. The client cap is the documented
  60 MB and an oversize file is **never read into memory**: the size is checked first.
- **`System.AttachedFileCount` does not exist on a read** (spike s36), not even with `$expand=all`,
  and neither do `RelatedLinkCount` or `ExternalLinkCount`; w17 had read the count from the create
  response. The detail page's new Attachments fact counts the `AttachedFile` relations instead.
- **"Insert image" is a real toolbar button.** `HtmlToolbarOptions.customToolbarButtons` takes it
  cleanly, so it sits at the end of the editor's own toolbar (not in the app bar), runs the same
  picker and upload, adds the `AttachedFile` relation so the upload is not orphaned, and pastes
  `<img src="…">` at the caret through `evaluateJavascript` with `jsonEncode` — the plugin's own
  `insertHtml` interpolates into a single-quoted JavaScript string, which a file name with a quote
  would break. **The image does not render inside the editor**: Summernote's WebView sends no
  Authorization header (research/01 §10.3), so it shows a broken-image glyph until Done, after which
  the control's preview and the detail page render it properly through `RichTextView`, which now gets
  the headers on the form too.
- **A photo gets a readable name.** `image_picker` copies the file into the app cache and names it
  after the platform id — the Android photo picker gave `19.png` — so a name that carries no meaning
  is replaced by `image-20260912-100901.png` (`photo-…` from the camera), keeping the extension.
- **New dependencies:** `image_picker` 1.2.3 (camera and photo library) and `file_picker` 10.3.10
  (any other file), both free and open source, both pinned. Neither needs an Android permission (the
  system photo picker and the Storage Access Framework), only the optional `android.hardware.camera`
  feature so the app still installs on a tablet without one. The iOS `NSCameraUsageDescription` and
  `NSPhotoLibraryUsageDescription` strings said Boardhop does not use them; they now say what it
  actually does.

## 9. Spike results (2026-09-12) and what they change

Scripts s24, s25, s26 (read-only) and w16, w17, w18 (scratch project); findings in `research/spikes/results/README.md`.

| Question | Answer | Change to the plan |
|---|---|---|
| Can the app read the process layout? | Only for types an inherited process has customized. Every stock type, including Epic in CloudCover 2.0 and all nine in the scratch project's system Agile process, answers HTTP 400 VS403115 "locked". | The Processes API is out. |
| Is there a universal layout source? | Yes: `wit/workitemtypes/{type}` returns `xmlForm` (5–7 KB) for every type: the legacy `<FORM><Layout>` tree with the header groups, a `TabGroup` (Details, History, Links, Attachments), labeled groups, columns with percent widths and the custom fields in place. It matches the process layout group for group. | **`FormSpec` is built from `xmlForm`** (a small XML walk: Group → Column → Control, TabGroup → Tab), plus `fields?$expand=All` for rules and the org field list for types. The field-list fallback stays for a parse failure only. The read is the one `types()` already makes, so the layout costs nothing extra. |
| Is the Assigned To allowed-values list the people picker? | No: it is empty in both projects. | Kelly's pick cannot work. Proposal: team members (`teams/{id}/members`, 13 and 2 rows, avatars through the `_links.avatar` path fixed for reviewers) as the cached offline list with recent assignees first, and a project-scoped `graph/subjectquery` (3 hits for "a" in CloudCover) as you type. **Kelly agreed the same day.** |
| What does a dry run return? | HTTP 200 with the whole item minus id and rev, including the server's defaults (State, Reason, Area, Iteration, CreatedBy) and the format map; errors as `RuleValidationErrors[]` per field; an unknown field as a different exception without rule errors. | The form opens with one dry run of `{type}` plus the pre-fills, so its defaults are the server's rather than guessed. Error mapping stays as planned; the unknown-field case becomes a generic banner. |
| Can a new item start in a column's state? | No: only the type's initial state is legal on create (Bug as Active is refused). Create then `PATCH` State works (New → Active, Reason set by the server). | Board-column create is two calls; the card lands in the column after the second, and if the second fails the item still exists in its initial state, which a snackbar says. The State chip is read-only on a new item. |
| Do links and attachments ride in the create call? | Yes: the parent relation, tags, numbers and a Markdown description created #15539 in one call; an uploaded file's `AttachedFile` relation created #15540 with the count at 1. | As planned. Attachment bytes need the Authorization header (203 sign-in page without it). |
| Defaults for area and iteration | `teamsettings` carries `defaultIteration`, `backlogIteration`, `defaultIterationMacro` and `bugsBehavior`; `iterations?$timeframe=current` gives the sprint; areas are a single node in both projects while CloudCover has 107 iterations. | The iteration picker lists the team's iterations first (current marked), the whole tree behind "All iterations". |
| Templates | None exist in either team. | The chooser shows templates only when the team has some; verification waits for one on the scratch team. |
| Type chooser order | `backlogconfiguration` gives the levels top-down with their types and `bugsBehavior`; `Microsoft.HiddenCategory` lists the eight types to hide. | As planned. |
| Initial states | Every type has exactly one `transitions[""]` target. | State is not chosen on create. |

Test data created: #15539 (Task, child of 15503, Markdown description), #15540 (Task with an attachment), #15541 (Bug moved New → Active). All in the scratch project, left for the emulator walkthrough.
