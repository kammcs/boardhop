import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../data/models/wiki.dart';
import '../../../theme/theme.dart';
import '../wiki_prefs.dart';

/// One drawn row of the tree: a node and how deep it sits.
///
/// The tree is hand-rolled rather than an `ExpansionTile` list because K2
/// asks for in-place expansion with the ancestors visible and the current
/// page highlighted, inside the page's one `CustomScrollView` — nested
/// `ExpansionTile`s would each own a scrollable of their own and lose the
/// sliver.
@immutable
class WikiTreeRow {
  const WikiTreeRow({required this.node, required this.depth});

  final WikiPageNode node;
  final int depth;
}

/// The rows to draw for [root] given the set of expanded paths.
///
/// Pure, so the expansion rules are testable without a widget tree: the
/// root itself is never drawn (it is the wiki), a child is drawn when every
/// ancestor above it is expanded, and the order is the model's — `.order`
/// first, then title (spike w37).
List<WikiTreeRow> visibleWikiRows(WikiPageNode? root, Set<String> expanded) {
  final rows = <WikiTreeRow>[];
  if (root == null) return rows;
  void walk(WikiPageNode node, int depth) {
    for (final child in node.subPages) {
      rows.add(WikiTreeRow(node: child, depth: depth));
      if (child.subPages.isNotEmpty && expanded.contains(child.path)) {
        walk(child, depth + 1);
      }
    }
  }

  walk(root, 0);
  return rows;
}

/// Every ancestor path of [path], so opening the tree on the page last read
/// shows it without a tap (K1).
Set<String> ancestorPathsOf(String? path) {
  if (path == null || path.isEmpty) return <String>{};
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  final out = <String>{};
  // The page itself is expanded too: a parent page that was open should
  // still show its children.
  for (var i = 1; i <= segments.length; i++) {
    out.add('/${segments.sublist(0, i).join('/')}');
  }
  return out;
}

/// One row of the tree.
class WikiTreeTile extends StatelessWidget {
  const WikiTreeTile({
    super.key,
    required this.row,
    required this.expanded,
    required this.selected,
    this.onTap,
    this.onToggle,
  });

  final WikiTreeRow row;
  final bool expanded;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  /// How far one level of nesting indents. The scratch wiki is four deep
  /// and the client wiki five, so a phone cannot afford much more.
  static const double indent = 20;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final node = row.node;
    // A file pushed into the wiki repository whose name the wiki cannot map
    // back to a page: it is listed, and it 404s by path *and* by id, so it
    // must not be tappable (research/20 §1).
    final blocked = node.isNonConformant;
    final color = blocked
        ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
        : selected
        ? scheme.onSurface
        : scheme.onSurface;
    return ListTile(
      dense: true,
      selected: selected,
      enabled: !blocked,
      contentPadding: EdgeInsets.fromLTRB(
        Spacing.md + row.depth * indent,
        0,
        Spacing.lg,
        0,
      ),
      leading: node.isParentPage && node.subPages.isNotEmpty
          ? IconButton(
              tooltip: expanded ? 'Collapse' : 'Expand',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                color: scheme.onSurfaceVariant,
              ),
              onPressed: blocked ? null : onToggle,
            )
          : const SizedBox(width: 40),
      title: Text(
        node.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: color,
          fontWeight: selected ? FontWeight.w600 : null,
        ),
      ),
      subtitle: blocked
          ? Text(
              'Not readable: the file name has a space',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          : null,
      onTap: blocked ? null : onTap,
    );
  }
}

/// The Recent strip above the tree (K1, K11): up to five pages, most recent
/// first, as chips that scroll sideways.
class WikiRecentsStrip extends StatelessWidget {
  const WikiRecentsStrip({super.key, required this.recents, this.onOpen});

  final List<WikiRecent> recents;
  final void Function(WikiRecent recent)? onOpen;

  @override
  Widget build(BuildContext context) {
    if (recents.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.md,
            Spacing.lg,
            Spacing.xs,
          ),
          child: Text(
            'Recent',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Row(
            children: [
              for (final recent in recents) ...[
                ActionChip(
                  avatar: Icon(
                    Icons.history,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  label: Text(
                    recent.title.isEmpty ? recent.path : recent.title,
                  ),
                  onPressed: onOpen == null ? null : () => onOpen!(recent),
                ),
                const SizedBox(width: Spacing.sm),
              ],
            ],
          ),
        ),
        const SizedBox(height: Spacing.xs),
        const Divider(height: 1),
      ],
    );
  }
}

/// "Updated 3m ago", or the offline form, over content that did not come
/// from this minute's network read (K7).
///
/// The Dashboards view's own line, repeated rather than shared: that one
/// lives beside the dashboard cards and this one has to be drawable by the
/// wiki probe with no dashboard in the import graph.
class WikiCacheLine extends StatelessWidget {
  const WikiCacheLine({super.key, this.shownAt, this.offline = false});

  final DateTime? shownAt;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final at = shownAt;
    if (at == null && !offline) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final age = at == null ? '' : ' · ${relativeTime(at)}';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg + MediaQuery.paddingOf(context).left,
        Spacing.xs,
        Spacing.lg + MediaQuery.paddingOf(context).right,
        0,
      ),
      child: Row(
        children: [
          Icon(
            offline ? Icons.cloud_off_outlined : Icons.history_toggle_off,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              offline
                  ? 'offline · showing the cached copy$age'
                  : at == null
                  ? 'Updated'
                  : 'Updated ${relativeTime(at)} ago',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An error or a refusal, inline over the content it concerns (DESIGN §7).
class WikiNotice extends StatelessWidget {
  const WikiNotice({
    super.key,
    required this.message,
    this.icon = Icons.error_outline,
    this.tone = WikiNoticeTone.error,
    this.onDismiss,
  });

  final String message;
  final IconData icon;
  final WikiNoticeTone tone;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (tone == WikiNoticeTone.quiet) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.md,
          Spacing.lg,
          0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Material(
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(icon, color: scheme.onErrorContainer),
        title: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
        trailing: onDismiss == null
            ? null
            : IconButton(
                tooltip: 'Dismiss',
                icon: Icon(Icons.close, color: scheme.onErrorContainer),
                onPressed: onDismiss,
              ),
      ),
    );
  }
}

enum WikiNoticeTone { error, quiet }

/// "This project has no wiki", with the one action there is (research/20
/// §4.2, DESIGN §7: one sentence and one action).
class WikiEmptyState extends StatelessWidget {
  const WikiEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xl,
        Spacing.lg,
        Spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 40,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: Spacing.sm),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: Spacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.open_in_new),
                label: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
