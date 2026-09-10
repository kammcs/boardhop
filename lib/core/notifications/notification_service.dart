import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local notifications for the activity feed (research/05 §8.4: honest
/// foreground polling, no push relay yet). Holds the user's opt-in, asks
/// the OS for permission on Android 13+ / iOS, posts one notification per
/// new item with its in-app route as payload, and streams taps.
class NotificationService {
  NotificationService._(this._plugin, this._prefs, bool enabled)
    : enabledNotifier = ValueNotifier(enabled);

  static const _prefKey = 'notifications.activity';
  static const channelId = 'activity';

  static Future<NotificationService> create() async {
    final plugin = FlutterLocalNotificationsPlugin();
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    final service = NotificationService._(
      plugin,
      prefs,
      prefs?.getBool(_prefKey) ?? false,
    );
    await service._init();
    return service;
  }

  /// For tests and widget previews: no platform plugin behind it.
  @visibleForTesting
  NotificationService.fake({bool enabled = false})
    : this._(null, null, enabled);

  final FlutterLocalNotificationsPlugin? _plugin;
  final SharedPreferences? _prefs;

  /// The user's opt-in; listen to rebuild switches and banners. (Not a
  /// ChangeNotifier itself, so it can sit in a plain RepositoryProvider.)
  final ValueNotifier<bool> enabledNotifier;
  bool _permissionDenied = false;
  String? _launchRoute;
  final _taps = StreamController<String>.broadcast();

  /// The user's opt-in (Settings > Notifications, or the feed banner).
  bool get enabled => enabledNotifier.value;

  /// True after the OS refused the permission prompt.
  bool get permissionDenied => _permissionDenied;

  /// Routes of tapped notifications while the app is running.
  Stream<String> get taps => _taps.stream;

  /// Route of the notification that launched the app, once.
  String? takeLaunchRoute() {
    final r = _launchRoute;
    _launchRoute = null;
    return r;
  }

  Future<void> _init() async {
    final plugin = _plugin;
    if (plugin == null) return;
    try {
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) _taps.add(payload);
        },
      );
      final launch = await plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _launchRoute = launch?.notificationResponse?.payload;
      }
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// Asks the OS (Android 13+, iOS) and records the answer. Returns the
  /// new [enabled] value.
  Future<bool> setEnabled(bool value) async {
    if (value) {
      final granted = await _requestPermission();
      _permissionDenied = !granted;
      enabledNotifier.value = granted;
    } else {
      enabledNotifier.value = false;
    }
    await _prefs?.setBool(_prefKey, enabled);
    return enabled;
  }

  Future<bool> _requestPermission() async {
    final plugin = _plugin;
    if (plugin == null) return true;
    try {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? true;
      }
      final ios = plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            true;
      }
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
    return true;
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String route,
  }) async {
    final plugin = _plugin;
    if (plugin == null || !enabled) return;
    try {
      await plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Activity',
            channelDescription:
                'Pull requests waiting for you, work item changes and builds',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: route,
      );
    } catch (e) {
      debugPrint('Notification show failed: $e');
    }
  }

  void dispose() {
    _taps.close();
    enabledNotifier.dispose();
  }
}
