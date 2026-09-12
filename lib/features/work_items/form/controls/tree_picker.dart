import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../data/models/work_item_form.dart';
import '../../../../theme/theme.dart';
import '../work_item_form_state.dart';
import 'form_field_slot.dart';

/// What the area and iteration trees need, kept apart from the repository so
/// the form body can be built in a test.
class ClassificationSource {
  const ClassificationSource({
    required this.nodes,
    this.teamIterations,
    this.currentIterationPath,
    this.backlogIterationPath,
  });

  /// The root node of the areas or the iterations, ten levels deep.
  final Future<ClassificationNode?> Function({required bool areas}) nodes;

  /// Every iteration of the team, for the picker's "Team" section (spike
  /// s30). Null in a test, which falls back to the two paths below.
  final Future<List<TeamIteration>> Function()? teamIterations;

  /// The team's sprint, marked in the list (spike s25).
  final String? currentIterationPath;

  /// `teamsettings.backlogIteration`, the fallback when there is no sprint.
  final String? backlogIterationPath;
}

Future<String?> pickClassificationPath(
  BuildContext context, {
  required String title,
  required ClassificationSource source,
  required bool areas,
  String? current,
}) {
  // A tablet gets the same tree in a centered dialog (research/11 §4.5).
  if (!context.breakpoint.isCompact) {
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _TreeSheet(
            title: title,
            source: source,
            areas: areas,
            current: current,
            dialog: true,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _TreeSheet(
      title: title,
      source: source,
      areas: areas,
      current: current,
    ),
  );
}

class _TreeSheet extends StatefulWidget {
  const _TreeSheet({
    required this.title,
    required this.source,
    required this.areas,
    this.current,
    this.dialog = false,
  });

  final String title;
  final ClassificationSource source;
  final bool areas;
  final String? current;

  /// Centered dialog rather than a bottom sheet.
  final bool dialog;

  @override
  State<_TreeSheet> createState() => _TreeSheetState();
}

class _TreeSheetState extends State<_TreeSheet> {
  final _query = TextEditingController();
  ClassificationNode? _root;
  List<TeamIteration> _iterations = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _loadIterations();
  }

  Future<void> _load() async {
    try {
      final root = await widget.source.nodes(areas: widget.areas);
      if (mounted) setState(() => _root = root);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The team's own iterations head the list; a failure just leaves the
  /// section on the current and backlog paths.
  Future<void> _loadIterations() async {
    final read = widget.source.teamIterations;
    if (widget.areas || read == null) return;
    try {
      final rows = await read();
      if (mounted) setState(() => _iterations = rows);
    } catch (_) {
      // The whole tree is still there.
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// The team's iterations in wire order, the current one marked; the
  /// backlog iteration follows when it is not one of them.
  List<({String path, String? badge})> get _teamPaths {
    if (widget.areas) return const [];
    final out = <({String path, String? badge})>[];
    final seen = <String>{};
    for (final iteration in _iterations) {
      if (iteration.path.isEmpty || !seen.add(iteration.path)) continue;
      out.add((
        path: iteration.path,
        badge: iteration.isCurrent ? 'Current' : null,
      ));
    }
    if (out.isEmpty) {
      final current = widget.source.currentIterationPath;
      if (current != null && seen.add(current)) {
        out.add((path: current, badge: 'Current'));
      }
    }
    final backlog = widget.source.backlogIterationPath;
    if (backlog != null && seen.add(backlog)) {
      out.add((path: backlog, badge: 'Backlog'));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = _query.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? const <ClassificationNode>[]
        : [
            for (final n in _root?.flattened ?? const <ClassificationNode>[])
              if (n.path.toLowerCase().contains(query)) n,
          ];
    final teamPaths = _teamPaths;
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
              child: Text(widget.title, style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: TextField(
                controller: _query,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Filter',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            if (_loading) const LinearProgressIndicator(),
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
                  if (query.isNotEmpty) ...[
                    for (final node in matches)
                      _PathTile(
                        path: node.path,
                        selected: node.path == widget.current,
                        onTap: () => Navigator.of(context).pop(node.path),
                      ),
                    if (matches.isEmpty && !_loading)
                      const Padding(
                        padding: EdgeInsets.all(Spacing.lg),
                        child: Text('Nothing matches.'),
                      ),
                  ] else ...[
                    if (teamPaths.isNotEmpty) ...[
                      _Caption(
                        text: 'Team',
                        style: theme.textTheme.labelMedium,
                        color: scheme.onSurfaceVariant,
                      ),
                      for (final row in teamPaths)
                        _PathTile(
                          path: row.path,
                          selected: row.path == widget.current,
                          badge: row.badge,
                          onTap: () => Navigator.of(context).pop(row.path),
                        ),
                      const Divider(height: 1),
                      _Caption(
                        text: widget.areas ? 'All areas' : 'All iterations',
                        style: theme.textTheme.labelMedium,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                    if (_root != null)
                      _NodeTile(
                        node: _root!,
                        current: widget.current,
                        currentIteration: widget.source.currentIterationPath,
                        onPick: (path) => Navigator.of(context).pop(path),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.text, this.style, this.color});

  final String text;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Spacing.lg,
      Spacing.md,
      Spacing.lg,
      Spacing.xs,
    ),
    child: Text(text, style: style?.copyWith(color: color)),
  );
}

class _PathTile extends StatelessWidget {
  const _PathTile({
    required this.path,
    required this.onTap,
    this.selected = false,
    this.badge,
  });

  final String path;
  final VoidCallback onTap;
  final bool selected;
  final String? badge;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(path, overflow: TextOverflow.ellipsis),
    // The badge and the tick sit together: the current iteration is
    // usually the one already picked.
    trailing: badge == null && !selected
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null)
                Chip(label: Text(badge!), visualDensity: VisualDensity.compact),
              if (selected) ...[
                const SizedBox(width: Spacing.sm),
                const Icon(Icons.check),
              ],
            ],
          ),
    onTap: onTap,
  );
}

/// One node of the tree; children are built when the node is expanded.
class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.node,
    required this.onPick,
    this.current,
    this.currentIteration,
    this.depth = 0,
  });

  final ClassificationNode node;
  final void Function(String path) onPick;
  final String? current;
  final String? currentIteration;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final selected = node.path == current;
    final marked = node.path == currentIteration;
    final title = Row(
      children: [
        Flexible(child: Text(node.name, overflow: TextOverflow.ellipsis)),
        if (marked) ...[
          const SizedBox(width: Spacing.sm),
          const Icon(Icons.play_circle_outline, size: 16),
        ],
        if (selected) ...[
          const SizedBox(width: Spacing.sm),
          const Icon(Icons.check, size: 16),
        ],
      ],
    );
    final padding = EdgeInsets.only(left: Spacing.lg + depth * Spacing.md);
    if (node.children.isEmpty) {
      return ListTile(
        dense: true,
        contentPadding: padding.add(const EdgeInsets.only(right: Spacing.lg)),
        title: title,
        onTap: () => onPick(node.path),
      );
    }
    return ExpansionTile(
      initiallyExpanded: depth == 0,
      tilePadding: padding.add(const EdgeInsets.only(right: Spacing.lg)),
      childrenPadding: EdgeInsets.zero,
      title: title,
      trailing: TextButton(
        onPressed: () => onPick(node.path),
        child: const Text('Pick'),
      ),
      children: [
        for (final child in node.children)
          _NodeTile(
            node: child,
            onPick: onPick,
            current: current,
            currentIteration: currentIteration,
            depth: depth + 1,
          ),
      ],
    );
  }
}

/// A `treePath` field inside a group card. Area and Iteration themselves sit
/// in the pinned header and open the same sheet.
class TreeControl extends StatelessWidget {
  const TreeControl({
    super.key,
    required this.state,
    required this.field,
    required this.label,
    required this.source,
    this.enabled = true,
  });

  final WorkItemFormState state;
  final FieldSpec field;
  final String label;
  final ClassificationSource? source;
  final bool enabled;

  bool get _areas => !field.referenceName.toLowerCase().contains('iteration');

  @override
  Widget build(BuildContext context) {
    final reference = field.referenceName;
    final value = state.value(reference) as String?;
    return FormFieldSlot(
      label: label,
      required: field.alwaysRequired,
      helpText: field.helpText,
      error: state.errorFor(reference),
      child: PickerTile(
        icon: Icons.account_tree_outlined,
        text: (value ?? '').isEmpty ? 'Not set' : value!,
        placeholder: (value ?? '').isEmpty,
        enabled: enabled && source != null,
        hasError: state.errorFor(reference) != null,
        onTap: () async {
          final picked = await pickClassificationPath(
            context,
            title: label,
            source: source!,
            areas: _areas,
            current: value,
          );
          if (picked == null) return;
          state.setValue(reference, picked);
        },
      ),
    );
  }
}
