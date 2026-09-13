/// Android's half of "the relay sends **data-only**" (research/14 §3.3): FCM
/// shows nothing by itself, so the app posts every notification — in the
/// foreground through `PushCoordinator`, and here in the background and from
/// cold, in the isolate `firebase_messaging` spins up for the purpose.
///
/// What it posts now is the **fallback line** of research/14 §3.1 (heading,
/// body and sub-text the relay already composed). R2.6 replaces the body with
/// the enriched one after two GETs; the two-version lock-screen shape of §4.1
/// D7 is already wired here, so that phase only has to fill the private half
/// in.
///
/// Everything below `backgroundNotificationFor` is a **pure function**, which
/// is what the tests drive: an isolate with no bindings cannot be pumped.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/notifications/notification_service.dart';
import 'push_pointer.dart';


/// The tap payload of a pushed notification: this prefix and then the
/// pointer's `data` map as JSON, so a tap on one the background isolate posted
/// routes through exactly the same code as a foreground tap.
const pushPayloadPrefix = 'push:';

String pushPayloadFor(PushPointer pointer) =>
    '$pushPayloadPrefix${jsonEncode(pointer.data)}';

/// The pointer inside a [pushPayloadPrefix] payload, or null when the payload
/// is an ordinary route (the polled notifications carry one of those).
PushPointer? pointerFromPayload(String payload) {
  if (!payload.startsWith(pushPayloadPrefix)) return null;
  try {
    final decoded = jsonDecode(payload.substring(pushPayloadPrefix.length));
    if (decoded is! Map) return null;
    return PushPointer.tryFrom({
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    });
  } catch (_) {
    return null;
  }
}

/// One notification to post, as [backgroundNotificationFor] decided it.
///
/// [publicTitle] and [publicBody] are the lock-screen version (research/14 §4.1
/// D7): in R2.4 they are the same fallback line as [title] and [body], because
/// nothing has been enriched yet, and R2.6 is where the private half gains the
/// comment text while this half stays the artifact line.
@immutable
class PushNotificationRequest {
  const PushNotificationRequest({
    required this.id,
    required this.tag,
    required this.groupKey,
    required this.title,
    required this.body,
    required this.publicTitle,
    required this.publicBody,
    required this.payload,
    this.subtitle,
  });

  final int id;

  /// The relay's collapse key, or the per-artifact derivation.
  final String tag;

  /// `{org}.{family}`: one group per artifact family per organization.
  final String groupKey;

  final String title;
  final String body;

  /// Android sub-text: the project.
  final String? subtitle;

  final String publicTitle;
  final String publicBody;

  /// `push:{json}`, decoded by `PushCoordinator` on a tap.
  final String payload;

  /// True while the lock screen may show the same words as the unlocked
  /// shade, which is the case until enrichment lands in R2.6. While it holds,
  /// the notification is posted `public`, which is the public version's
  /// content; when it stops holding, the private content needs a real
  /// `publicVersion` (see the note in [showPushNotification]).
  bool get publicMatchesPrivate => publicTitle == title && publicBody == body;
}

/// Whether a pushed pointer should become a notification, and what it should
/// say. Pure, so the background isolate's whole decision is unit-tested.
///
/// Nothing is posted when the pointer does not parse, when the user has
/// notifications off (the same opt-in the polled ones honour,
/// [NotificationService.enabledPrefKey]), or when the pointer is stale —
/// research/14 §4.1: a pointer older than ten minutes is answered by the app's
/// own poll, not by a notification. The test push (`boardhop.test`) is **not**
/// an exception: it is the support route, so it has to show.
PushNotificationRequest? backgroundNotificationFor(
  Map<String, Object?> data, {
  required bool enabled,
  required DateTime now,
}) {
  final pointer = PushPointer.tryFrom(data);
  if (pointer == null) return null;
  return backgroundNotificationForPointer(
    pointer,
    enabled: enabled,
    now: now,
  );
}

PushNotificationRequest? backgroundNotificationForPointer(
  PushPointer pointer, {
  required bool enabled,
  required DateTime now,
}) {
  if (!enabled) return null;
  if (pointer.isStaleAt(now)) return null;
  final (title, body) = pointer.message;
  return PushNotificationRequest(
    id: pointer.notificationId,
    tag: pointer.tag,
    groupKey: pointer.groupKey,
    title: title,
    body: body,
    subtitle: pointer.subtitle,
    // R2.4: the enriched body does not exist yet, so both versions are the
    // fallback line.
    publicTitle: title,
    publicBody: body,
    payload: pushPayloadFor(pointer),
  );
}

/// Hands [boardhopBackgroundMessage] to `firebase_messaging`, on Android only:
/// iOS has no Firebase app (the Runner talks to APNs directly) and the OS
/// presents the relay's alert itself.
///
/// Called from `main` after `PushService.create()`, which is what initialises
/// Firebase on this isolate. Failing here must never stop the app: push is a
/// bonus.
Future<void> registerPushBackgroundHandler() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    FirebaseMessaging.onBackgroundMessage(boardhopBackgroundMessage);
  } catch (e) {
    debugPrint('Push background handler unavailable: $e');
  }
}

/// The entry point `FirebaseMessaging.onBackgroundMessage` calls, in its own
/// isolate, for every data-only message that arrives while the app is in the
/// background or not running at all.
///
/// It must be a top-level function and it must survive tree shaking, hence
/// `@pragma('vm:entry-point')`. Nothing here may touch the app's widget tree:
/// this isolate has no UI, no router and no repositories — it posts a
/// notification and ends.
@pragma('vm:entry-point')
Future<void> boardhopBackgroundMessage(RemoteMessage message) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    await Firebase.initializeApp();
    final request = backgroundNotificationFor(
      message.data,
      enabled: await _notificationsEnabled(),
      now: DateTime.now(),
    );
    if (request == null) return;
    await showPushNotification(request);
  } catch (e) {
    // A background isolate that throws takes the process's next message with
    // it; a missed notification is the smaller failure.
    debugPrint('Push background handler failed: $e');
  }
}

/// The user's opt-in, read straight from shared preferences: the background
/// isolate has no `NotificationService`, only the same key.
Future<bool> _notificationsEnabled() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(NotificationService.enabledPrefKey) ?? false;
  } catch (_) {
    return false;
  }
}

/// Posts one [PushNotificationRequest] through a plugin instance of this
/// isolate's own, into the same `activity` channel the polled notifications
/// use, so both look alike and share the user's per-channel settings.
///
/// **Lock screen (research/14 §4.1, D7):** the shape is two versions, private
/// and public. `flutter_local_notifications` 22.3 has no `publicVersion`
/// binding, so while the two versions are identical — all of R2.4 — the
/// notification is posted `public`, which shows exactly the public version's
/// words on the lock screen. The day the private body carries a comment
/// (R2.6, whose Android path builds `NotificationCompat` in Kotlin) the public
/// half is [PushNotificationRequest.publicBody] and the private one is posted
/// `private` with it attached.
Future<void> showPushNotification(
  PushNotificationRequest request, {
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  final notifications = plugin ?? FlutterLocalNotificationsPlugin();
  try {
    if (plugin == null) {
      await notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              NotificationService.channelId,
              'Activity',
              description:
                  'Pull requests waiting for you, work item changes and builds',
              importance: Importance.defaultImportance,
            ),
          );
    }
    await notifications.show(
      id: request.id,
      title: request.title,
      body: request.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationService.channelId,
          'Activity',
          channelDescription:
              'Pull requests waiting for you, work item changes and builds',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          tag: request.tag,
          groupKey: request.groupKey,
          subText: request.subtitle,
          visibility: request.publicMatchesPrivate
              ? NotificationVisibility.public
              : NotificationVisibility.private,
        ),
      ),
      payload: request.payload,
    );
  } catch (e) {
    debugPrint('Push notification failed: $e');
  }
}
