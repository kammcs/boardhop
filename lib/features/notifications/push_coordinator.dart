import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/notifications/notification_service.dart';
import 'push_pointer.dart';
import 'push_registrar.dart';
import 'push_service.dart';

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
///   because the OS shows nothing while the app is in front.
class PushCoordinator {
  PushCoordinator({
    required this.push,
    required this.notifications,
    required this.registrarFor,
    required this.orgFor,
    required this.openRoute,
  });

  final PushService push;
  final NotificationService notifications;

  /// The per-account registrar from `AppDependencies`.
  final PushRegistrar Function(String accountId) registrarFor;

  /// The organization an account is working in (its last-opened one).
  final Future<String?> Function(String accountId) orgFor;

  final void Function(String route) openRoute;

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
    // iOS presents a remote push itself, so re-raising it here would show
    // the same event twice. Only Android needs this: FCM delivers a
    // foreground message silently and leaves the showing to the app.
    if (push.platform != 'android') return;
    final accountId = accountForOrg(pointer.org);
    if (accountId == null) return;
    final (title, body) = pointer.message;
    await notifications.show(
      id: pointer.notificationId,
      title: title,
      body: body,
      route: pointer.route(accountId),
    );
  }

  void _open(PushPointer pointer) {
    final accountId = accountForOrg(pointer.org);
    if (accountId == null) {
      debugPrint('Push: no signed-in account for ${pointer.org}');
      return;
    }
    openRoute(pointer.route(accountId));
  }

  void dispose() {
    _foreground?.cancel();
    _opened?.cancel();
    push.token.removeListener(_onTokenChanged);
    notifications.enabledNotifier.removeListener(_onEnabledChanged);
    _started = false;
  }
}
