import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/text/wiki_link.dart';
import '../../../data/models/wiki.dart';
import '../../../theme/theme.dart';
import '../../shared/mention/mention_controller.dart';
import '../wiki_page_source.dart';
import 'wiki_picker_sheet.dart';
import 'wiki_tree_view.dart';

/// The composer's wiki-page picker (K12): the book button beside attach
/// opens this, and what it answers is inserted at the caret as
/// `[Page title](url)`.
///
/// A sheet three quarters of the screen high on a phone and a dialog from
/// medium up, the shape every other picker in the app takes. Inside: the
/// wiki switcher when the project has more than one, a field that filters
/// titles over the tree already cached, and otherwise the same expandable
/// rows the Wiki view draws ([WikiTreeTile]).
Future<WikiPageLink?> showWikiPagePicker(
  BuildContext context, {
  required WikiPageSource source,
}) {
  final body = WikiPagePickerSheet(source: source);
  if (!context.breakpoint.isCompact) {
    return showBoardhopDialog<WikiPageLink>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          // Three quarters of the screen, but never the 1,032 pt an iPad
          // would give it: a dialog that tall is mostly empty box on a wiki
          // of a dozen pages (seen on the iPad, 2026-09-15). The form's own
          // Add link dialog caps itself the same way.
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: math.min(620, MediaQuery.sizeOf(context).height * 0.75),
          ),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<WikiPageLink>(
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

/// The URL a picked node is linked by: the id form when the tree carried an
/// id (what the web's *Copy page URL* writes), the path form when it did
/// not. A code wiki's branch rides along, because its pages only resolve on
/// the version they were published from (K8).
String wikiPageLinkUrl({
  required String org,
  required String project,
  required Wiki wiki,
  required WikiPageNode node,
}) {
  final id = node.id;
  if (id != null) {
    return WikiLink.webUrl(org, project, wiki.name, id, node.title);
  }
  return WikiLink.pageUrl(
    org,
    project,
    wiki.name.isEmpty ? wiki.id : wiki.name,
    node.path,
    version: wiki.isProjectWiki ? null : wiki.version,
  );
}

class WikiPagePickerSheet extends StatefulWidget {
  const WikiPagePickerSheet({super.key, required this.source});

  final WikiPageSource source;

  @override
  State<WikiPagePickerSheet> createState() => _WikiPagePickerSheetState();
}

class _WikiPagePickerSheetState extends State<WikiPagePickerSheet> {
  final _query = TextEditingController();

  List<Wiki> _wikis = const [];
  Wiki? _wiki;
  WikiPageNode? _root;
  final _expanded = <String>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final wikis = await widget.source.wikis();
    if (!mounted) return;
    if (wikis.isEmpty) {
      setState(() {
        _wikis = const [];
        _loading = false;
        _error = 'This project has no wiki.';
      });
      return;
    }
    setState(() => _wikis = wikis);
    await _openWiki(wikis.first);
  }

  Future<void> _openWiki(Wiki wiki) async {
    setState(() {
      _wiki = wiki;
      _root = null;
      _expanded.clear();
      _loading = true;
      _error = null;
    });
    final root = await widget.source.tree(wiki);
    if (!mounted) return;
    setState(() {
      _root = root;
      _loading = false;
      _error = root == null ? 'This wiki could not be read.' : null;
    });
  }

  Future<void> _switchWiki() async {
    final picked = await showWikiPicker(
      context,
      wikis: _wikis,
      currentId: _wiki?.id,
      projectName: widget.source.project,
    );
    if (picked == null || !mounted || picked.id == _wiki?.id) return;
    await _openWiki(picked);
  }

  void _pick(WikiPageNode node) {
    final wiki = _wiki;
    if (wiki == null || node.isNonConformant) return;
    Navigator.of(context).pop(
      WikiPageLink(
        title: node.title.isEmpty ? wiki.name : node.title,
        url: wikiPageLinkUrl(
          org: widget.source.org,
          project: widget.source.project,
          wiki: wiki,
          node: node,
        ),
      ),
    );
  }

  /// Every page whose title contains the typed text, in tree order. The
  /// match is over the title, not the path: a filter is for finding a page
  /// by name, and the path is what the row shows underneath.
  List<WikiPageNode> _matches(String query) {
    final root = _root;
    if (root == null) return const [];
    final needle = query.trim().toLowerCase();
    return [
      for (final node in root.flatten())
        if (!node.isRoot && node.title.toLowerCase().contains(needle)) node,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wiki = _wiki;
    final query = _query.text.trim();
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.lg,
                Spacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Link a wiki page',
                          style: theme.textTheme.titleMedium,
                        ),
                        if (wiki != null)
                          Text(
                            '${wiki.name} · ${wikiSubtitle(wiki)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Only where there is something to switch to (K1).
                  if (_wikis.length > 1)
                    TextButton.icon(
                      onPressed: _switchWiki,
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Wiki'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, 0),
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filter pages',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(_query.clear),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) WikiNotice(message: _error!),
            Flexible(child: _rows(query)),
          ],
        ),
      ),
    );
  }

  Widget _rows(String query) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final root = _root;
    if (root == null) return const SizedBox.shrink();
    if (query.isNotEmpty) {
      final matches = _matches(query);
      if (matches.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Text(
            'No page matches "$query".',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        );
      }
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          for (final node in matches)
            ListTile(
              dense: true,
              enabled: !node.isNonConformant,
              leading: Icon(
                Icons.description_outlined,
                color: scheme.onSurfaceVariant,
              ),
              title: Text(
                node.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                node.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              onTap: node.isNonConformant ? null : () => _pick(node),
            ),
        ],
      );
    }
    final rows = visibleWikiRows(root, _expanded);
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return WikiTreeTile(
          row: row,
          expanded: _expanded.contains(row.node.path),
          selected: false,
          onTap: () => _pick(row.node),
          onToggle: () => setState(() {
            if (!_expanded.remove(row.node.path)) _expanded.add(row.node.path);
          }),
        );
      },
    );
  }
}

/// The book button beside a composer's attach button (K12).
///
/// Drawn only where the host passed a [WikiPageSource]; what the picker
/// answers goes in at the caret as plain Markdown, so `MentionController`
/// leaves it alone, and the field takes the focus back.
class WikiPageButton extends StatelessWidget {
  const WikiPageButton({
    super.key,
    required this.source,
    required this.controller,
    this.focusNode,
    this.enabled = true,
  });

  final WikiPageSource source;
  final MentionController controller;

  /// The field to give the focus back to once a page is picked. Null leaves
  /// the caret where it was without re-opening the keyboard.
  final FocusNode? focusNode;

  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final picked = await showWikiPagePicker(context, source: source);
    if (picked == null) return;
    controller.insertPlain(picked.markdown);
    focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Link a wiki page',
    icon: const Icon(Icons.menu_book_outlined),
    onPressed: enabled ? () => _pick(context) : null,
  );
}
