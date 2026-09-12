import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../core/util/format.dart';
import '../../../data/repositories/pr_diff_source.dart';
import '../../../theme/theme.dart';
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

  @override
  State<ThreadCard> createState() => _ThreadCardState();
}

class _ThreadCardState extends State<ThreadCard> with WidgetsBindingObserver {
  final _controller = TextEditingController();

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
    final text = _controller.text.trim();
    if (text.isEmpty || widget.onReply == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final posted = await widget.onReply!(text);
    if (!mounted) return;
    if (posted) {
      setState(() => _replying = false);
      _controller.clear();
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
                child: MarkdownBody(data: c.content, selectable: true),
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
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 5,
                        enabled: !widget.busy,
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
                      const SizedBox(height: Spacing.xs),
                      // Empty box: the only sensible action is the status
                      // change, so nothing typed can be lost. With text,
                      // the paired button posts and then flips the status.
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: Spacing.xs,
                        runSpacing: Spacing.xs,
                        children: [
                          TextButton(
                            onPressed: widget.busy
                                ? null
                                : () => setState(() => _replying = false),
                            child: const Text('Cancel'),
                          ),
                          if (_draft.isEmpty)
                            if (widget.onSetStatus != null)
                              FilledButton(
                                onPressed: widget.busy
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
                              onPressed: widget.busy ? null : () => _send(),
                              child: Text(widget.busy ? 'Posting…' : 'Reply'),
                            ),
                            if (widget.onSetStatus != null)
                              FilledButton(
                                onPressed: widget.busy
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
