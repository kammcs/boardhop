import 'package:flutter/material.dart';

import '../../../data/models/wiki.dart';
import '../../../theme/theme.dart';
import 'search_highlight_text.dart';

/// One wiki search hit (research/20 K4): the page title, the wiki it lives
/// in — and the project when the search spans more than one — and the one
/// matched line the service highlighted.
///
/// A title match is the line the service sends back as `fileNames`, and it
/// reads as the title with the term in bold; a content match is a line out
/// of the page. Either way it is the same [SearchHighlightText] the work
/// item and code sections use, so a match looks alike wherever it is found.
class WikiHitTile extends StatelessWidget {
  const WikiHitTile({
    super.key,
    required this.hit,
    required this.onTap,
    this.showProject = false,
  });

  final WikiSearchHit hit;
  final VoidCallback onTap;

  /// True in the All-projects scope, where a row has to say where it is.
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final highlight = hit.highlight;
    final where = [
      if (showProject && hit.projectName.isNotEmpty) hit.projectName,
      if (hit.wikiName.isNotEmpty) hit.wikiName,
    ].join(' · ');
    return ListTile(
      isThreeLine: highlight != null,
      leading: Icon(Icons.menu_book_outlined, color: scheme.onSurfaceVariant),
      title: Text(
        hit.title.isEmpty ? hit.fileName : hit.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (where.isNotEmpty)
            Text(
              where,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          if (highlight != null) ...[
            const SizedBox(height: Spacing.xs),
            SearchHighlightText(highlight: highlight),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}
