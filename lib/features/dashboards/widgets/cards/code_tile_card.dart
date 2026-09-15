import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/models/dashboard.dart';
import '../../../../theme/theme.dart';
import '../../../../core/routes.dart';
import '../../../shared/account_scope.dart';
import '../dashboard_card.dart';

/// Code Tile: the repository and branch the widget points at, as a way in.
///
/// The web's tile also shows a commit count over a window; that needs a
/// commit read per card and is out of scope here (research/19 §6 keeps the
/// counts for later). Everything drawn comes from the widget's own
/// settings, so the card never fails and works offline.
class CodeTileCard extends StatelessWidget {
  const CodeTileCard({super.key, required this.args, required this.settings});

  final DashboardCardArgs args;
  final CodeTileSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = settings.repositoryName ?? '';
    final branch = (settings.branchName ?? '').replaceFirst('refs/heads/', '');
    // Inert outside the account shell (the diagnostics probe).
    final account = AccountScope.maybeOf(context);
    final base = account == null
        ? null
        : Routes.project(account, args.org, args.project);
    return DashboardCard(
      title: args.widget.name.isNotEmpty ? args.widget.name : 'Code',
      icon: Icons.source_outlined,
      filled: args.filled,
      maxBodyHeight: args.maxBodyHeight,
      onTap: name.isEmpty || base == null
          ? null
          : () => context.push('$base/repos/${Uri.encodeComponent(name)}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name.isEmpty ? 'Repository' : name,
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (branch.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.call_split,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Spacing.xs),
                  Flexible(
                    child: Text(
                      branch,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if ((settings.path ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.xs),
              child: Text(
                settings.path!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
