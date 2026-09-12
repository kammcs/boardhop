import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/git_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import 'widgets/commit_visuals.dart';

/// One commit: message, author and committer, parents, linked work items
/// and the changed files, each opening a diff against the first parent.
class CommitPage extends StatefulWidget {
  const CommitPage({
    super.key,
    required this.org,
    required this.project,
    required this.repo,
    required this.commitId,
  });

  final String org;
  final String project;
  final GitRepository repo;
  final String commitId;

  @override
  State<CommitPage> createState() => _CommitPageState();
}

class _CommitPageState extends State<CommitPage> {
  GitCommit? _commit;
  List<GitChange>? _changes;
  bool _loading = true;
  String? _error;

  RepoRepository get _repos => context.read<RepoRepository>();

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
    final repos = _repos;
    try {
      final results = await Future.wait<Object?>([
        repos.commit(
          widget.org,
          widget.project,
          widget.repo.id,
          widget.commitId,
        ),
        repos.commitChanges(
          widget.org,
          widget.project,
          widget.repo.id,
          widget.commitId,
        ),
      ]);
      if (!mounted) return;
      final commit = results[0] as GitCommit?;
      setState(() {
        _commit = commit;
        _changes = results[1] as List<GitChange>;
        if (commit == null) _error = 'Commit not found.';
      });
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

  String? get _webUrl => RepoWebUrls.commit(widget.repo, widget.commitId);

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$what copied.')));
    }
  }

  void _openDiff(GitChange change) {
    final commit = _commit;
    final parent = commit?.parents.firstOrNull;
    context.push(
      diffRoute(
        _base,
        change: change,
        oldRef: parent ?? '',
        newRef: widget.commitId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final commit = _commit;
    final changes = _changes ?? const <GitChange>[];
    final short = widget.commitId.length > 7
        ? widget.commitId.substring(0, 7)
        : widget.commitId;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(short),
            Text(
              widget.repo.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              switch (v) {
                case 'browse':
                  context.push(
                    '$_base/code?ref=${Uri.encodeQueryComponent(widget.commitId)}',
                  );
                case 'copy-sha':
                  _copy(widget.commitId, 'Commit id');
                case 'copy-link':
                  if (_webUrl != null) _copy(_webUrl!, 'Link');
                case 'share':
                  if (_webUrl != null) {
                    SharePlus.instance.share(
                      ShareParams(
                        uri: Uri.parse(_webUrl!),
                        title: _commit?.subject ?? short,
                      ),
                    );
                  }
                case 'open':
                  if (_webUrl != null) {
                    launchUrl(
                      Uri.parse(_webUrl!),
                      mode: LaunchMode.externalApplication,
                    );
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'browse',
                child: ListTile(
                  leading: Icon(Icons.code),
                  title: Text('Browse files at this commit'),
                ),
              ),
              const PopupMenuItem(
                value: 'copy-sha',
                child: ListTile(
                  leading: Icon(Icons.content_copy),
                  title: Text('Copy commit id'),
                ),
              ),
              if (_webUrl != null) ...[
                const PopupMenuItem(
                  value: 'copy-link',
                  child: ListTile(
                    leading: Icon(Icons.link),
                    title: Text('Copy link'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.share_outlined),
                    title: Text('Share link'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'open',
                  child: ListTile(
                    leading: Icon(Icons.open_in_new),
                    title: Text('Open in browser'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ContentColumn(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: scrollEndPadding(context),
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                ListTile(
                  leading: Icon(Icons.error_outline, color: scheme.error),
                  title: Text(_error!),
                ),
              if (commit != null) ...[
                Padding(
                  padding: Spacing.page,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        commit.subject.isEmpty
                            ? '(no message)'
                            : commit.subject,
                        style: theme.textTheme.titleLarge,
                      ),
                      if (commit.body.isNotEmpty) ...[
                        const SizedBox(height: Spacing.sm),
                        // PR merge messages are Markdown on Azure DevOps.
                        MarkdownBody(data: commit.body, selectable: true),
                      ],
                      const SizedBox(height: Spacing.lg),
                      Row(
                        children: [
                          CommitAvatar(name: commit.authorName, radius: 18),
                          const SizedBox(width: Spacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  commit.authorName ?? 'Unknown author',
                                  style: theme.textTheme.titleSmall,
                                ),
                                Text(
                                  [
                                    if (commit.authorDate != null)
                                      relativeTime(commit.authorDate),
                                    if (commit.committerName != null &&
                                        commit.committerName !=
                                            commit.authorName)
                                      'committed by ${commit.committerName}',
                                  ].join(' · '),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ChangeCounts(commit: commit),
                        ],
                      ),
                    ],
                  ),
                ),
                if (commit.parents.isNotEmpty || commit.workItemIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      0,
                      Spacing.lg,
                      Spacing.md,
                    ),
                    child: Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.xs,
                      children: [
                        for (final p in commit.parents)
                          ActionChip(
                            avatar: const Icon(Icons.commit, size: 16),
                            label: Text(
                              'parent ${p.length > 7 ? p.substring(0, 7) : p}',
                            ),
                            onPressed: () => context.push('$_base/commits/$p'),
                          ),
                        for (final id in commit.workItemIds)
                          ActionChip(
                            avatar: const Icon(
                              Icons.assignment_outlined,
                              size: 16,
                            ),
                            label: Text('#$id'),
                            onPressed: () => context.push(
                              '${projectRoute(context, widget.org, widget.project)}'
                              '/work-items/$id',
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
                    _changes == null
                        ? 'Changed files'
                        : '${changes.length} changed file${changes.length == 1 ? '' : 's'}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
                for (final c in changes)
                  ChangeTile(change: c, onTap: () => _openDiff(c)),
                if (_changes != null && changes.isEmpty)
                  Padding(
                    padding: Spacing.page,
                    child: Text(
                      commit.isMerge
                          ? 'A merge commit with no changes of its own.'
                          : 'No file changes.',
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
