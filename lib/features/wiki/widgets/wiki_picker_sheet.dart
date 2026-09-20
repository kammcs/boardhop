import 'package:flutter/material.dart';

import '../../../data/models/wiki.dart';
import '../../../theme/theme.dart';

/// The wiki picker: the project wiki first, then its code wikis, the one on
/// screen checked (K1, K8).
///
/// A bottom sheet on a phone and a dialog from medium up, like the dashboard
/// and sprint pickers. It is only ever opened when the project has more than
/// one wiki — with one there is nothing to pick and the title is not a
/// button.
Future<Wiki?> showWikiPicker(
  BuildContext context, {
  required List<Wiki> wikis,
  String? currentId,
  String? projectName,
}) {
  final body = WikiPickerSheet(
    wikis: wikis,
    currentId: currentId,
    projectName: projectName,
  );
  if (!context.breakpoint.isCompact) {
    return showBoardhopDialog<Wiki>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<Wiki>(
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

class WikiPickerSheet extends StatelessWidget {
  const WikiPickerSheet({
    super.key,
    required this.wikis,
    this.currentId,
    this.projectName,
  });

  final List<Wiki> wikis;
  final String? currentId;
  final String? projectName;

  /// The project wiki first, then the code wikis by name — the order
  /// `WikiRepository.wikis` already answers in, repeated here so a
  /// hand-assembled list (the probe, a test) reads the same.
  List<Wiki> get _sorted {
    final sorted = [...wikis];
    sorted.sort((a, b) {
      if (a.isProjectWiki != b.isProjectWiki) return a.isProjectWiki ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

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
                Text('Wikis', style: theme.textTheme.titleMedium),
                if ((projectName ?? '').isNotEmpty)
                  Text(
                    projectName!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final wiki in _sorted)
            ListTile(
              leading: Icon(
                wiki.isProjectWiki
                    ? Icons.menu_book_outlined
                    : Icons.folder_copy_outlined,
                color: scheme.onSurfaceVariant,
              ),
              title: Text(wiki.name),
              subtitle: Text(wikiSubtitle(wiki)),
              trailing: wiki.id == currentId ? const Icon(Icons.check) : null,
              selected: wiki.id == currentId,
              onTap: () => Navigator.of(context).pop(wiki),
            ),
        ],
      ),
    );
  }
}

/// The second line a wiki is described by, in the picker and under the tree
/// page's title: "Project wiki", or "Code wiki · branch" (K8).
///
/// [version] is the branch being read, which the tree page passes so the
/// line follows the branch pill instead of always naming the first
/// published version.
String wikiSubtitle(Wiki wiki, {String? version}) => wiki.isProjectWiki
    ? 'Project wiki'
    : 'Code wiki · ${version == null || version.isEmpty ? wiki.version : version}';
