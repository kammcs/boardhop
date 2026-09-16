import 'package:shared_preferences/shared_preferences.dart';

import '../core/notifications/notification_service.dart';
import '../data/repositories/activity_repository.dart';
import '../features/notifications/push_coordinator.dart';
import '../features/notifications/push_pointer.dart';
import '../features/notifications/push_verbs.dart';
import 'demo_world.dart';

/// Demo mode starts as a phone that has had notifications on for a while:
/// the opt-in is set, so the feed shows no "Turn on" row, and the relay's
/// pushes of the last hour are already in the feed.
Future<void> prepareDemoNotifications() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(NotificationService.enabledPrefKey, true);
}

/// The pushed rows: what the relay announces that the feed's own poll does
/// not list (mentions, failed deploys, approvals).
Future<void> seedDemoActivity(ActivityRepository activity) async {
  final pointers = [
    PushPointer(
      org: DemoWorld.org,
      eventType: 'workitem.commented',
      artifactType: 'workItem',
      artifactId: '1231',
      project: DemoWorld.project,
      title: DemoWorld.workItem(1231).title,
      actor: DemoWorld.priya.name,
      actorId: DemoWorld.priya.id,
      verb: PushVerb.mentioned,
      sentAt: DemoWorld.minutesAgo(2),
    ),
    PushPointer(
      org: DemoWorld.org,
      eventType: 'ms.vss-pipelinechecks-events.approval-pending',
      artifactType: 'approval',
      artifactId: 'release-approval',
      runId: '3216',
      project: DemoWorld.project,
      title: 'boardhop-release · Release to App Store',
      verb: PushVerb.approvalPending,
      sentAt: DemoWorld.minutesAgo(26),
    ),
    PushPointer(
      org: DemoWorld.org,
      eventType: 'build.complete',
      artifactType: 'build',
      artifactId: '3214',
      project: DemoWorld.project,
      title: 'relay-deploy · health check failed',
      actor: DemoWorld.aiko.name,
      actorId: DemoWorld.aiko.id,
      verb: PushVerb.buildFailed,
      detail: 'failed',
      sentAt: DemoWorld.minutesAgo(41),
    ),
  ];
  for (final pointer in pointers) {
    final item = pushedActivityItem(pointer, DemoWorld.me.id);
    if (item != null) await activity.insertPushed(DemoWorld.org, item);
  }
}
