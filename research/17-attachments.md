# 17. Images and files in comments (work items and pull requests)

Planned with Kelly on 2026-09-14 after two research passes (Azure DevOps facts with spikes w32/s50;
the app's existing pieces plus a survey of the web, Slack, Teams, Jira, GitHub and Flutter's
clipboard limits). Decisions here; state in NEXT-STEPS item 23.

## 1. What the service does (verified, w32/s50)

- **Two-step write on both surfaces:** upload the bytes as `application/octet-stream` (any other
  `Content-Type` is HTTP 400), then reference the returned **absolute URL** from the Markdown
  comment: `![name](url)` for an image, `[name](url)` for a file. Nothing else: no relation, no
  registration. The web writes exactly these shapes (corpus: 14 comment images on 150 items, 0 with
  an `AttachedFile` relation).
- **Work item store:** `POST {org}/{project}/_apis/wit/attachments?fileName=…&uploadType=simple&api-version=7.1`
  → 201 `{id, url}`; the URL carries the project GUID and `?fileName=` (keep it: without it the
  fetch answers `application/octet-stream` with `Content-Disposition: attachment`). 60 MB per file,
  100 per item; 1 MB `simple` upload fine; **no DELETE** (405), an unreferenced upload is orphaned.
- **PR store:** `POST {org}/{project}/_apis/git/repositories/{repoId}/pullRequests/{prId}/attachments/{fileName}?api-version=7.1`
  → 201 `Attachment {id:int (1, 2, …), displayName, url, contentHash, author, createdDate}`; keyed by
  **file name**, a duplicate name is HTTP 400 (uniquify before upload); `GET …/attachments` lists;
  `DELETE …/attachments/{fileName}` works. Size cap undocumented and untested above 6.5 KB.
- **Comments:** work item `format=markdown` `![x](url)` → `renderedText` has a well-formed
  `<img src="{absolute url}">`; a file link → `<a rel=nofollow>`. PR comments store the Markdown
  verbatim (no rendered form). Rate cost of an upload ≈ one work item read; downloads carry no cost.
- **Read side:** every attachment URL is authenticated; without the bearer token the fetch answers
  **HTTP 203 with a 16 KB sign-in page**, not a 401. Two hosts appear in client data
  (`dev.azure.com/{org}/{projectGuid}/_apis/wit/attachments/…` and the legacy
  `{org}.visualstudio.com/…`) plus `…/_apis/git/repositories/{repo}/pullRequests/{id}/attachments/{name}`.
- **Two live bugs (fix first):** (a) an `html`-format work item comment's `renderedText` rewrites
  `<img src>` to `"\x06/{guid}?fileName=…"` (a U+0006 sentinel and a base-less path) — 12 of 33
  client comment images look like that and render broken today; render such comments from `text`
  (absolute URLs, otherwise identical) or normalise the prefix. (b) `MentionMarkdown` has no
  `imageBuilder`, so `![](attachment url)` in a PR comment, PR description or Markdown field renders
  as an empty `SizedBox` (no headers, silent error builder).
- Unverified: the web's rendering (corpus says the shapes match), anything above 1 MB, the PR cap,
  uploads with the app's Entra token (`vso.work_write`/`vso.code_write` are in `.default`; the spike
  ran on the PAT).

## 2. What the app already has

`attachment_picker.dart` (camera / library / file sheet, `PickedAttachment`, the 60 MB guard before
bytes are read, `photoFileName`), `WorkItemFormRepository.uploadAttachment` / `attachmentBytes`,
`AttachmentSource` (`bytes`, `upload`, `commit`, `headers`), `AttachmentInfo` (`isImage`, glyphs),
`AttachmentRow`, `AttachmentImage` (memory 24 + disk cache, no TTL), `AttachmentViewer` (root
navigator lightbox), `openAttachment` (image → viewer, else share sheet), `RichTextView`'s authed
`CachedNetworkImageProvider` for HTML bodies, `AdoClient.send(body, contentType)` and `getBytes`.
Nothing on the PR side; the PR pages hold no bearer token today. `WriteQueue` stores a comment as a
string only. `AttachmentRef.fromJson` reads `id` as a String (the PR store answers an int).

## 3. Decisions (Kelly, 2026-09-14)

| # | Decision |
|---|---|
| T1 | **Surfaces:** all three composers — work item Discussion, PR Comments tab, thread replies and diff-line threads. |
| T2 | **Any file type.** Images render inline; other files become a download row. The service's own refusal message is shown verbatim; no client-side type list. |
| T3 | **Upload on Send.** Chips show picked files from memory at once; on Send every file uploads (one progress state on the composer), then the comment posts with the links. Cancelling leaves nothing behind (the work item store cannot delete). A failed upload keeps the text and chips and shows the message inline. |
| T4 | **Comment only, no `AttachedFile` relation** for work item comment files (matches the web; no revision bump). |
| T5 | **Compression:** camera path only, `maxWidth: 2048, maxHeight: 2048, imageQuality: 85`, name forced to `.jpg`; library picks and files stay byte-exact. The 60 MB guard stays the boundary. |
| T6 | **Offline:** attachments need a connection — the attach button is disabled with a tooltip while the app is offline; a work item comment written offline still queues as text and the snackbar says the files were not included. |
| T7 | **Several files per comment, one pick at a time;** the chip strip accumulates; any chip can be removed before Send. |
| T8 | **Markup as a trailing block on Send:** the wire text is `toWire(markdown)` followed by one `![name](url)` / `[name](url)` per attachment, each on its own line. The visible field never carries URLs; mention tokens stay intact. |
| T9 | **Reading:** inline images at up to about 320 pt tall, tap opens `AttachmentViewer`; files as a row (icon, name, size) that opens the share sheet through `openAttachment`; a failed fetch shows a broken-image glyph with the name, never a blank. |
| T10 | **Gboard rich content:** `contentInsertionConfiguration` passed through `MentionField` so an image inserted from the Android keyboard becomes a pending chip. Android only; **no clipboard-paste package** in v1 (iOS prompts on every programmatic read; no interception exists). |

## 4. Design

- **`lib/features/shared/attachments/`**: `PendingAttachment` (`PickedAttachment picked`, `bool uploading`, `String? error`), `PendingAttachmentsBar` (a `Wrap` of `InputChip`s above the field: 24 pt `Image.memory` avatar or the type glyph, name and size, `onDeleted`), `attachmentMarkdown(name, url, isImage)`, `isAttachmentUrl(url)` (both hosts, both stores), `uniqueAttachmentName(name)` for the PR store (timestamp suffix before the extension).
- **Composer seam:** `CommentComposer`, `ThreadCard` and the diff `_ComposerView` take `AttachmentSource? attachments` (null = no attach button). `AttachmentSource.upload` on work items = `WorkItemFormRepository.uploadAttachment`; on PRs a new `PullRequestRepository.uploadAttachment(org, pr, fileName, bytes)` (path form, octet-stream, tolerant `AttachmentRef` id) and `attachmentBytes(url)`. Send = upload all → append markup → post; busy state covers both.
- **Read side:** `MentionMarkdown` gains `headers`/`attachments` and an `imageBuilder` that uses `CachedNetworkImageProvider(url, headers)` for attachment URLs (managed 30-day cache), `errorBuilder` with the glyph, capped height, tap → viewer; `onTapLink` routes an attachment href to `openAttachment`. Work item comments of `format == 'html'` render from `text`. The PR pages build `_headers` from the token as the work item page does.
- **Picker:** `pickAttachment(camera)` passes the T5 sizing; the sheet is reused as-is.

## 5. Acceptance

1. Work item #15545: attach a camera photo (simulator: a library image) and a `.txt`, Send → both upload, the comment reads back with the inline image and a file row; `renderedText` carries the absolute URLs; tapping the image opens the viewer; the file row opens the share sheet.
2. PR 8334 Comments tab, a thread reply and a diff-line thread: the same; the PR attachments list shows the uploads; a second upload of the same photo name does not collide.
3. Remove a chip before Send; cancel a reply with chips → nothing uploaded (no new rows in the PR store).
4. Offline: the attach button is disabled with its tooltip; a queued work item comment posts later without files and said so.
5. The two read bugs: an `html`-format client comment image renders; a web-authored PR comment image renders; a failed fetch shows the glyph.
6. Both breakpoints, both themes, xxxL text; Android emulator with Gboard's image button if available.

## 6. Out of v1

Clipboard image paste, staged offline uploads through the write queue, `AttachedFile` relations
from comments, PR description editing, deleting a PR attachment from the app, the unmanaged
`AttachmentImage` disk cache's growth (NEXT-STEPS note).

## 7. What landed (2026-09-14)

T-A: `lib/features/shared/attachments/` (`attachment_links.dart`, `inline_attachments.dart`,
`inline_attachment_source.dart`), `WorkItemComment.displayHtml` and the sentinel repair in
`RichTextView`, `MentionMarkdown`'s authenticated image builder and attachment link routing, the PR
pages' bearer headers, `PullRequestRepository.uploadAttachment/listAttachments/attachmentBytes`.
T-B: `pending_attachments.dart` (`PendingAttachment`, `PendingAttachmentsBar`, the
`ComposerAttachments` mixin), the attach button and upload-on-Send in all three composers, camera
sizing, Gboard pass-through, tappable file links and images in html comments. T-C: §5 items 1–3, 5
and 6 passed on the iPhone 17 and iPad Pro 13" simulators (dark, xxxL, landscape, embedded pane);
item 4 (offline) by widget tests only; Android blocked by this Mac's redirect URI. Spikes s51–s53:
the earlier PR-file 500 was a dead spike blob on the service. Walkthrough:
`research/walkthroughs/2026-09-14-attachments.md`.

