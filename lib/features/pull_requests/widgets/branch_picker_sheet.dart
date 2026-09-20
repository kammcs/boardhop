import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/http/ado_exceptions.dart';
import '../../../data/models/git_repository.dart';
import '../../../theme/theme.dart';

/// Picks a branch **name** (not a ref) for Change target branch (R2).
///
/// The list is `stats/branches`, the same read the repository page uses, so
/// each row can say how far it is ahead of and behind the default branch.
/// The pull request's current target is marked and cannot be picked again.
Future<String?> pickBranch(
  BuildContext context, {
  required String title,
  required Future<List<GitBranch>> Function() branches,
  String? current,
}) {
  if (!context.breakpoint.isCompact) {
    return showBoardhopDialog<String>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _BranchSheet(
            title: title,
            branches: branches,
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
    builder: (context) =>
        _BranchSheet(title: title, branches: branches, current: current),
  );
}

class _BranchSheet extends StatefulWidget {
  const _BranchSheet({
    required this.title,
    required this.branches,
    this.current,
    this.dialog = false,
  });

  final String title;
  final Future<List<GitBranch>> Function() branches;
  final String? current;
  final bool dialog;

  @override
  State<_BranchSheet> createState() => _BranchSheetState();
}

class _BranchSheetState extends State<_BranchSheet> {
  final _query = TextEditingController();
  List<GitBranch> _all = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.branches();
      if (mounted) setState(() => _all = all);
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = _query.text.trim().toLowerCase();
    final shown = [
      for (final b in _all)
        if (q.isEmpty || b.name.toLowerCase().contains(q)) b,
    ];
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: widget.dialog ? math.min(560, height * 0.8) : height * 0.8,
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
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search branches',
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
                  if (!_loading && shown.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: Text(
                        'No branch matches.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final b in shown)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        b.isDefault ? Icons.star : Icons.call_split,
                        size: 20,
                        color: b.isDefault
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      title: Text(
                        b.name,
                        style: BoardhopTheme.codeStyle(context),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: b.aheadCount == 0 && b.behindCount == 0
                          ? null
                          : Text(
                              '${b.aheadCount} ahead · ${b.behindCount} behind',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                      trailing: b.name == widget.current
                          ? const Icon(Icons.check)
                          : null,
                      enabled: b.name != widget.current,
                      onTap: () => Navigator.of(context).pop(b.name),
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
