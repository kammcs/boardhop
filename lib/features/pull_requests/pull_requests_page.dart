import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/pull_request.dart';
import '../../data/repositories/pull_request_repository.dart';
import '../../theme/theme.dart';
import '../work_items/widgets/work_item_visuals.dart';
import 'widgets/pr_visuals.dart';

/// Pull request inbox: to review, created by me, or all active, across the
/// organization (spike S4's org-level list) or inside one project.
class PullRequestsPage extends StatefulWidget {
  const PullRequestsPage({super.key, required this.org, this.project});

  final String org;
  final String? project;

  @override
  State<PullRequestsPage> createState() => _PullRequestsPageState();
}

class _PullRequestsPageState extends State<PullRequestsPage> {
  PrListFilter _filter = PrListFilter.toReview;
  List<PullRequest> _items = const [];
  String? _error;
  bool _loading = false;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await context.read<PullRequestRepository>().list(
        widget.org,
        project: widget.project,
        filter: _filter,
      );
      if (mounted) setState(() => _items = items);
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadedOnce = true;
        });
      }
    }
  }

  void _select(PrListFilter f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _items = const [];
      _loadedOnce = false;
    });
    _refresh();
  }

  void _open(PullRequest pr) => context.push(
    '/orgs/${Uri.encodeComponent(widget.org)}/pull-requests/${pr.id}',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inProject = widget.project != null;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.project ?? widget.org, overflow: TextOverflow.ellipsis),
            Text(
              'Pull requests',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        leading: IconButton(
          tooltip: inProject ? 'Projects' : 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => inProject
              ? context.go('/orgs/${Uri.encodeComponent(widget.org)}/projects')
              : context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ContentColumn(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_loading) const LinearProgressIndicator(),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.lg,
                    vertical: Spacing.xs,
                  ),
                  children: [
                    for (final (f, label) in const [
                      (PrListFilter.toReview, 'To review'),
                      (PrListFilter.mine, 'Created by me'),
                      (PrListFilter.all, 'All active'),
                    ]) ...[
                      ChoiceChip(
                        label: Text(label),
                        selected: _filter == f,
                        onSelected: (_) => _select(f),
                      ),
                      const SizedBox(width: Spacing.sm),
                    ],
                  ],
                ),
              ),
              if (_error != null)
                ListTile(
                  leading: Icon(Icons.error_outline, color: scheme.error),
                  title: Text(_error!),
                ),
              if (_items.isEmpty && _loadedOnce && !_loading)
                Padding(
                  padding: const EdgeInsets.all(Spacing.xl),
                  child: Column(
                    children: [
                      Icon(
                        Icons.call_merge,
                        size: 40,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(switch (_filter) {
                        PrListFilter.toReview =>
                          'No pull requests are waiting for your review.',
                        PrListFilter.mine =>
                          'You have no active pull requests.',
                        PrListFilter.all => 'No active pull requests.',
                      }, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              for (final pr in _items)
                _PullRequestTile(
                  pr: pr,
                  showProject: !inProject,
                  onTap: () => _open(pr),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PullRequestTile extends StatelessWidget {
  const _PullRequestTile({
    required this.pr,
    required this.showProject,
    required this.onTap,
  });

  final PullRequest pr;
  final bool showProject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vote = pr.overallVote;
    return ListTile(
      leading: IdentityAvatar(identity: pr.createdBy, radius: 16),
      title: Text(pr.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${showProject ? '${pr.projectName} / ' : ''}${pr.repositoryName} · !${pr.id}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                if (pr.isDraft) ...[
                  const DraftChip(),
                  const SizedBox(width: Spacing.xs),
                ],
                Icon(voteIcon(vote), size: 14, color: voteColor(context, vote)),
                const SizedBox(width: Spacing.xs),
                Flexible(
                  child: Text(
                    '${pr.sourceBranch} → ${pr.targetBranch}',
                    style: theme.textTheme.labelMedium?.copyWith(
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
      trailing: Text(
        relativeTime(pr.creationDate),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      isThreeLine: true,
      onTap: onTap,
    );
  }
}
