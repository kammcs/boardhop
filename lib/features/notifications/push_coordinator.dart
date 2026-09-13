import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/notifications/notification_service.dart';
import '../../data/models/activity.dart';
import '../../data/repositories/activity_repository.dart';
import 'push_background.dart';
import 'push_pointer.dart';
import 'push_registrar.dart';
import 'push_service.dart';
import 'push_verbs.dart';

/// Ties the platform token, the relay registration and the existing local
/// notifications together.
///
/// It is the only piece that knows which signed-in account an organization
/// belongs to, so it is where an incoming pointer becomes an account-scoped
/// route.
///
/// The rules:
/// * register when the user has notifications on, is signed in, and the OS has
///   given a token;
/// * heartbeat once a day at app start;
/// * `DELETE` on sign-out, before MSAL forgets the account;
/// * a foreground push is shown through the feed's own notification channel,
///   because the OS shows nothing while the app is in front (on Android the
///   relay's message is data-only, so nothing is shown in **any** state unless
///   the app posts it: the background and terminated states are
///   `push_background.dart`);
/// * every pointer that arrives is also written into the Activity feed at
///   once, so the feed and the notifications agree without waiting for the
///   next poll (research/14 §4.2).
class PushCoordinator {
  PushCoordinator({
    required this.push,
    required this.notifications,
    required this.registrarFor,
    required this.orgFor,
    required this.openRoute,
    this.activityFor,
  });

  final PushService push;
  final NotificationService notifications;

  /// The per-account registrar from `AppDependencies`.
  final PushRegistrar Function(String accountId) registrarFor;

  /// The organization an account is working in (its last-opened one).
  final Future<String?> Function(String accountId) orgFor;

  final void Function(String route) openRoute;

  /// The per-account activity feed, so a pushed pointer lands in it straight
  /// away. Null in tests that only care about routing.
  final ActivityRepository Function(String accountId)? activityFor;

  final Set<String> _accounts = {};
  StreamSubscription<PushPointer>? _foreground;
  StreamSubscription<PushPointer>? _opened;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _foreground = push.foreground.listen(_showForeground);
    _opened = push.opened.listen(_open);
    push.token.addListener(_onTokenChanged);
    notifications.enabledNotifier.addListener(_onEnabledChanged);
    final launch = push.takeLaunchPointer();
    if (launch != null) _open(launch);
  }

  /// Called whenever the set of signed-in accounts changes, and at start.
  Future<void> syncAccounts(Iterable<String> accountIds) async {
    _accounts
      ..clear()
      ..addAll(accountIds);
    for (final id in accountIds) {
      await registrarFor(id).load();
    }
    await _registerAll();
  }

  /// Sign-out for one account: tell the relay while a token can still be
  /// acquired, then forget it here.
  Future<void> signOut(String accountId) async {
    _accounts.remove(accountId);
    await registrarFor(accountId).unregister();
  }

  /// Registers (or heartbeats) every signed-in account. Does nothing until the
  /// user has turned notifications on and the OS has handed over a token.
  Future<void> _registerAll() async {
    if (!notifications.enabled) return;
    final platform = push.platform;
    if (platform == null) return;
    // Always through refreshToken: on Android that is what turns FCM on for
    // the install, and it is a no-op once a token is in hand.
    final token = await push.refreshToken();
    if (token == null || token.isEmpty) return;

    for (final accountId in _accounts.toList()) {
      final registrar = registrarFor(accountId);
      final current = registrar.registration.value ?? await registrar.load();
      final org = current?.org ?? await orgFor(accountId);
      if (org == null) continue;
      if (current == null) {
        await registrar.register(org: org, platform: platform, token: token);
      } else {
        await registrar.heartbeat(token: token);
        // A heartbeat that found the device gone clears the record; register
        // again so the phone does not go quietly unreachable.
        if (registrar.registration.value == null) {
          await registrar.register(org: org, platform: platform, token: token);
        }
      }
    }
  }

  /// The platform rotated the token: re-register everywhere it is known.
  void _onTokenChanged() {
    final token = push.token.value;
    if (token == null || token.isEmpty) return;
    unawaited(_reregister(token));
  }

  Future<void> _reregister(String token) async {
    if (!notifications.enabled) return;
    final platform = push.platform;
    if (platform == null) return;
    for (final accountId in _accounts.toList()) {
      final registrar = registrarFor(accountId);
      final current = registrar.registration.value;
      final org = current?.org ?? await orgFor(accountId);
      if (org == null) continue;
      await registrar.register(org: org, platform: platform, token: token);
    }
  }

  void _onEnabledChanged() {
    if (notifications.enabled) {
      unawaited(_registerAll());
    } else {
      // Turning notifications off should stop the pushes too, not only hide
      // the local ones.
      unawaited(_unregisterAll());
    }
  }

  Future<void> _unregisterAll() async {
    for (final accountId in _accounts.toList()) {
      await registrarFor(accountId).unregister();
    }
  }

  /// Which signed-in account a pushed organization belongs to: the one that
  /// registered for it. Falls back to the only signed-in account.
  String? accountForOrg(String org) {
    for (final accountId in _accounts) {
      if (registrarFor(accountId).registration.value?.org == org) {
        return accountId;
      }
    }
    return _accounts.length == 1 ? _accounts.first : null;
  }

  Future<void> _showForeground(PushPointer pointer) async {
    final accountId = accountForOrg(pointer.org);
    if (accountId == null) return;
    unawaited(_insertIntoFeed(pointer, accountId));
    // iOS presents a remote push itself, so re-raising it here would show
    // the same event twice. Only Android needs this: the relay's message is
    // data-only, so the OS shows nothing at all and the app posts it.
    if (push.platform != 'android') return;
    if (pointer.isStale) return;
    final (title, body) = pointer.message;
    await notifications.show(
      id: pointer.notificationId,
      title: title,
      body: body,
      // The same payload the background isolate posts, so a tap routes
      // through one path whichever state the app was in.
      route: pushPayloadFor(pointer),
      tag: pointer.tag,
      groupKey: pointer.groupKey,
      subtitle: pointer.subtitle,
    );
  }

  /// A tap on a notification the background isolate posted: its payload is
  /// the pointer as JSON behind [pushPayloadPrefix], not a route. Returns true
  /// when this was such a payload, so the caller knows not to treat it as one.
  bool handleTapPayload(String payload) {
    final pointer = pointerFromPayload(payload);
    if (pointer == null) return payload.startsWith(pushPayloadPrefix);
    _open(pointer);
    return true;
  }

  void _open(PushPointer pointer) {
    final accountId = accountForOrg(pointer.org);
    if (accountId == null) {
      debugPrint('Push: no signed-in account for ${pointer.org}');
      return;
    }
    unawaited(_insertIntoFeed(pointer, accountId));
    openRoute(pointer.route(accountId));
  }

  /// Writes the pointer into that account's Activity feed and marks its key
  /// announced, so the next poll neither duplicates the row nor notifies
  /// again (research/14 §4.2).
  Future<void> _insertIntoFeed(PushPointer pointer, String accountId) async {
    final repository = activityFor?.call(accountId);
    if (repository == null) return;
    final item = pushedActivityItem(pointer, accountId);
    if (item == null) return;
    try {
      await repository.insertPushed(pointer.org, item);
    } catch (e) {
      debugPrint('Push: could not insert into the feed ($e)');
    }
  }

  void dispose() {
    _foreground?.cancel();
    _opened?.cancel();
    push.token.removeListener(_onTokenChanged);
    notifications.enabledNotifier.removeListener(_onEnabledChanged);
    _started = false;
  }
}

/// The Activity row a pushed pointer becomes (research/14 §4.2). Null for the
/// test push and anything with no artifact to point at, which has no feed row.
///
/// The key is the feed's own (`pr:8336`, `wi:15503`, `build:4242`), so the
/// next poll's copy of the same artifact replaces this one instead of
/// doubling it.
ActivityItem? pushedActivityItem(PushPointer pointer, String accountId) {
  final key = pointer.activityKey;
  if (key == null) return null;
  return ActivityItem(
    kind: switch (pointer.artifactType) {
      'workItem' => ActivityKind.workItem,
      'build' || 'approval' => ActivityKind.build,
      _ => _authorFacing.contains(pointer.verb)
          ? ActivityKind.prMine
          : ActivityKind.prReview,
    },
    key: key,
    title: pointer.fallbackTitle ?? pointer.title ?? pointer.heading,
    subtitle: pointer.body,
    route: pointer.route(accountId),
    time: pointer.sentAt?.toLocal() ?? DateTime.now(),
    project: pointer.project.isEmpty ? null : pointer.project,
    result: pointer.detail,
    actor: pointer.actor,
    actorId: pointer.actorId,
  );
}

/// What happens to a pull request of **yours**; everything else on a PR is
/// review-side and shows as "waiting for you".
const _authorFacing = <PushVerb>{
  PushVerb.voted,
  PushVerb.prCompleted,
  PushVerb.prAbandoned,
  PushVerb.mergeFailed,
};
