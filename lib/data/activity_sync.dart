import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/http/ado_exceptions.dart';
import '../core/notifications/notification_service.dart';
import 'db/json_cache.dart';
import 'db/app_database.dart';
import 'models/activity.dart';
import 'repositories/activity_repository.dart';
import 'repositories/org_repository.dart';
import 'repositories/pull_request_repository.dart';

/// Polls the activity feed of the last-opened organization while the app
/// is in the foreground and posts a local notification for each item that
/// is new since the user last looked at the feed, was not already announced,
/// and was not caused by the user. Paused while the Activity page is open
/// (it marks items seen itself).
class ActivitySync with WidgetsBindingObserver {
  ActivitySync({
    required ActivityRepository activity,
    required OrgRepository orgs,
    required PullRequestRepository pullRequests,
    required NotificationService notifications,
    AppDatabase? db,
    this.interval = const Duration(minutes: 3),
  }) : _activity = activity, // ignore: prefer_initializing_formals
       _orgs = orgs, // ignore: prefer_initializing_formals
       _pullRequests = pullRequests, // ignore: prefer_initializing_formals
       _notifications = notifications, // ignore: prefer_initializing_formals
       _cache = JsonCache(db);

  final ActivityRepository _activity;
  final OrgRepository _orgs;
  final PullRequestRepository _pullRequests;
  final NotificationService _notifications;
  final JsonCache _cache;
  final Duration interval;

  static const maxRemembered = 500;
  static String notifiedKey(String org) => 'activity:notified:$org';

  Timer? _timer;
  bool _running = false;
  bool _started = false;

  /// True while the Activity page is on screen.
  bool suppressed = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) => run());
    // First pass shortly after start, once the UI has settled.
    Timer(const Duration(seconds: 20), run);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) run();
  }

  /// Which items deserve a notification: newer than the last visit (never
  /// on the very first sync, which only sets the baseline), not announced
  /// before, and not the user's own doing.
  static List<ActivityItem> toNotify(
    List<ActivityItem> items, {
    required DateTime? lastSeen,
    required Set<String> notified,
    required String? meId,
  }) {
    if (lastSeen == null) return const [];
    return [
      for (final i in items)
        if (i.isNewSince(lastSeen) &&
            !notified.contains(i.key) &&
            (i.actorId == null ||
                i.actorId != meId ||
                i.kind == ActivityKind.prReview))
          i,
    ];
  }

  static (String, String) message(ActivityItem i) => switch (i.kind) {
    ActivityKind.prReview => ('Review requested', i.title),
    ActivityKind.prMine => ('Your pull request', i.title),
    ActivityKind.workItem => ('Work item updated', i.title),
    ActivityKind.build => (
      switch (i.result) {
        'succeeded' => 'Build succeeded',
        'failed' => 'Build failed',
        'partiallySucceeded' => 'Build partially succeeded',
        'canceled' => 'Build canceled',
        _ => 'Build ${i.status}',
      },
      i.title,
    ),
  };

  Future<void> run() async {
    if (_running || suppressed || !_notifications.enabled) return;
    _running = true;
    try {
      final org = await _orgs.lastOpened();
      if (org == null) return;
      final lastSeen = await _activity.lastSeen(org);
      final items = await _activity.refresh(org);
      if (lastSeen == null) {
        // Baseline: nothing to announce yet, but remember this moment.
        await _activity.markSeen(org);
        return;
      }
      final remembered = await _cache.get(notifiedKey(org));
      final notified = <String>{
        if (remembered?.json case final List l) ...l.map((e) => e.toString()),
      };
      String? me;
      try {
        me = await _pullRequests.meId(org);
      } on AdoException {
        me = null;
      }
      final fresh = toNotify(
        items,
        lastSeen: lastSeen,
        notified: notified,
        meId: me,
      );
      for (final i in fresh.take(10)) {
        final (title, body) = message(i);
        await _notifications.show(
          id: i.key.hashCode & 0x7fffffff,
          title: title,
          body: body,
          route: i.route,
        );
        notified.add(i.key);
      }
      if (fresh.isNotEmpty) {
        final list = notified.toList();
        await _cache.put(
          notifiedKey(org),
          list.length > maxRemembered
              ? list.sublist(list.length - maxRemembered)
              : list,
        );
      }
    } on AdoException catch (e) {
      debugPrint('Activity sync skipped: ${e.message}');
    } catch (e) {
      debugPrint('Activity sync failed: $e');
    } finally {
      _running = false;
    }
  }
}
