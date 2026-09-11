import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/activity.dart';
import '../../core/notifications/notification_service.dart';
import '../../data/activity_sync.dart';
import '../../data/models/pull_request.dart';
import '../../data/repositories/activity_repository.dart';
import '../../theme/theme.dart';
import '../pipelines/widgets/pipeline_visuals.dart';
import '../pull_requests/widgets/pr_visuals.dart';
import '../shared/account_scope.dart';

/// Foreground activity feed for one organization: refreshes on open, on
/// pull, and every minute while visible (≈0.013 TSTU per cycle, spike s09).
/// Items newer than the last visit carry a dot. Push arrives later with the
/// Marketplace extension and tenant relay (research/06).
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, required this.org});

  final String org;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

enum _Filter { all, pullRequests, workItems, builds }

class _ActivityPageState extends State<ActivityPage>
    with WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 60);

  List<ActivityItem> _items = const [];
  DateTime? _seen;
  DateTime? _shownAt;
  _Filter _filter = _Filter.all;
  String? _error;
  bool _loading = false;
  bool _loadedOnce = false;
  Timer? _poll;

  ActivityRepository get _repo => context.read<ActivityRepository>();
  ActivitySync? _sync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The feed marks items seen itself; no notifications while it is open.
    _sync = context.read<ActivitySync>()..suppressed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _poll = Timer.periodic(_pollEvery, (_) {
      if (mounted && !_loading) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _sync?.suppressed = false;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final repo = _repo;
    if (!_loadedOnce) {
      final results = await Future.wait<Object?>([
        repo.lastSeen(widget.org),
        repo.cached(widget.org),
      ]);
      if (!mounted) return;
      final cached =
          results[1] as ({List<ActivityItem> items, DateTime fetchedAt})?;
      setState(() {
        _seen = results[0] as DateTime?;
        if (cached != null) {
          _items = cached.items;
          _shownAt = cached.fetchedAt;
        }
      });
    }
    try {
      final items = await repo.refresh(widget.org);
      if (!mounted) return;
      setState(() {
        _items = items;
        _shownAt = DateTime.now();
      });
      // What is on screen now counts as seen next time.
      await repo.markSeen(widget.org);
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
      if (mounted && !quiet) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadedOnce = true;
        });
      }
    }
  }

  bool _matches(ActivityItem i) => switch (_filter) {
    _Filter.all => true,
    _Filter.pullRequests =>
      i.kind == ActivityKind.prReview || i.kind == ActivityKind.prMine,
    _Filter.workItems => i.kind == ActivityKind.workItem,
    _Filter.builds => i.kind == ActivityKind.build,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notifications = context.read<NotificationService>();
    final visible = _items.where(_matches).toList();
    final newCount = _items.where((i) => i.isNewSince(_seen)).length;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.org, overflow: TextOverflow.ellipsis),
            Text(
              'Activity${newCount > 0 ? ' · $newCount new' : ''}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ContentColumn(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: Spacing.xxl),
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
                      (_Filter.all, 'All'),
                      (_Filter.pullRequests, 'Pull requests'),
                      (_Filter.workItems, 'Work items'),
                      (_Filter.builds, 'Builds'),
                    ]) ...[
                      ChoiceChip(
                        label: Text(label),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
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
                  subtitle: _shownAt == null || _items.isEmpty
                      ? null
                      : Text(
                          'Showing activity from ${relativeTime(_shownAt)}.',
                        ),
                ),
              ListenableBuilder(
                listenable: notifications.enabledNotifier,
                builder: (context, _) => notifications.enabled
                    ? const SizedBox.shrink()
                    : ListTile(
                        leading: Icon(
                          Icons.notifications_active_outlined,
                          color: scheme.primary,
                        ),
                        title: const Text('Get notified about new activity'),
                        subtitle: const Text(
                          'Checked every few minutes while Boardhop is open.',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => notifications.setEnabled(true),
                          child: const Text('Turn on'),
                        ),
                      ),
              ),
              if (visible.isEmpty && _loadedOnce && !_loading)
                Padding(
                  padding: const EdgeInsets.all(Spacing.xl),
                  child: Column(
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 40,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(
                        _filter == _Filter.builds
                            ? 'No recent builds. Open a project\'s Pipelines tab to follow its runs here.'
                            : 'Nothing new. Pull requests waiting for you, your work items and recent builds show up here.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              for (final item in visible)
                _ActivityTile(
                  key: ValueKey(item.key),
                  item: item,
                  isNew: item.isNewSince(_seen),
                  onTap: () => context.push(item.route),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    super.key,
    required this.item,
    required this.isNew,
    required this.onTap,
  });

  final ActivityItem item;
  final bool isNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (IconData icon, Color color, String kind) = switch (item.kind) {
      ActivityKind.prReview => (
        Icons.rate_review_outlined,
        scheme.primary,
        'Review requested',
      ),
      ActivityKind.prMine => (
        voteIcon(
          PrVote.values.firstWhere(
            (v) => v.name == item.result,
            orElse: () => PrVote.none,
          ),
        ),
        voteColor(
          context,
          PrVote.values.firstWhere(
            (v) => v.name == item.result,
            orElse: () => PrVote.none,
          ),
        ),
        'Your pull request',
      ),
      ActivityKind.workItem => (
        Icons.assignment_outlined,
        scheme.onSurfaceVariant,
        'Work item updated',
      ),
      ActivityKind.build => (
        runGlyph(context, item.status ?? '', item.result ?? '').$1,
        runGlyph(context, item.status ?? '', item.result ?? '').$2,
        runResultLabel(item.status ?? '', item.result ?? ''),
      ),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kind,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
          Text(
            item.subtitle,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            relativeTime(item.time),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (isNew) ...[
            const SizedBox(height: Spacing.xs),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
      isThreeLine: true,
      onTap: onTap,
    );
  }
}
