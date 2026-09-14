# 16. Mentions: tagging people, work items and pull requests in comments

Planned with Kelly on 2026-09-14 after three research passes (the Azure DevOps wire format
with spikes s45/s46/w30, a survey of Slack, Teams, Jira, GitHub, Linear, Notion, Confluence,
Azure DevOps web and Apple Messages, and a map of every composer in the app). This document
carries the decisions; the phase briefs and NEXT-STEPS item 21 carry the state.

## 1. What the service does (verified)

- **A mention is created by the service at save time**, not by the client's rendering. A work
  item comment that carries one reads back with a non-empty `mentions[]` (`artifactType:
  Person`, `targetId` = identity GUID) and a `<a href="" data-vss-mention="version:2.0,{guid}"
  class="mention-link">@Name</a>` anchor in `renderedText`. A hand-typed `@Name` is never a
  mention and notifies nobody.
- **Work item comments, `format=markdown`** (the route the app already uses, api
  `7.1-preview.4`): `@<{identityGuid}>` in the text is a real mention. The HTML anchor pasted
  into a markdown body is escaped and is *not* one. `format=html` with the anchor also works;
  the web UI itself writes that form.
- **PR thread comments and replies**: `content` is Markdown stored verbatim; `@<{guid}>` is the
  mention form (`ms.vss-code.git-pullrequest-comment-event` exposes a `mentionedUsers` role, so
  the service parses it). **A PR comment has no rendered form and no `mentions[]`**: the app
  resolves `@<guid>` to a name itself when displaying one.
- **The GUID is the Azure DevOps identity id** (`connectionData.authenticatedUser.id` =
  `profile/profiles/me` `id` = `graph/storagekeys/{descriptor}` = `teams/{id}/members[].identity.id`).
  The Graph `originId` is the Entra object id, a different GUID, and does not work.
- **`#123` and `!456` need no client syntax**: the service auto-links them at render time
  (`data-vss-mention="version:1.0,{id}"`, class `mention-widget-workitem` for a work item) and they
  never appear in `mentions[]`. A PR comment naming `#id` writes `Mentioned in !{prId}` to that
  work item's History.
- **The relay needs no change**: `System.History` stores the comment's raw text, so a markdown
  `@<guid>` lands as `@<guid>` and `routing_view.dart`'s `_mentionsIn` (both spellings) routes
  `Verb.mentioned` ("mentioned you", priority 100). Web HTML mentions land as the anchor and are
  caught by the other regex.
- **Identity lookup**: `graph/subjectquery` (project-scoped through `graph/descriptors/{projectId}`,
  project *id* not name, s30) gives descriptors; `graph/storagekeys/{descriptor}` gives the GUID;
  `teams/{id}/members` carries the GUID directly and is cached. The web's own
  `IdentityPicker/Identities` returns the GUID in one call but is undocumented and may need
  `vso.identity`, which the registration lacks; `identities?searchFilter=General` answers 0 rows.
- Unverified: whether ADO's own e-mail/bell fires for an API-posted mention (needs a second
  identity); `@<guid>` in a Markdown-format *field*; the pipeline approval comment; the exact
  shape the web stores for a PR mention (none exists in the org yet).

## 2. Best practice consensus (survey)

Open on `@` only at a word boundary (start of text or after whitespace, `(`, `[`) so e-mail
addresses never trigger; show results on the bare `@`; allow spaces in the query so full names
match; close on Escape, tap outside, the caret leaving the token, a newline, or a space directly
after the `@`. Case-insensitive contains over every name token and the e-mail. Participants of
the item before recently mentioned before team members before directory hits (GitLab 18132: never
let a stranger float above a participant); highlight the matched letters; secondary line says why
the person is here or disambiguates with the e-mail. A list anchored above the composer, fixed
height with internal scrolling, never a sheet (you keep typing). Insert a styled run plus one
space; mentions stay editable. Arrows plus Enter to pick; Tab stays field traversal.

Flutter: every mention package on pub.dev is abandoned, `WidgetSpan`-based (asserts in
`buildTextSpan`, flutter#63863) or ignores the IME composing range. Build it, copying Flutter
3.47's `RawAutocomplete` (`OverlayPortal.overlayChildLayoutBuilder`, the inset/safe-area math,
`ExcludeFocus` on the options, `TextFieldTapRegion`). Never a `GestureRecognizer` or a different
font size in a `buildTextSpan` span (throws on mobile / crops the field); never touch
`controller.selection` from a listener (restarts the Android IME); honour `withComposing`.

## 3. Decisions (Kelly, 2026-09-14)

| # | Decision |
|---|---|
| M1 | **Surfaces in v1:** the work item Discussion composer, the PR Comments-tab composer, the thread reply box, and the new-thread box on a diff line. PR description (not editable today) and the HTML field editor (WebView, needs a JS-side picker and a spike) are later phases. |
| M2 | **Scope: project.** Participants of the item or thread, then people recently mentioned in this project, then cached team members, then a project-scoped directory search. Never the whole org: mentioning an outsider invites them into the organization. |
| M3 | **People only.** No teams or groups in v1. |
| M4 | **Placement: a floating list anchored above the field**, between it and the keyboard, about five rows, scrolling inside; `RawAutocomplete`'s 3.47 layout math (opens down when there is more room below, i.e. on a tablet). An inline strip is the fallback if the glass dock's inset fights it. |
| M5 | **Bare `@` shows** participants → recents → team members, instantly from cache; the directory is searched only from two characters, debounced 300 ms, last request wins. |
| M6 | **Token: styled text, edits break it.** `@Kelly Kamm` in `colorScheme.primary`, medium weight. Backspace deletes one character; any edit inside the run turns it into plain text (no longer a mention), which is what the server would do with it anyway. The caret may sit inside a token. |
| M7 | **Unresolved `@word`: a quiet hint** above Send ("@kelly is not a mention. Pick from the list to notify someone."), only while the text has an `@word` that is not a picked mention. No dialog. |
| M8 | **`#` and `!` pickers too.** `#` matches cached work items (id or title: the assigned-to-me list, the current board, linked items) at once and the work item search API from three characters; `!` matches the cached active PR list by id or title, no API call. Inserts plain `#123` / `!456` (the service links them). Triggers are a table keyed by character. |
| M9 | **Rendering on read:** a person mention is a styled `@Name` run, not tappable (no person page). Work item comments: restyle the server anchor. PR comments: resolve `@<guid>` from the PR's people (author, reviewers, comment authors), then the cached team, then the directory by id, cached; unknown reads `@someone`, never a GUID. |
| M10 | **`#123` / `!456` on read are styled and tappable**: they route to the work item or PR (work item comments already carry the server link; PR comments get the same from a regex). |
| M11 | **Endpoint: the existing Graph pair** (`subjectquery` + `storagekeys`, `vso.graph`), promoted out of the form repository. `IdentityPicker` is a separate on-device probe, not on the critical path. |
| M12 | **Hardware keyboard:** Up/Down move the highlight, Enter and numpad Enter pick, Escape closes, all only while the list is open (a disabled action falls through so caret movement never regresses). Tab is not bound. |
| M13 | **Offline:** participants, recents and team members (all carry the GUID) can be inserted; a directory hit whose GUID is not yet resolved shows disabled with a reason. A queued work item comment therefore always carries real GUIDs (serialization happens before `enqueueComment`). |
| M14 | **Matching:** case-insensitive contains on any part of the display name or e-mail; `kel ka` matches Kelly Kamm; matched letters bold; secondary line "On this item" / "In this thread" or the e-mail when two names collide. Hidden `me` is allowed (you can mention yourself; it is how Kelly tests the relay). |
| M15 | The GUID is resolved **at insert time** (a Graph hit goes through `storagekeys` when picked), so a failure surfaces while the list is open, not at post time; a person who cannot be resolved is never inserted as a mention. |

## 4. Design

### 4.1 Pure Dart: `lib/core/text/mention.dart`

```dart
enum MentionKind { person, workItem, pullRequest }
enum MentionWire { markdown, html }   // `@<guid>` vs the data-vss-mention anchor

class MentionSpan extends Equatable {   // read side
  final String text;                    // what to draw
  final MentionKind? kind;              // null = plain text
  final String? id;                     // guid, or the artifact id
  final bool tappable;                  // artifacts only (M10)
}

abstract final class Mentions {
  static final personAngle = RegExp(r'@<([0-9a-fA-F-]{36})>');
  static final personAnchor = RegExp(r'''<a\b[^>]*data-vss-mention=["']version:2\.0,([0-9a-fA-F-]{36})["'][^>]*>(.*?)</a>''', caseSensitive: false, dotAll: true);
  static final artifactAnchor = RegExp(r'''<a\b[^>]*data-vss-mention=["']version:1\.0,(\d+)["'][^>]*>(.*?)</a>''', ...);
  static final workItemRef = RegExp(r'(?<![\w/])#(\d+)\b');
  static final pullRequestRef = RegExp(r'(?<![\w/])!(\d+)\b');
  static String person(String guid, MentionWire wire, {required String displayName});
  static List<MentionSpan> parseMarkdown(String content, {required String? Function(String guid) nameFor});
  static List<MentionSpan> parseHtmlText(String html, ...);  // for PlainText and enrichment
}
```

`PlainText.strip` learns the angle form (`@<guid>` → `@Name` when a name is known, else `@someone`);
the Kotlin and Swift ports do the same (they must stay character-for-character identical, and
RunnerTests cover the Swift side).

### 4.2 Data: `lib/data/repositories/people_repository.dart`

Promoted out of `WorkItemFormRepository`, which delegates to it (its cache keys move with it):
`teamMembers(org, projectId, teamId)`, `projectDescriptor(org, projectId)`, `searchPeople(org,
projectId, query)`, `resolveIdentityId(org, person)`, plus new `identityById(org, guid)` (the
name for a `@<guid>` in a PR comment: memory → `JsonCache` → `vssps identities/{id}`; failures
remembered for the session) and `rememberIdentity(org, IdentityRef)` (seeds that cache from
comment authors, reviewers and picked people). Registered in `AccountDeps` as `people`.
`MentionRecents` (shared preferences, `org:project`, last 5 people) mirrors
`FormPrefs.recentAssignees`. `WorkItemComment` gains `mentions` (list of GUIDs, parsed from
`mentions[]`, which the list read already returns).

### 4.3 Widget: `lib/features/shared/mention/`

- `MentionController extends TextEditingController`: `tokens` (`start`, `end`, `kind`, `id`,
  `label`), re-derived on every `value` change by diffing (a token whose run changed is dropped,
  M6); `buildTextSpan` splits at the union of token boundaries and the composing range, styles
  token runs with `colorScheme.primary` + `FontWeight.w500` only; `toWire(MentionWire)` emits
  `@<guid>` for people (label untouched for artifacts); `unresolvedAtWords` for the hint (M7).
- `MentionSource`: `participants()`, `recents()`, `members()`, `search(query)` (≥ 2 chars),
  `resolve(person)`; `workItems(query)` (local then search API from 3 chars), `pullRequests(query)`
  (local); `me`; `onPicked`. All closures, so widget tests need no mocks.
- `MentionField`: wraps a real `TextField` (existing `find.byType(TextField)` finders keep
  working), detects the trigger (`@`, `#`, `!` at a word boundary), tracks the query to a newline,
  a `.`, or a space directly after the trigger, shows the list through `OverlayPortal` with
  `RawAutocomplete`'s layout (up on phones, `mostSpace`), rows `IdentityAvatar` + name + secondary
  line at ≥ 48 dp, artifact rows with the type tile / PR icon; inserts label + one space, caret
  after it via a post-frame callback; `Shortcuts`/`Actions` gated on "open" (M12); `ExcludeFocus`
  and `TextFieldTapRegion` as `RawAutocomplete` does; hint line (M7) rendered by the host above its
  buttons.
- Hosts: `CommentComposer` (work item discussion and PR Comments tab), `ThreadCard` reply, the
  diff `_ComposerView`; each takes `MentionSource? mentions` (null = plain field, so every existing
  host and test keeps compiling) and sends `controller.toWire(MentionWire.markdown)` at submit,
  before `enqueueComment`.

### 4.4 Read side

- `RichTextView` (HTML): `_AuthedWidgetFactory` restyles `a[data-vss-mention]`: `version:2.0`
  becomes a non-tappable styled run; `version:1.0` becomes a styled tappable run routing to
  `Routes.workItem` / `Routes.pullRequest` (the class or the href says which).
- `MarkdownBody` (PR comments, markdown fields): an `InlineSyntax` + `MarkdownElementBuilder`
  pair for `@<guid>`, `#123`, `!456`; names through `PeopleRepository.identityById` seeded from the
  PR's people; artifacts tappable.

### 4.5 Sources per host

- Work item detail: participants = comment authors + assignee (+ CreatedBy/ChangedBy when they
  carry an id); team from the project's default team (the form already resolves the project id);
  `#` local = the cached lists for the project plus the item's linked ids; `!` = cached active PRs.
- PR detail, thread card, diff page: participants = `createdBy`, `reviewers`, thread comment
  authors; `me` from `meId(org)`; project id from `PullRequest.projectId`.

## 5. Acceptance (simulators, then the physical phones for the push)

1. `@` at the start, after a space, after `(`; not inside `kelly@kammcs.com`. Bare `@` lists
   participants first, then recents, then team; `ke` narrows; `kel ka` matches; matched letters bold.
2. Pick → `@Kelly Kamm ` styled, caret after the space; backspace into it un-styles it; a typed
   `@kelly` shows the hint; Send posts `@<guid>`; the comment reads back styled; `mentions[]` is
   non-empty (scratch #15545) and Kelly's phone gets "mentioned you" through the relay.
3. Same on a PR thread reply and a diff-line thread (scratch PR 8334); the posted comment renders
   `@Name`, not a GUID; a comment with `#15545` and `!8334` shows tappable links that open them.
4. `#` lists cached items then search hits from three characters; `!` lists active PRs; both insert
   the plain id.
5. Keyboard on the iPad simulator: arrows, Enter, Escape; arrows still move the caret when the list
   is closed. Both breakpoints, both themes, xxxL text, phone landscape, dark.
6. Offline (Wi-Fi off): the list shows cached people; a Graph hit is disabled with a reason; a queued
   work item comment carries the GUID and posts when back online.
7. Android emulator: Gboard with predictions on, type `@kel` with a composing region, pick, type on;
   no field clearing.

## 6. Out of v1

PR description editing, HTML-field mentions (needs a Summernote-side picker spike), groups, tapping
a person, `IdentityPicker` probe (separate NEXT-STEPS line), ADO e-mail verification (Kelly mentions
themself once from the app and checks mail).
