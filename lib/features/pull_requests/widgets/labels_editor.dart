import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/http/ado_exceptions.dart';
import '../../../data/models/pull_request.dart';
import '../../../theme/theme.dart';

/// The Overview's label chips, with a pencil that opens the editor (R14).
class LabelsSection extends StatelessWidget {
  const LabelsSection({
    super.key,
    required this.labels,
    required this.onEdit,
    this.canEdit = true,
    this.busy = false,
  });

  final List<PrLabel> labels;
  final VoidCallback onEdit;
  final bool canEdit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (labels.isEmpty && !canEdit) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.lg,
            Spacing.sm,
            Spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Labels (${labels.length})',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (canEdit)
                IconButton(
                  tooltip: 'Edit labels',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: busy ? null : onEdit,
                ),
            ],
          ),
        ),
        Padding(
          padding: Spacing.pageHorizontal,
          child: labels.isEmpty
              ? Text(
                  'No labels.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    for (final l in labels)
                      Chip(
                        avatar: const Icon(Icons.label_outline, size: 16),
                        label: Text(l.name),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Free text with the project's tag pool as suggestions, chips with × to
/// remove (R14). Labels share `wit/tags`, so the suggestions are the same
/// pool a work item's tags come from (research/22 §1).
///
/// Answers with the list the user settled on; the caller diffs it against
/// what the pull request had and sends one `POST` or `DELETE` per change.
/// Null means they backed out.
Future<List<String>?> showLabelsEditor(
  BuildContext context, {
  required List<String> current,
  required Future<List<String>> Function() suggestions,
}) {
  if (!context.breakpoint.isCompact) {
    return showDialog<List<String>>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _LabelsSheet(
            current: current,
            suggestions: suggestions,
            dialog: true,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) =>
        _LabelsSheet(current: current, suggestions: suggestions),
  );
}

class _LabelsSheet extends StatefulWidget {
  const _LabelsSheet({
    required this.current,
    required this.suggestions,
    this.dialog = false,
  });

  final List<String> current;
  final Future<List<String>> Function() suggestions;
  final bool dialog;

  @override
  State<_LabelsSheet> createState() => _LabelsSheetState();
}

class _LabelsSheetState extends State<_LabelsSheet> {
  final _input = TextEditingController();
  late final List<String> _labels = [...widget.current];
  List<String> _all = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.suggestions();
      if (mounted) setState(() => _all = all);
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _add(String raw) {
    final label = raw.trim();
    if (label.isEmpty) return;
    final exists = _labels.any((l) => l.toLowerCase() == label.toLowerCase());
    setState(() {
      if (!exists) _labels.add(label);
      _input.clear();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = _input.text.trim().toLowerCase();
    final chosen = {for (final l in _labels) l.toLowerCase()};
    final suggestions = [
      for (final tag in _all)
        if (!chosen.contains(tag.toLowerCase()) &&
            (query.isEmpty || tag.toLowerCase().contains(query)))
          tag,
    ];
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: widget.dialog ? math.min(560, height * 0.8) : height * 0.7,
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
              child: Row(
                children: [
                  Expanded(
                    child: Text('Labels', style: theme.textTheme.titleMedium),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_labels),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: TextField(
                controller: _input,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Add a label',
                  prefixIcon: const Icon(Icons.label_outline),
                  suffixIcon: IconButton(
                    tooltip: 'Add label',
                    icon: const Icon(Icons.add),
                    onPressed: () => _add(_input.text),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: _add,
              ),
            ),
            if (_labels.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    for (final label in _labels)
                      InputChip(
                        label: Text(label),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        deleteButtonTooltipMessage: 'Remove $label',
                        onDeleted: () => setState(() => _labels.remove(label)),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
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
                  for (final tag in suggestions)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.label_outline),
                      title: Text(tag),
                      onTap: () => _add(tag),
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
