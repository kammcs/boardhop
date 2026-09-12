import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/http/ado_exceptions.dart';
import '../../../../theme/theme.dart';

/// Tag chips with an add field: suggestions come from the project's tag list
/// (`wit/tags`), and the value is a list the patch joins with `formatTags`.
Future<List<String>?> pickTags(
  BuildContext context, {
  required List<String> current,
  required Future<List<String>> Function() suggestions,
}) {
  // From medium up a centered dialog, like every other picker of the form;
  // a sheet pinned to the screen edge sat oddly beside the tablet's own
  // dialog (iPad walkthrough). A phone keeps the sheet.
  if (!context.breakpoint.isCompact) {
    return showDialog<List<String>>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _TagsSheet(
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
        _TagsSheet(current: current, suggestions: suggestions),
  );
}

class _TagsSheet extends StatefulWidget {
  const _TagsSheet({
    required this.current,
    required this.suggestions,
    this.dialog = false,
  });

  final List<String> current;
  final Future<List<String>> Function() suggestions;

  /// Centered dialog rather than a bottom sheet: a shorter box with its own
  /// title padding, since there is no drag handle above it.
  final bool dialog;

  @override
  State<_TagsSheet> createState() => _TagsSheetState();
}

class _TagsSheetState extends State<_TagsSheet> {
  final _input = TextEditingController();
  late final List<String> _tags = [...widget.current];
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
    final tag = raw.trim();
    if (tag.isEmpty) return;
    final exists = _tags.any((t) => t.toLowerCase() == tag.toLowerCase());
    setState(() {
      if (!exists) _tags.add(tag);
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
    final chosen = {for (final t in _tags) t.toLowerCase()};
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
                    child: Text('Tags', style: theme.textTheme.titleMedium),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_tags),
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
                  hintText: 'Add a tag',
                  prefixIcon: const Icon(Icons.label_outline),
                  suffixIcon: IconButton(
                    tooltip: 'Add tag',
                    icon: const Icon(Icons.add),
                    onPressed: () => _add(_input.text),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: _add,
              ),
            ),
            if (_tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    for (final tag in _tags)
                      InputChip(
                        label: Text(tag),
                        onDeleted: () => setState(() => _tags.remove(tag)),
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
