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
    this.color,
  });

  final PrThread thread;

  /// False on completed or abandoned pull requests: read-only card.
  final bool canAct;
  final bool busy;
  final Future<void> Function(String text)? onReply;
  final Future<void> Function(String status)? onSetStatus;
  final Color? color;

  @override
  State<ThreadCard> createState() => _ThreadCardState();
}

class _ThreadCardState extends State<ThreadCard> {
  final _controller = TextEditingController();
  bool _replying = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.onReply == null) return;
    await widget.onReply!(text);
    if (mounted) {
      setState(() => _replying = false);
      _controller.clear();
    }
  }

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
            ],
            if (widget.canAct && widget.onReply != null)
              if (_replying)
                Padding(
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
                        decoration: const InputDecoration(
                          hintText: 'Reply (Markdown)',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: widget.busy
                                ? null
                                : () => setState(() => _replying = false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: Spacing.xs),
                          FilledButton(
                            onPressed: widget.busy ? null : _send,
                            child: Text(widget.busy ? 'Posting…' : 'Reply'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: TextButton.icon(
                    onPressed: widget.busy
                        ? null
                        : () => setState(() => _replying = true),
                    icon: const Icon(Icons.reply, size: 18),
                    label: const Text('Reply'),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
