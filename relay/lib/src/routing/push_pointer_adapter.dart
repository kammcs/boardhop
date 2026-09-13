import '../gateway/pointer.dart';
import 'notification.dart';

/// The one place a routed [Notification] becomes a [PushPointer].
///
/// It lives under `routing/` on purpose: `routing/` may import `gateway/`, and
/// the gateway imports nothing from routing, so the dependency runs in exactly
/// one direction and the pointer type stays the boundary it was built to be.
///
/// (It is a function rather than the `PushPointer.fromNotification` factory the
/// brief names, because a factory has to live inside the class and the class
/// lives on the other side of that boundary.)
///
/// Nothing is invented here: every field is carried across and the pointer's
/// own constructor caps, sanitises and drops what it will not take.
PushPointer pointerFromNotification(Notification notification, {required DateTime sentAt}) => PushPointer(
  org: notification.org,
  eventType: notification.kind.eventType,
  artifactType: notification.artifactType,
  artifactId: notification.artifactId,
  // The app's routes take a project name; the id is the fallback the relay
  // uses when a payload carried only that (research/14 §2.1).
  project: notification.projectName ?? notification.projectId ?? '',
  title: notification.title,
  deepLink: notification.deepLink,
  actor: notification.actorName,
  actorId: notification.actorId,
  verb: notification.verb,
  detail: notification.detail,
  anchor: notification.anchor,
  runId: notification.runId,
  subId: notification.subId,
  collapseKey: notification.collapseKey,
  sentAt: sentAt,
);
