import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'wiki_markdown.dart';

/// The contents sheet (K9): the page's h1–h3 headings, indented by level,
/// answering the one that was tapped.
///
/// A bottom sheet on a phone and a dialog from medium up, the shape every
/// picker in the app uses.
Future<WikiHeading?> showWikiContents(
  BuildContext context, {
  required List<WikiHeading> headings,
  String? pageTitle,
}) {
  final body = WikiContentsSheet(headings: headings, pageTitle: pageTitle);
  if (!context.breakpoint.isCompact) {
    return showBoardhopDialog<WikiHeading>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<WikiHeading>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.75,
    ),
    builder: (context) => body,
  );
}

class WikiContentsSheet extends StatelessWidget {
  const WikiContentsSheet({super.key, required this.headings, this.pageTitle});

  final List<WikiHeading> headings;
  final String? pageTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Spacing.lg),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.lg,
              Spacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Contents', style: theme.textTheme.titleMedium),
                if ((pageTitle ?? '').isNotEmpty)
                  Text(
                    pageTitle!,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final heading in headings)
            ListTile(
              // Indent by level rather than a leading glyph: the level is
              // the only thing that distinguishes these rows, and a text
              // scale that doubles the row height must not double the
              // indent (DESIGN §4).
              contentPadding: EdgeInsets.fromLTRB(
                Spacing.lg + (heading.level - 1).clamp(0, 2) * Spacing.lg,
                0,
                Spacing.lg,
                0,
              ),
              title: Text(
                heading.text,
                style: heading.level == 1
                    ? theme.textTheme.bodyLarge
                    : theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
              ),
              onTap: () => Navigator.of(context).pop(heading),
            ),
          if (headings.isEmpty)
            Padding(
              padding: Spacing.page,
              child: Text(
                'This page has no headings.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
