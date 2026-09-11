import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/git_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import 'widgets/commit_visuals.dart';

/// A branch against another (usually the default): ahead/behind counts and
/// the files that differ between their common ancestor and the target,
/// each opening a diff.
class ComparePage extends StatefulWidget {
  const ComparePage({
    super.key,
    required this.org,
    required this.project,
    required this.repo,
    required this.base,
    required this.target,
  });

  final String org;
  final String project;
  final GitRepository repo;
  final String base;
  final String target;

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  GitCompare? _compare;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<RepoRepository>().compare(
        widget.org,
        widget.project,
        widget.repo.id,
        base: widget.base,
        target: widget.target,
      );
      if (mounted) setState(() => _compare = result);
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _base =>
      '${projectRoute(context, widget.org, widget.project)}'
      '/repos/${Uri.encodeComponent(widget.repo.name)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cmp = _compare;
    final files = cmp?.files ?? const <GitChange>[];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Compare'),
            Text(
              '${GitVersion.label(widget.base)} ← ${GitVersion.label(widget.target)}',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ContentColumn(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: Spacing.xxl),
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                ListTile(
                  leading: Icon(Icons.error_outline, color: scheme.error),
                  title: Text(_error!),
                ),
              if (cmp != null) ...[
                Padding(
                  padding: Spacing.page,
                  child: Row(
                    children: [
                      _Stat(
                        value: cmp.aheadCount,
                        label: 'ahead',
                        hint:
                            'commits on ${GitVersion.label(widget.target)} '
                            'not on ${GitVersion.label(widget.base)}',
                      ),
                      const SizedBox(width: Spacing.lg),
                      _Stat(
                        value: cmp.behindCount,
                        label: 'behind',
                        hint:
                            'commits on ${GitVersion.label(widget.base)} '
                            'not on ${GitVersion.label(widget.target)}',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    0,
                    Spacing.lg,
                    Spacing.md,
                  ),
                  child: Wrap(
                    spacing: Spacing.sm,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.history, size: 16),
                        label: Text(
                          'Commits on ${GitVersion.label(widget.target)}',
                        ),
                        onPressed: () => context.push(
                          '$_base/commits?ref=${Uri.encodeQueryComponent(widget.target)}',
                        ),
                      ),
                      if (cmp.commonCommit.isNotEmpty)
                        ActionChip(
                          avatar: const Icon(Icons.commit, size: 16),
                          label: Text(
                            'Common ancestor ${cmp.commonCommit.substring(0, 7)}',
                          ),
                          onPressed: () => context.push(
                            '$_base/commits/${cmp.commonCommit}',
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    Spacing.lg,
                    Spacing.lg,
                    Spacing.xs,
                  ),
                  child: Text(
                    '${files.length} changed file${files.length == 1 ? '' : 's'}'
                    '${cmp.allChangesIncluded ? '' : ' (first ${files.length})'}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
                for (final c in files)
                  ChangeTile(
                    change: c,
                    onTap: () => context.push(
                      diffRoute(
                        _base,
                        change: c,
                        oldRef: cmp.commonCommit,
                        newRef: cmp.targetCommit,
                      ),
                    ),
                  ),
                if (files.isEmpty && !_loading)
                  Padding(
                    padding: Spacing.page,
                    child: Text(
                      cmp.aheadCount == 0
                          ? '${GitVersion.label(widget.target)} has nothing '
                                '${GitVersion.label(widget.base)} lacks.'
                          : 'No file differences.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.hint});

  final int value;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Tooltip(
        message: hint,
        child: Container(
          padding: Spacing.card,
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: Radii.card,
          ),
          child: Column(
            children: [
              Text('$value', style: theme.textTheme.headlineSmall),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
