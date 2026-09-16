import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import '../../shared/mention/mention_source.dart';
import '../../work_items/widgets/work_item_visuals.dart';

/// Picks a work item id to link to the pull request.
///
/// The rows come from the same `#` band the composers use
/// (`MentionSources.workItemMatches`): the project's cached lists first,
/// then the work item search API from three characters on. Reusing it means
/// the link picker is as good offline as the mention picker is, and there is
/// one place where "which work items can I name here" is decided (M8).
Future<int?> pickWorkItemToLink(
  BuildContext context, {
  required Future<List<ArtifactSuggestion>> Function(String query) search,
  Set<int> linked = const {},
}) {
  if (!context.breakpoint.isCompact) {
    return showDialog<int>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _WorkItemLinkSheet(
            search: search,
            linked: linked,
            dialog: true,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _WorkItemLinkSheet(search: search, linked: linked),
  );
}

class _WorkItemLinkSheet extends StatefulWidget {
  const _WorkItemLinkSheet({
    required this.search,
    required this.linked,
    this.dialog = false,
  });

  final Future<List<ArtifactSuggestion>> Function(String query) search;
  final Set<int> linked;
  final bool dialog;

  @override
  State<_WorkItemLinkSheet> createState() => _WorkItemLinkSheetState();
}

class _WorkItemLinkSheetState extends State<_WorkItemLinkSheet> {
  static const _debounceFor = Duration(milliseconds: 300);

  final _query = TextEditingController();
  Timer? _debounce;
  List<ArtifactSuggestion> _hits = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  void _onQuery(String text) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(_debounceFor, () => _run(text.trim()));
  }

  Future<void> _run(String query) async {
    setState(() => _searching = true);
    try {
      final hits = await widget.search(query);
      if (mounted && _query.text.trim() == query) setState(() => _hits = hits);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final shown = [
      for (final h in _hits)
        if (!widget.linked.contains(int.tryParse(h.id) ?? -1)) h,
    ];
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: widget.dialog ? math.min(560, height * 0.8) : height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                Spacing.lg,
                widget.dialog ? Spacing.lg : 0,
                Spacing.lg,
                Spacing.sm,
              ),
              child: Text(
                'Link a work item',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search by id or title',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(Spacing.md),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: _onQuery,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (shown.isEmpty && !_searching)
                    Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: Text(
                        'No work item matches.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final h in shown)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        WorkItemType.iconFor(
                          WorkItemVisuals.guessIcon(h.typeName ?? ''),
                        ),
                        color: colors.workItemType(h.typeName ?? ''),
                      ),
                      title: Text(
                        h.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          if ((h.typeName ?? '').isNotEmpty) h.typeName!,
                          '#${h.id}',
                          if ((h.state ?? '').isNotEmpty) h.state!,
                        ].join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () {
                        final id = int.tryParse(h.id);
                        if (id != null) Navigator.of(context).pop(id);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
