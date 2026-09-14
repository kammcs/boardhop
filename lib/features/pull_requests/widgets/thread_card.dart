import 'package:flutter/material.dart';

import '../../../core/text/mention.dart';
import '../../../core/util/format.dart';
import '../../../data/repositories/pr_diff_source.dart';
import '../../../theme/theme.dart';
import '../../shared/attachments/inline_attachments.dart';
import '../../shared/attachments/pending_attachments.dart';
import '../../shared/mention/mention_controller.dart';
import '../../shared/mention/mention_field.dart';
import '../../shared/mention/mention_hint.dart';
import '../../shared/mention/mention_markdown.dart';
import '../../shared/mention/mention_source.dart';
import '../../work_items/form/controls/attachment_picker.dart';
import '../../work_items/form/controls/attachments_section.dart'
    show AttachmentSource;
import '../../work_items/widgets/work_item_visuals.dart';

/// One PR thread: status, comments, an inline reply box and a status menu
/// (resolve, won't fix, close, reactivate). Used by the conversation tab and
/// under diff lines; the parent performs the writes.
class ThreadCard extends StatefulWidget {
  const ThreadCard({
    super.key,
    required this.thread,
    this.canAct = false,
    this.busy = false,
    this.onReply,
    this.onSetStatus,
    this.onApplySuggestion,
    this.color,
    this.mentions,
    this.mentionNames = const {},
    this.attachments,
    this.uploads,
    this.offline = false,
    this.pick = pickAttachment,
    this.onOpenMention,
  });

  final PrThread thread;

  /// False on completed or abandoned pull requests: read-only card.
  final bool canAct;
  final bool busy;
  final Future<bool> Function(String text)? onReply;
  final Future<bool> Function(String status)? onSetStatus;

  /// Set when a ```` ```suggestion ```` in this thread can be committed to
  /// the source branch (file thread, latest iteration, active PR).
  final Future<void> Function(PrComment comment, String suggestion)?
  onApplySuggestion;
  final Color? color;

  /// People, work items and pull requests the reply box offers. Null leaves
  /// a plain field (research/16 M1).
  final MentionSource? mentions;

  /// Lower-cased identity GUID → display name, for the `@<guid>` runs in the
  /// comments above: a pull request comment has no rendered form and no
  /// `mentions[]`, so the name is resolved by the page (M9).
  final Map<String, String> mentionNames;

  /// The bearer token for the attachment images in these comments and the
  /// way to open one. A pull request comment is stored verbatim, so an
  /// `![x](url)` in it is rendered here rather than by the service — and
  /// without this it renders as nothing (research/17 §1 bug (b)).
  final InlineAttachments? attachments;

  /// Where a file picked into the **reply** box is uploaded on Send. Named
  /// apart from [attachments], which is the read side of the same feature:
  /// one draws the images already in the thread, the other puts a new one
  /// there. Null leaves no attach button (research/17 §4).
  final AttachmentSource? uploads;

  /// The page's last request could not reach the service (decision T6).
  final bool offline;

  /// The platform picker, injected by the tests.
  final Future<PickedAttachment?> Function(AttachmentPickSource) pick;

  /// Tapping a `#123` or `!456` in a comment.
  final void Function(MentionKind kind, String id)? onOpenMention;

  @override
  State<ThreadCard> createState() => _ThreadCardState();
}

class _ThreadCardState extends State<ThreadCard>
    with WidgetsBindingObserver, ComposerAttachments<ThreadCard> {
  final _controller = MentionController();

  @override
  AttachmentSource? get attachmentSource => widget.uploads;

  @override
  Future<PickedAttachment?> Function(AttachmentPickSource) get attachmentPick =>
      widget.pick;

  @override
  bool get attachmentsOffline => widget.offline;

  /// One busy state covers the uploads and the post (T3).
  bool get _busy => widget.busy || uploadingAttachments;

  /// The reply field and its buttons, so both can be scrolled clear of
  /// the keyboard.
  final _composerKey = GlobalKey();
  bool _replying = false;

  /// The trimmed reply text, so the buttons can follow an empty box.
  String _draft = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  /// The keyboard rising changes the viewport: Flutter only guarantees
  /// the focused field is visible, which leaves Cancel and Reply under
  /// the keyboard, so reveal the whole composer each time the insets move.
  @override
  void didChangeMetrics() {
    if (_replying) _revealComposer();
  }

  void _revealComposer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _composerKey.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _startReply() {
    setState(() {
      _replying = true;
      _draft = _controller.text.trim();
    });
    _revealComposer();
  }

  /// Posts the reply and, when [thenStatus] is set, flips the thread to
  /// it afterwards ("Reply & resolve"). The comment is the part that
  /// matters: if the status call fails the reply is kept and the failure
  /// is said out loud, rather than rolling anything back.
  Future<void> _send({String? thenStatus}) async {
    if (widget.onReply == null || _busy) return;
    // Every picked person becomes `@<guid>` here, at the submit boundary
    // (research/16 §4.3): the repository below takes a plain string.
    final text = _controller.toWire(MentionWire.markdown).trim();
    // A reply may be files alone (T3).
    if (text.isEmpty && pending.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    // Uploads first, then one Markdown line each on the end (T8). A
    // refusal keeps the text and the chips and posts nothing.
    final body = await bodyWithAttachments(text);
    if (body == null || body.isEmpty || !mounted) return;
    final posted = await widget.onReply!(body);
    if (!mounted) return;
    if (posted) {
      setState(() => _replying = false);
      _controller.clear();
      clearAttachments();
      // The keyboard goes with the reply (Kelly, 2026-09-14).
      FocusManager.instance.primaryFocus?.unfocus();
    }
    if (!posted || thenStatus == null) return;
    final changed = await widget.onSetStatus?.call(thenStatus) ?? false;
    if (!changed && mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Replied, but the thread could not be marked '
            '${PrThreadStatus.label(thenStatus).toLowerCase()}.',
          ),
        ),
      );
    }
  }

  /// Status the thread moves to when a reply is sent with the paired
  /// button: an open thread resolves, a settled one reopens.
  String get _pairedStatus =>
      widget.thread.isResolved ? PrThreadStatus.active : PrThreadStatus.fixed;

  String get _pairedLabel =>
      widget.thread.isResolved ? 'Reply & reactivate' : 'Reply & resolve';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final t = widget.thread;
    final resolved = t.isResolved;
    final statusColor = resolved ? colors.voteApproved : scheme.primary;
    final moved = t.trackedFromLine != null && t.trackedFromLine != t.rightLine;
    final actions = widget.canAct && widget.onSetStatus != null;
    return Material(
      color: widget.color ?? scheme.surfaceContainerLow,
      borderRadius: Radii.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.xs,
          Spacing.xs,
          Spacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  resolved ? Icons.check_circle : Icons.chat_bubble_outline,
                  size: 16,
                  color: statusColor,
                ),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    '${PrThreadStatus.label(t.status)}'
                    '${moved ? ' · moved from line ${t.trackedFromLine}' : ''}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: statusColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (actions)
                  PopupMenuButton<String>(
                    tooltip: 'Thread status',
                    enabled: !widget.busy,
                    icon: const Icon(Icons.more_horiz, size: 20),
                    onSelected: (s) => widget.onSetStatus!(s),
                    itemBuilder: (context) => [
                      if (resolved)
                        const PopupMenuItem(
                          value: PrThreadStatus.active,
                          child: Text('Reactivate'),
                        )
                      else ...const [
                        PopupMenuItem(
                          value: PrThreadStatus.fixed,
                          child: Text('Resolve'),
                        ),
                        PopupMenuItem(
                          value: PrThreadStatus.wontFix,
                          child: Text("Won't fix"),
                        ),
                        PopupMenuItem(
                          value: PrThreadStatus.closed,
                          child: Text('Close'),
                        ),
                      ],
                    ],
                  )
                else
                  const SizedBox(height: 40),
              ],
            ),
            for (final c in t.comments) ...[
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Row(
                  children: [
                    IdentityAvatar(identity: c.identity, radius: 10),
                    const SizedBox(width: Spacing.xs),
                    Expanded(
                      child: Text(
                        c.author,
                        style: theme.textTheme.labelLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: Spacing.sm),
                      child: Text(
                        relativeTime(c.publishedDate),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: 28,
                  right: Spacing.sm,
                  top: 2,
                  bottom: Spacing.xs,
                ),
                child: MentionMarkdown(
                  data: c.content,
                  names: widget.mentionNames,
                  onOpen: widget.onOpenMention,
                  attachments: widget.attachments,
                ),
              ),
              if (c.suggestion != null &&
                  widget.canAct &&
                  widget.onApplySuggestion != null &&
                  !t.isResolved)
                Padding(
                  padding: const EdgeInsets.only(left: 28, bottom: Spacing.xs),
                  child: FilledButton.tonalIcon(
                    onPressed: widget.busy
                        ? null
                        : () => widget.onApplySuggestion!(c, c.suggestion!),
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('Apply suggestion'),
                  ),
                ),
            ],
            if (widget.canAct && widget.onReply != null)
              if (_replying)
                Padding(
                  key: _composerKey,
                  padding: const EdgeInsets.only(
                    left: 28,
                    right: Spacing.sm,
                    top: Spacing.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MentionField(
                        controller: _controller,
                        source: widget.mentions,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 5,
                        enabled: !_busy,
                        contentInsertionConfiguration: contentInsertion,
                        onChanged: (v) {
                          final draft = v.trim();
                          // Only the empty/non-empty flip changes the row.
                          if (draft.isEmpty != _draft.isEmpty) {
                            setState(() => _draft = draft);
                            // The button row grows by one: keep it clear
                            // of the keyboard.
                            _revealComposer();
                          } else {
                            _draft = draft;
                          }
                        },
                        decoration: const InputDecoration(
                          hintText: 'Reply (Markdown)',
                          isDense: true,
                        ),
                      ),
                      MentionHint(controller: _controller),
                      attachmentsBar(busy: _busy),
                      const SizedBox(height: Spacing.xs),
                      // Empty box: the only sensible action is the status
                      // change, so nothing typed can be lost. With text —
                      // or with a file attached — the paired button posts
                      // and then flips the status.
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: Spacing.xs,
                        runSpacing: Spacing.xs,
                        children: [
                          // At the start of the row, so it does not compete
                          // with the two text actions (a2 §3.1).
                          if (canAttach) attachButton(busy: _busy),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _replying = false;
                                    // Cancelling leaves nothing behind:
                                    // nothing was uploaded (T3).
                                    pending.clear();
                                    attachmentError = null;
                                  }),
                            child: const Text('Cancel'),
                          ),
                          if (_draft.isEmpty && pending.isEmpty)
                            if (widget.onSetStatus != null)
                              FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => widget.onSetStatus!(_pairedStatus),
                                child: Text(
                                  widget.thread.isResolved
                                      ? 'Reactivate'
                                      : 'Resolve',
                                ),
                              )
                            else
                              const SizedBox.shrink()
                          else ...[
                            TextButton(
                              onPressed: _busy ? null : () => _send(),
                              // Azure DevOps reopens a settled thread as
                              // soon as a comment lands on it, whatever
                              // the app asks (spike note, 2026-09-12), so
                              // the plain Reply says what it will do.
                              child: Text(
                                _busy
                                    ? 'Posting…'
                                    : (t.isResolved
                                          ? 'Reply (reopens)'
                                          : 'Reply'),
                              ),
                            ),
                            if (widget.onSetStatus != null)
                              FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => _send(thenStatus: _pairedStatus),
                                child: Text(_pairedLabel),
                              ),
                          ],
                        ],
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: widget.busy ? null : _startReply,
                        icon: const Icon(Icons.reply, size: 18),
                        label: const Text('Reply'),
                      ),
                      if (widget.onSetStatus != null && !t.isResolved)
                        TextButton.icon(
                          onPressed: widget.busy
                              ? null
                              : () => widget.onSetStatus!(PrThreadStatus.fixed),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: const Text('Resolve'),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
