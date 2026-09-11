import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/git_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../../theme/theme.dart';

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

class _BranchPickerPageState extends State<BranchPickerPage> {
  List<GitBranch> _branches = const [];
  String? _error;
  bool _loading = true;
  String _query = '';

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
              'Branches',
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
                Spacing.xs,
              ),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Find a branch',
                  prefixIcon: Icon(Icons.search),
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
              child: ListView.builder(
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
