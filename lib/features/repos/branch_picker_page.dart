import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/git_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';

/// Every branch of a repository with its standing against the default
/// branch; picking one pops with its name.
class BranchPickerPage extends StatefulWidget {
  const BranchPickerPage({
    super.key,
    required this.org,
    required this.project,
    required this.repoId,
    required this.repoName,
    this.current,
    this.defaultBranch,
  });

  final String org;
  final String project;
  final String repoId;
  final String repoName;
  final String? current;
  final String? defaultBranch;

  @override
  State<BranchPickerPage> createState() => _BranchPickerPageState();
}

enum _Section { branches, tags }

class _BranchPickerPageState extends State<BranchPickerPage> {
  List<GitBranch> _branches = const [];
  List<GitTag>? _tags;
  String? _error;
  bool _loading = true;
  String _query = '';
  _Section _section = _Section.branches;

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
      final branches = await context.read<RepoRepository>().branches(
        widget.org,
        widget.project,
        widget.repoId,
        defaultBranch: widget.defaultBranch,
      );
      if (mounted) setState(() => _branches = branches);
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTags() async {
    if (_tags != null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tags = await context.read<RepoRepository>().tags(
        widget.org,
        widget.project,
        widget.repoId,
      );
      if (mounted) setState(() => _tags = tags);
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _base =>
      '${projectRoute(context, widget.org, widget.project)}'
      '/repos/${Uri.encodeComponent(widget.repoName)}';

  Widget _tagsList(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = _query.trim().toLowerCase();
    final tags = _tags ?? const <GitTag>[];
    final shown = q.isEmpty
        ? tags
        : tags.where((t) => t.name.toLowerCase().contains(q)).toList();
    if (_tags != null && shown.isEmpty && !_loading) {
      return Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Text(
          q.isEmpty ? 'No tags in this repository.' : 'No tag matches "$q".',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final t = shown[i];
        return ListTile(
          leading: Icon(Icons.sell_outlined, color: scheme.onSurfaceVariant),
          title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              t.commitId.length > 7 ? t.commitId.substring(0, 7) : t.commitId,
              if (t.isAnnotated) 'annotated',
              if (t.creatorName != null) t.creatorName!,
            ].join(' · '),
          ),
          trailing: IconButton(
            tooltip: 'Browse files at ${t.name}',
            icon: const Icon(Icons.code),
            onPressed: () => context.push(
              '$_base/code?ref=${Uri.encodeQueryComponent(t.ref)}',
            ),
          ),
          onTap: () => context.push('$_base/commits/${t.commitId}'),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? _branches
        : _branches.where((b) => b.name.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.repoName, overflow: TextOverflow.ellipsis),
            Text(
              _section == _Section.tags ? 'Tags' : 'Branches',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: ContentColumn(
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.sm,
                Spacing.lg,
                0,
              ),
              child: SegmentedButton<_Section>(
                segments: const [
                  ButtonSegment(
                    value: _Section.branches,
                    label: Text('Branches'),
                    icon: Icon(Icons.fork_right),
                  ),
                  ButtonSegment(
                    value: _Section.tags,
                    label: Text('Tags'),
                    icon: Icon(Icons.sell_outlined),
                  ),
                ],
                selected: {_section},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (sel) {
                  setState(() => _section = sel.first);
                  if (sel.first == _Section.tags) _loadTags();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.sm,
                Spacing.lg,
                Spacing.xs,
              ),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: _section == _Section.tags
                      ? 'Find a tag'
                      : 'Find a branch',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            if (_error != null)
              ListTile(
                leading: Icon(Icons.error_outline, color: scheme.error),
                title: Text(_error!),
                trailing: TextButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ),
            Expanded(
              child: _section == _Section.tags
                  ? _tagsList(context)
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final b = shown[i];
                        final selected = b.name == widget.current;
                        final standing = b.isDefault
                            ? 'default branch'
                            : '${b.aheadCount} ahead · ${b.behindCount} behind';
                        final who = [
                          if (b.authorName != null) b.authorName!,
                          if (b.date != null) relativeTime(b.date),
                        ].join(' · ');
                        return ListTile(
                          selected: selected,
                          leading: Icon(
                            selected ? Icons.check_circle : Icons.commit,
                            color: selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  b.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (b.isDefault) ...[
                                const SizedBox(width: Spacing.sm),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.secondaryContainer,
                                    borderRadius: Radii.chip,
                                  ),
                                  child: Text(
                                    'default',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            [standing, if (who.isNotEmpty) who].join(' · ') +
                                (b.subject.isEmpty ? '' : '\n${b.subject}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: b.subject.isNotEmpty,
                          trailing: b.isDefault || widget.defaultBranch == null
                              ? null
                              : IconButton(
                                  tooltip:
                                      'Compare with ${widget.defaultBranch}',
                                  icon: const Icon(Icons.compare_arrows),
                                  onPressed: () => context.push(
                                    '$_base/compare'
                                    '?base=${Uri.encodeQueryComponent(widget.defaultBranch!)}'
                                    '&ref=${Uri.encodeQueryComponent(b.name)}',
                                  ),
                                ),
                          onTap: () => context.pop(b.name),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
