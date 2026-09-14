import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/git_repository.dart';
import '../../../theme/theme.dart';
import '../../shared/account_scope.dart';
import 'item_actions.dart';

/// One code search hit: the file's glyph and name, then its folder, branch
/// and how it matched.
///
/// Drawn the same way by the Repos code search and by the search feature's
/// Code section (research/15 §4), so a hit looks alike wherever it is found.
class CodeHitTile extends StatelessWidget {
  const CodeHitTile({
    super.key,
    required this.hit,
    required this.onTap,
    this.showProject = false,
  });

  final CodeSearchHit hit;
  final VoidCallback onTap;

  /// Names the hit's project in the second line, for an org-wide search
  /// whose results come from more than one.
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      leading: Icon(
        itemIcon(GitItem(path: hit.path, isFolder: false)),
        color: scheme.onSurfaceVariant,
      ),
      title: Text(hit.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (showProject && hit.projectName.isNotEmpty) hit.projectName,
          hit.folder,
          if (hit.branch != null) hit.branch!,
          if (hit.contentMatches > 0)
            '${hit.contentMatches} match${hit.contentMatches == 1 ? '' : 'es'}',
          if (hit.fileNameMatches > 0) 'name matches',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// Opens the file a hit names at the branch it was found on, with [query]
/// carried as `find` so the viewer scrolls to the first matching line
/// (code search returns no snippets).
///
/// The hit's own project is used when it has one, so an All-projects search
/// opens the file inside its own project rather than the one being browsed.
void openCodeHit(
  BuildContext context, {
  required String org,
  required String project,
  required CodeSearchHit hit,
  required String query,
}) {
  final owner = hit.projectName.isEmpty ? project : hit.projectName;
  final base =
      '${projectRoute(context, org, owner)}'
      '/repos/${Uri.encodeComponent(hit.repositoryName)}';
  final params = <String, String>{
    if (hit.branch != null) 'ref': hit.branch!,
    'path': hit.path,
    'find': query,
  };
  final encoded = params.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  context.push('$base/file?$encoded');
}

/// The hits as rows, with a header per repository when more than one
/// repository can appear (a project- or org-wide search); a search already
/// narrowed to one repository gets a plain list.
List<Widget> codeHitRows({
  required List<CodeSearchHit> hits,
  required void Function(CodeSearchHit hit) onTap,
  required BuildContext context,
  bool grouped = true,
  bool showProject = false,
}) {
  final theme = Theme.of(context);
  final byRepository = <String, List<CodeSearchHit>>{};
  for (final hit in hits) {
    byRepository.putIfAbsent(hit.repositoryName, () => []).add(hit);
  }
  final rows = <Widget>[];
  for (final entry in byRepository.entries) {
    if (grouped) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.lg,
            Spacing.lg,
            Spacing.xs,
          ),
          child: Text(
            '${entry.key} · ${entry.value.length}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }
    for (final hit in entry.value) {
      rows.add(
        CodeHitTile(
          hit: hit,
          showProject: showProject,
          onTap: () => onTap(hit),
        ),
      );
    }
  }
  return rows;
}
