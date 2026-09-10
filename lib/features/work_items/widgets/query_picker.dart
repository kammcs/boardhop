import 'package:flutter/material.dart';

import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';

/// Bottom sheet listing the project's saved queries grouped by folder.
Future<SavedQuery?> pickSavedQuery(
  BuildContext context, {
  required List<SavedQuery> tree,
  String? selectedId,
}) {
  final leaves = [for (final root in tree) ...root.leaves];
  final byFolder = <String, List<SavedQuery>>{};
  for (final q in leaves) {
    byFolder.putIfAbsent(q.folder, () => []).add(q);
  }
  return showModalBottomSheet<SavedQuery>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  0,
                  Spacing.lg,
                  Spacing.sm,
                ),
                child: Text('Saved queries', style: theme.textTheme.titleMedium),
              ),
              if (leaves.isEmpty)
                const ListTile(
                  title: Text('No saved queries in the first two levels.'),
                ),
              for (final entry in byFolder.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    Spacing.sm,
                    Spacing.lg,
                    Spacing.xs,
                  ),
                  child: Text(
                    entry.key.isEmpty ? 'Queries' : entry.key,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final q in entry.value)
                  ListTile(
                    leading: const Icon(Icons.manage_search_outlined),
                    title: Text(q.name),
                    trailing: q.id == selectedId ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.of(context).pop(q),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
