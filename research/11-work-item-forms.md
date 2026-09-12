# 11. Work item forms: creating and editing any work item

**Date:** 2026-09-12
**Status:** plan agreed with Kelly (section 7). Not started; spikes in section 6 come first.
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

## 6. Spikes before phase 1

Read-only unless marked; results in `research/spikes/results/README.md`, raw output stays local.

1. **s24 process layout.** For CloudCover 2.0 (inherited) and DevOps Mobile App (stock): project capabilities → process id → layout for Bug, User Story, Task and one custom type. Record page/section/group/control shapes, control types met, whether custom fields appear with their `Custom.` reference names, and the status for a process the caller cannot read. Also read `wit/fields` once and note the field types of every control.
2. **s25 pickers and defaults.** `classificationnodes` depth and shape for both projects; `teamfieldvalues` and `iterations?$timeframe=current` for a team; `wit/tags`; `templates` for the scratch team; `backlogconfiguration` type roles and `bugsBehavior`; `workitemtypecategories` hidden set; `transitions[""]` for each type.
3. **w16 create with dry run (scratch project).** `validateOnly=true` create with a missing required field, an illegal picklist value and a bad state, then a real create of a Task with parent link, tags, Markdown description and a template; read it back. Confirms the error shape on create and that relations can ride in the create patch.
4. **w17 attachment (scratch project).** Upload a small PNG with `uploadType=simple`, attach it, confirm the relation and that the detail page's HTML image path (research/01 §10.3) can show it.

## 7. Decisions (interview with Kelly, 2026-09-12)

| Question | Decision |
|---|---|
| Fidelity to the web form | **Full process layout**: every page, group and control in web order, custom fields included, from the Processes layout API. |
| Types offered | **Backlog types first, the rest under "Other"**: backlog levels from `backlogconfiguration`, then a collapsed section with the remaining non-hidden types. |
| Edit | **One form for create and edit.** The detail page's Edit opens the full form; the title-and-description page goes away. |
| Entry points | **Work app bar `+`, board column `+` (state and lane pre-filled), "Add child" from a work item.** Not on Home. |
| Tablet | **Centered web-like dialog** up to ~960 dp with the sections in columns; the list or board stays visible around it. |
| Phone | **Pinned header, sections stacked**: type, title and the core chips pinned; groups as collapsible cards; extra pages as sections at the bottom. |
| Offline | **Online only, local drafts.** No queued creates, no temporary ids. |
| People picker | **The type's allowed values**, cached a day, filtered locally, recent first. Org-wide Graph search is not in scope. |
| Rich text on create | **Rich editor, following the project**: HTML editor by default, Markdown when the project or the user chooses it; the spike confirms the format op on create. |
| Area and iteration defaults | **The current board's team** (project default team elsewhere): its default area and current iteration. |
| Extras | **Team templates, links (parent, child, related), attachments** are in scope. |
| Layout unavailable | **Field-list fallback**: required and common fields first, then the rest grouped by prefix. |

## 8. Phases

| Phase | Scope | Verify on |
|---|---|---|
| 0 | Spikes s24, s25, w16, w17; `FormSpec` models and repository with the fallback; tests from recorded JSON | Scratch project, CloudCover read-only |
| 1 | Type chooser; `+` in the Work app bar; phone form with header, groups, string/picklist/number/date/boolean controls, state transitions, identity picker, tree pickers, tags; dry-run validation; create; open on success | Emulator against the scratch project |
| 2 | Tablet dialog layout with columns and page tabs; rich-text field through the existing editor; Markdown choice | Tablet emulator, iPad simulator |
| 3 | Edit through the same form (replace `WorkItemEditPage`); transition-driven state sheet on the detail page | Scratch items 15503–15507 |
| 4 | Board column `+`, "Add child", templates, drafts | Scratch board |
| 5 | Links page (add parent/child/related with search) and Attachments page (camera, library, files) | Scratch project |

Open after the spikes: the exact permission the layout call needs (if it is process-admin only, phase 0 ships the fallback as the main path and the layout becomes an enhancement); whether `validateOnly` on create returns rule-set default values or only errors; how a template interacts with required-field validation.
