import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../data/models/work_item.dart';
import '../../../../theme/theme.dart';
import '../../widgets/work_item_visuals.dart';
import '../work_item_form_state.dart';

/// The work item link types the form knows by name, in the order the Links
/// page lists them.
///
/// Azure DevOps also publishes them through `wit/workitemrelationtypes`
/// (research/01 §2.6), but the names are stable, the list costs a call and
/// the page must work from the cache, so the mapping is local and anything
/// unknown falls into [LinkKind.other] under its raw `rel`.
enum LinkKind {
  parent(WorkItemRelation.parentRel, 'Parent', Icons.arrow_upward),
  child(
    WorkItemRelation.childRel,
    'Child',
    Icons.arrow_downward,
    plural: 'Children',
    multiple: true,
  ),
  related(
    WorkItemRelation.relatedRel,
    'Related',
    Icons.link,
    plural: 'Related',
    multiple: true,
  ),
  predecessor(
    WorkItemRelation.predecessorRel,
    'Predecessor',
    Icons.skip_previous_outlined,
    plural: 'Predecessors',
  ),
  successor(
    WorkItemRelation.successorRel,
    'Successor',
    Icons.skip_next_outlined,
    plural: 'Successors',
  ),
  duplicate(
    WorkItemRelation.duplicateRel,
    'Duplicate',
    Icons.copy_outlined,
    plural: 'Duplicates',
    addable: false,
  ),
  duplicateOf(
    WorkItemRelation.duplicateOfRel,
    'Duplicate of',
    Icons.copy_all_outlined,
  ),
  other('', 'Other', Icons.open_in_new, plural: 'Other');

  const LinkKind(
    this.rel,
    this.label,
    this.icon, {
    this.plural,
    this.multiple = false,
    this.addable = true,
  });

  /// The relation's reference name; empty for [other].
  final String rel;

  /// Singular label, and what the "Add link" picker offers.
  final String label;

  /// The section heading when the item has more than one of this kind;
  /// [label] when the type carries no plural of its own.
  final String? plural;

  final IconData icon;

  /// An item may hold several of these, so the picker multi-selects.
  final bool multiple;

  /// Offered by the "Add link" picker (research/11 §4.3). "Duplicate" is
  /// not: the pair is added from its "Duplicate of" end.
  final bool addable;

  /// The section heading.
  String get heading => plural ?? label;

  static LinkKind of(String rel) {
    for (final kind in values) {
      if (kind != other && kind.rel == rel) return kind;
    }
    return other;
  }

  /// The kinds the picker offers, in its own order.
  static List<LinkKind> get addableKinds => [
    for (final kind in values)
      if (kind != other && kind.addable) kind,
  ];
}

/// One heading of the Links page and the relations under it.
@immutable
class LinkGroup {
  const LinkGroup({required this.kind, required this.relations});

  final LinkKind kind;
  final List<WorkItemRelation> relations;
}

/// Groups a work item's links by kind, in [LinkKind] order, keeping the
/// wire order inside each group. Only links to other work items are
/// listed: an attachment belongs on the Attachments page and a Git or
/// build artifact is Azure DevOps's own (the "Development" group).
List<LinkGroup> groupLinkRelations(Iterable<WorkItemRelation> relations) {
  final byKind = <LinkKind, List<WorkItemRelation>>{};
  for (final relation in relations) {
    if (!relation.isWorkItemLink) continue;
    byKind.putIfAbsent(LinkKind.of(relation.rel), () => []).add(relation);
  }
  return [
    for (final kind in LinkKind.values)
      if (byKind[kind] != null) LinkGroup(kind: kind, relations: byKind[kind]!),
  ];
}

/// What the Links page needs, kept apart from the repositories so the
/// section can be built in a widget test.
class LinkSource {
  const LinkSource({
    required this.resolve,
    required this.search,
    required this.open,
    this.visuals = const WorkItemVisuals({}),
  });

  /// Titles and states for the ids the relations point at, through one
  /// `WorkItemRepository.batch`. An id it cannot resolve is simply absent.
  final Future<List<WorkItem>> Function(List<int> ids) resolve;

  /// Link targets: an exact id, or a title search
  /// (`WorkItemFormRepository.searchWorkItems`).
  final Future<List<WorkItem>> Function(String text) search;

  /// Opens one item.
  final void Function(int id) open;

  /// Type icons and state colors for the rows.
  final WorkItemVisuals visuals;
}

/// The Links panel: the item's links grouped by kind, each row resolved to
/// its title and state, with an "Add link" button and a per-row remove.
///
/// On a new item the links are pending and ride in the create patch (spike
/// w16); on an existing one they become `add`/`remove` relation ops on Save
/// (research/01 §2.6).
class LinksSection extends StatefulWidget {
  const LinksSection({
    super.key,
    required this.state,
    this.source,
    this.enabled = true,
  });

  final WorkItemFormState state;
  final LinkSource? source;
  final bool enabled;

  @override
  State<LinksSection> createState() => _LinksSectionState();
}

class _LinksSectionState extends State<LinksSection> {
  /// Resolved targets by id, so a removal and a re-render do not re-read.
  final _resolved = <int, WorkItem>{};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    setState(() {});
    _resolve();
  }

  Future<void> _resolve() async {
    final source = widget.source;
    if (source == null || _loading) return;
    final missing = <int>[
      for (final relation in widget.state.linkRelations)
        if (relation.targetId != null &&
            !_resolved.containsKey(relation.targetId))
          relation.targetId!,
    ];
    if (missing.isEmpty) return;
    setState(() => _loading = true);
    try {
      final items = await source.resolve(missing.toSet().toList());
      if (!mounted) return;
      setState(() {
        for (final item in items) {
          _resolved[item.id] = item;
        }
      });
    } catch (_) {
      // An unresolvable target still shows as its id.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final source = widget.source;
    if (source == null) return;
    final picked = await showAddLinkSheet(context, source: source);
    if (picked == null || !mounted) return;
    for (final item in picked.items) {
      final url = item.url;
      if (url == null || url.isEmpty) continue;
      widget.state.addRelation(
        WorkItemRelation(rel: picked.kind.rel, url: url),
      );
      _resolved[item.id] = item;
    }
    await _resolve();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final groups = groupLinkRelations(widget.state.linkRelations);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Text(
              'No links yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text(
              group.relations.length > 1
                  ? '${group.kind.heading} (${group.relations.length})'
                  : group.kind.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final relation in group.relations)
            LinkRow(
              key: ValueKey(relation.key),
              relation: relation,
              kind: group.kind,
              target: _resolved[relation.targetId],
              visuals: widget.source?.visuals ?? const WorkItemVisuals({}),
              onOpen: widget.source == null || relation.targetId == null
                  ? null
                  : () => widget.source!.open(relation.targetId!),
              onRemove: widget.enabled
                  ? () => widget.state.removeRelation(relation)
                  : null,
            ),
        ],
        if (_loading) const LinearProgressIndicator(),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: OutlinedButton.icon(
              onPressed: widget.enabled && widget.source != null ? _add : null,
              icon: const Icon(Icons.add_link),
              label: const Text('Add link'),
            ),
          ),
        ),
      ],
    );
  }
}

/// One link: the target's type icon, id, title and state, opening the item
/// on tap and removable by a swipe or the trailing menu.
class LinkRow extends StatelessWidget {
  const LinkRow({
    super.key,
    required this.relation,
    required this.kind,
    required this.target,
    required this.visuals,
    this.onOpen,
    this.onRemove,
  });

  final WorkItemRelation relation;
  final LinkKind kind;

  /// The resolved item, or null while the batch read is out or when the
  /// target cannot be read (the row then shows the bare id).
  final WorkItem? target;

  final WorkItemVisuals visuals;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = target;
    final id = relation.targetId;
    final row = InkWell(
      onTap: onOpen,
      borderRadius: Radii.chip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Row(
          children: [
            Icon(
              item == null ? kind.icon : visuals.typeIcon(item),
              size: 18,
              color: item == null
                  ? scheme.onSurfaceVariant
                  : visuals.typeColor(context, item),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item == null
                        ? '#${id ?? '?'}'
                        : '#${item.id} ${item.title}',
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item != null)
                    Row(
                      children: [
                        StateDot(
                          color: visuals.stateColor(context, item),
                          size: 8,
                        ),
                        const SizedBox(width: Spacing.xs),
                        Flexible(
                          child: Text(
                            '${item.type} · ${item.state}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove link',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
    if (onRemove == null) return row;
    return Dismissible(
      key: ValueKey('dismiss:${relation.key}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove!(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Spacing.md),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      child: row,
    );
  }
}

/// What the "Add link" sheet answers with.
@immutable
class AddLinkResult {
  const AddLinkResult({required this.kind, required this.items});

  final LinkKind kind;
  final List<WorkItem> items;
}

/// The "Add link" flow: the kind, then the target by id or title search. A
/// sheet on a phone, a centered dialog from medium up (research/11 §4.5).
Future<AddLinkResult?> showAddLinkSheet(
  BuildContext context, {
  required LinkSource source,
}) {
  const sheet = _AddLinkSheet();
  if (!context.breakpoint.isCompact) {
    return showDialog<AddLinkResult>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _AddLinkScope(source: source, child: sheet),
        ),
      ),
    );
  }
  return showModalBottomSheet<AddLinkResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _AddLinkScope(source: source, child: sheet),
  );
}

class _AddLinkScope extends InheritedWidget {
  const _AddLinkScope({required this.source, required super.child});

  final LinkSource source;

  static LinkSource of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AddLinkScope>()!.source;

  @override
  bool updateShouldNotify(_AddLinkScope old) => old.source != source;
}

class _AddLinkSheet extends StatefulWidget {
  const _AddLinkSheet();

  @override
  State<_AddLinkSheet> createState() => _AddLinkSheetState();
}

class _AddLinkSheetState extends State<_AddLinkSheet> {
  final _query = TextEditingController();
  LinkKind _kind = LinkKind.related;
  final _picked = <int, WorkItem>{};
  List<WorkItem> _results = const [];
  bool _searching = false;
  String? _error;
  int _search = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final text = _query.text.trim();
    final token = ++_search;
    if (text.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final rows = await _AddLinkScope.of(context).search(text);
      if (!mounted || token != _search) return;
      setState(() => _results = rows);
    } catch (e) {
      if (mounted && token == _search) setState(() => _error = '$e');
    } finally {
      if (mounted && token == _search) setState(() => _searching = false);
    }
  }

  void _toggle(WorkItem item) {
    if (!_kind.multiple) {
      Navigator.of(context).pop(AddLinkResult(kind: _kind, items: [item]));
      return;
    }
    setState(() {
      if (_picked.remove(item.id) == null) _picked[item.id] = item;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final source = _AddLinkScope.of(context);
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: math.min(620, height * 0.85),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.lg,
                Spacing.lg,
                Spacing.sm,
              ),
              child: Text('Add link', style: theme.textTheme.titleMedium),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Row(
                children: [
                  for (final kind in LinkKind.addableKinds) ...[
                    ChoiceChip(
                      label: Text(kind.label),
                      avatar: Icon(kind.icon, size: 16),
                      selected: _kind == kind,
                      onSelected: (_) => setState(() {
                        _kind = kind;
                        if (!kind.multiple) _picked.clear();
                      }),
                    ),
                    const SizedBox(width: Spacing.sm),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.lg,
                0,
              ),
              child: TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Id or words in the title',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => _run(),
                onSubmitted: (_) => _run(),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            if (_searching) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (_error != null)
                    ListTile(
                      leading: Icon(Icons.error_outline, color: scheme.error),
                      title: Text(_error!),
                    ),
                  if (_results.isEmpty && !_searching && _error == null)
                    Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: Text(
                        _query.text.trim().isEmpty
                            ? 'Type an id to link it, or words to search '
                                  'titles.'
                            : 'Nothing matches.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final item in _results)
                    _TargetTile(
                      item: item,
                      visuals: source.visuals,
                      selected: _picked.containsKey(item.id),
                      multiple: _kind.multiple,
                      onTap: () => _toggle(item),
                    ),
                ],
              ),
            ),
            if (_kind.multiple)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.sm,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: Spacing.sm),
                    FilledButton(
                      onPressed: _picked.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(
                              AddLinkResult(
                                kind: _kind,
                                items: _picked.values.toList(),
                              ),
                            ),
                      child: Text(
                        _picked.isEmpty
                            ? 'Add'
                            : 'Add ${_picked.length} ${_kind.label.toLowerCase()}',
                      ),
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

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.item,
    required this.visuals,
    required this.selected,
    required this.multiple,
    required this.onTap,
  });

  final WorkItem item;
  final WorkItemVisuals visuals;
  final bool selected;
  final bool multiple;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      leading: Icon(
        visuals.typeIcon(item),
        color: visuals.typeColor(context, item),
      ),
      title: Text(
        '#${item.id} ${item.title}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          StateDot(color: visuals.stateColor(context, item), size: 8),
          const SizedBox(width: Spacing.xs),
          Flexible(
            child: Text(
              '${item.type} · ${item.state}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: multiple
          ? Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            )
          : null,
      onTap: onTap,
    );
  }
}
