# Attachments walkthrough — iPhone 17 and iPad Pro 13-inch, 2026-09-14

Phase T-C of research/17, walking that document's §5 acceptance list after T-A (the read side and
the data layer) and T-B (attaching from the three composers). Devices: iPhone 17 simulator
`9CB22607-F6D0-4C47-8B2D-4AC4F60A6A31` and iPad Pro 13-inch (M4)
`929DE352-434C-4CE6-BB96-5C34212741E8`, both **debug** builds from `flutter run`, plus one
attempt on the `Pixel_10_Pro` Android emulator. Signed in as Kelly (puremedia), project
**DevOps Mobile App** (scratch) and its pull request 8334. Everything outside that project was
read-only; the three writes this phase was allowed are listed below and nothing else was posted,
voted, resolved or run.

Screenshots live in the session scratchpad and are **not** in the repository.

**Console: no `EXCEPTION`, no `overflowed`, no `RenderFlex` and no assert** on either simulator
over the whole run (19 lines each, the rest being the inappwebview banner).

`flutter analyze` clean, `flutter test` **885 passed** (880 at the end of T-B, so 5 new cases).

---

## Per acceptance item (research/17 §5)

### 1. Work item comment: upload, read back, open — pass (iPhone, iPad)
Two library images picked into chips on #15545, then Send. Both uploaded in order and the comment
posted as one body. Read back through the service (read-only probe
`research/spikes/s53_tc_readback.py`) the comment is `format: markdown` and its stored text is
exactly the T8 trailing block — the wire text, a blank line, `![name](absolute url)`, a blank
line, the second one — and its `renderedText` carries two `<img src="{absolute url}">`. The item's
`relations` stayed `[]`, so no `AttachedFile` was created (T4). Read back **through the app** both
images render inline and tapping one opens `AttachmentViewer`.

T-B's earlier comment on the same item covered the mixed case (one image, one `.txt`): the file
row opens the share sheet and the image opens the viewer.

**The Send-in-flight state, which T-B could not catch, is now on the device.** Tapping Send with
two chips (966 KB and 1.8 MB) and shooting in the same breath: both chips lose their delete
button and grey out, the first shows its progress spinner, the attach button is disabled, and the
Send glyph is replaced by a spinner. One busy state covers the uploads and the post, as T3 asks.

### 2. Pull request: a thread reply, a diff-line thread, the store — pass (iPhone)
Two writes on scratch PR 8334:

- **thread 42727, comment 4** — `T-C: a text file on a thread reply.` with `tc-check.txt`
  attached from the Files app. Stored as
  `[tc-check.txt](…/pullRequests/8334/attachments/tc-check-20260914-190317.txt)`: the label is the
  name that was picked, the URL carries the uniquified one.
- **new thread 42739, comment 1** on `/src/app.ts:2` — `T-C: a diff-line thread with an image.`
  with a library photo. The image renders inline under the line, capped, and tapping it opens the
  viewer over the diff. `threadContext.filePath` is set, so the thread is a real diff-line thread
  and the app deep-links back into the file view from `?thread=42739`.

The pull request attachment store went from **4 rows to 6** — exactly these two files — and the
second photo of the run went up under its own stamped name beside T-B's, so `uniqueAttachmentName`
keeps the store's file-name key from colliding (a duplicate name is a 400, w32 §4).

### 3. Remove a chip, cancel with chips, files alone — pass (iPhone)
On a thread reply: two chips (a photo and the text file), the photo removed with its chip's X, then
**Cancel** with the remaining chip still there. The reply box closed and the chips went with it.
The store count above proves nothing was uploaded: 4 before the run, 6 after, and the two are the
posted files. Nothing is uploaded until Send, so a cancelled work item composer leaves nothing
either — which matters, because the work item store has no DELETE (w32 §2).

A chip on its own is a valid comment (T3): it flips a thread's button row from Resolve to
Reply / Reply & resolve, and it lights the work item composer's Send with an empty field. Neither
was posted.

### 4. Offline — not run
This Mac's default route is a Thunderbolt Ethernet service, and the session's permission layer
refuses `networksetup -setnetworkserviceenabled`, so the network could not be turned off with any
guarantee of turning it back on. Skipped rather than risked, as the brief said to.

What stands in its place is T-B's test on the real page (`work_item_comment_anchor_test.dart`):
offline, two files attached, Send queues the **text alone** and the snackbar names how many files
were dropped, and the attach button is then disabled with *"Attachments need a connection"*. The
disabled button and its tooltip have never been seen on a device.

### 5. The two read bugs, and a failed fetch — pass with a note (iPhone)
- **Bug (a), the U+0006 sentinel:** the `html`-format comment on #15545 ("spike w32 attachment
  probe B — html image") renders its image. That comment's `renderedText` is the sentinel form, so
  it drew nothing before T-A.
- **Bug (b), Markdown images:** thread 42727 on PR 8334 renders all three of the spike's shapes —
  a pull request-store image, a cross-store `wit` image, and a styled file link. All three were
  empty `SizedBox`es before T-A. **Note, faithfully:** these were written by spike w32 through the
  API, not by the web UI. No web-authored comment image exists on scratch PR 8334, so "the web
  writes the same shapes" is still only the corpus evidence from s50, not something seen rendering
  here.
- **A failed fetch:** the natural case on the scratch data is the dead spike blob
  `w32-pr-probe.txt`, which is a **file row**, not an image, so what the user sees is not the
  broken-image glyph but a snackbar. It read
  *"Could not open the file: AdoServerException(500 : Internal Server Error)"* — the exception's
  `toString`, class name and all. Fixed below. The broken-image glyph on a failed **image** fetch
  stays covered by T-A's widget tests; every image URL on the scratch item and pull request loads,
  so there was nothing on the device to break.

**s51 is settled.** The 500 is the blob, not the client: the same URL answers 500 to the spike PAT
as well, while the fresh `tc-check.txt` uploaded in item 2 fetches 200 `text/plain` and opens the
share sheet with its 150 bytes. Recorded in `research/spikes/results/README.md`.

### 6. Breakpoints, themes, text size — pass (iPhone, iPad)
- **Dark:** chips, the attach button, the composer and an inline image all read correctly.
- **xxxL (`content_size extra-extra-extra-large`):** the chip strip wraps to one chip per row, each
  name ellipsised with its size still readable and its delete button still there, nothing past the
  right edge, and the field grows to two lines with both buttons still on the row.
- **Phone landscape:** the chip strip and the composer clear the floating rail on one side and the
  side inset on the other; nothing overflows.
- **iPad, expanded (1032 × 1376 dp):** the Discussion composer **inside the embedded pane** of the
  Work tab's two-pane layout takes chips and wraps them within the pane, not the window; the pull
  request Comments composer takes one too; and the picker sheet is a **centred dialog** there
  rather than a bottom sheet.
- **Android: blocked, not skipped.** `Pixel_10_Pro` boots and resolves DNS, and the debug build
  installs and launches, but sign-in fails at the first screen with MSAL's
  `redirect_uri_validation_error`: the hash in this machine's `android/secret.properties` is not
  the hash of the debug keystore that signed the build, and neither is on the app registration
  (research/09 A5). The app registration was not touched. So **T10's Gboard image button and T5's
  camera path are still unverified on a device** — they remain unit-tested and wired only.

---

## Findings, and what was done about them

### An image in a work item comment had no height cap — fixed
T9 caps an inline image at 320 pt. The Markdown builder does it, and a pull request comment goes
that way; a **work item** comment is rendered HTML and nothing capped it there. A portrait photo
posted from the phone filled the whole iPhone screen, and on the iPad one image was taller than
the window — the comment above it scrolled away before the image ended.

`_AuthedWidgetFactory` now overrides `buildImage` and wraps the built widget in a
`ConstrainedBox(maxHeight: inlineImageMaxHeight)`. Capping the built widget rather than the `Image`
keeps the package's own `AspectRatio` and tap detector inside the box, and the cap is applied
**only when the src is an attachment URL** (after the sentinel repair), so an icon or a badge in a
description keeps whatever size its author gave it. Three tests in
`comment_attachment_render_test.dart`: a comment image is capped, a repaired sentinel image is
capped, a foreign image is not.

### The failure snackbar said `AdoServerException(500 : Internal Server Error)` — fixed
`openAttachment`'s catch interpolated the exception itself. It now takes an `AdoException`'s
`message` and leaves anything else as it was, so the user reads the service's own words — which is
what T2 says about a refusal on the way up, and should be no different on the way down. Two tests
in `attachments_section_test.dart`.

### After a thread reply posts, the keyboard stays up — open
`ThreadCard._send` does call `FocusManager.instance.primaryFocus?.unfocus()` on success, and on the
work item page the same call drops the keyboard. On the pull request page it does not: the reply
box closes, and focus lands on the **page's own** composer at the bottom (its outline is drawn
focused in the screenshot) so the keyboard never goes. It then survived a tab switch to Files and a
push into the file diff — three screens with a keyboard over them and nothing focused that the user
can see.

Not attachment-specific, and not a one-line fix: the reply field is removed from the tree in the
same frame, and where focus goes next is the framework's `UnfocusDisposition` behaviour with a
second text field in the same scope. Left for its own change.

### A pull request attachment opens under its stamped name — open
The viewer's title and the share sheet's file name are the **uniquified** name off the URL
(`tc-check-20260914-190317.txt`), while the comment shows the label the user picked
(`tc-check.txt`). T-B reported this for the viewer; it is the same on a file row. Fixing it means
carrying the Markdown label down to the opener.

---

## Still open

- Offline on a device (item 4) and Gboard plus the camera path on Android (item 6), for the reasons
  above.
- `listAttachments` still has no caller (T-A open item 4).
- The unmanaged `AttachmentImage` disk cache's growth (research/17 §6).
- The three writes: PR 8334 thread **42727** comment 4, PR 8334 new thread **42739** comment 1 on
  `/src/app.ts`, and work item **#15545** comment **6068650**. The Android emulator now carries an
  installed debug build that cannot sign in.
