import 'package:flutter/material.dart';

import '../../../../data/models/dashboard.dart';
import '../../../shared/mention/mention_markdown.dart';
import '../dashboard_card.dart';

/// Markdown: the widget's settings string rendered as Markdown.
///
/// The settings of this widget are the markdown itself, not JSON (w36
/// wrote one and read it back byte-for-byte), so there is nothing to fetch
/// and the card is stateless apart from the More toggle. Long text is
/// clamped to about twelve lines with a More that expands in place, so one
/// verbose widget cannot own the whole dashboard.
///
/// The **repo-file variant** — settings that are a JSON object naming a
/// repository, branch and path — is hidden for now (it needs a file read
/// per card); [MarkdownSettings.isFile] is how the registry spots it.
class MarkdownCard extends StatefulWidget {
  const MarkdownCard({super.key, required this.args, required this.settings});

  final DashboardCardArgs args;
  final MarkdownSettings settings;

  @override
  State<MarkdownCard> createState() => _MarkdownCardState();
}

class _MarkdownCardState extends State<MarkdownCard> {
  /// Roughly twelve lines of body text; the card grows with the text scale
  /// because the box does, not because the clamp does.
  static const _clampedHeight = 220.0;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final content = widget.settings.content.trim();
    final body = MentionMarkdown(data: content, selectable: false);
    return DashboardCard(
      title: widget.args.widget.name.isNotEmpty
          ? widget.args.widget.name
          : 'Markdown',
      icon: Icons.notes_outlined,
      filled: widget.args.filled,
      // More means *more*: the page's per-kind cap comes off once the
      // person has asked for the rest of the text.
      maxBodyHeight: _expanded ? null : widget.args.maxBodyHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_expanded || widget.args.filled)
            body
          else
            DashboardCard.clipToHeight(body, _clampedHeight),
          if (!_expanded && !widget.args.filled && content.length > 320)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _expanded = true),
                child: const Text('More'),
              ),
            ),
        ],
      ),
    );
  }
}

/// The empty-settings case: a Markdown widget with nothing in it is still
/// a widget the person put there, so it draws its name and says so rather
/// than vanishing into the hidden count.
class EmptyMarkdownCard extends StatelessWidget {
  const EmptyMarkdownCard({super.key, required this.args});

  final DashboardCardArgs args;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DashboardCard(
      title: args.widget.name.isNotEmpty ? args.widget.name : 'Markdown',
      icon: Icons.notes_outlined,
      filled: args.filled,
      maxBodyHeight: args.maxBodyHeight,
      child: Text(
        'This widget has no text.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
