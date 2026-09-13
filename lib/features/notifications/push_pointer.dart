import '../../core/routes.dart';

/// The pointer the relay pushes (research/06, "Push gateway"): ids, an event
/// type and at most one short line — never a comment, a description or a diff.
///
/// This is the app's half of the same contract the relay enforces in
/// `relay/lib/src/gateway/pointer.dart`; the wire form is the `data` map both
/// APNs and FCM carry, whose values are always strings.
class PushPointer {
  const PushPointer({
    required this.org,
    required this.eventType,
    required this.artifactType,
    required this.artifactId,
    required this.project,
    this.title,
    this.deepLink,
  });

  /// Reads one from a notification's `data` map. Returns null when the
  /// required fields are not all there, so a malformed push is ignored rather
  /// than opening a broken route.
  static PushPointer? tryFrom(Map<String, Object?> data) {
    String? str(String key) {
      final value = data[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final org = str('org');
    final artifactType = str('artifactType');
    final artifactId = str('artifactId');
    if (org == null || artifactType == null || artifactId == null) return null;
    return PushPointer(
      org: org,
      eventType: str('eventType') ?? '',
      artifactType: artifactType,
      artifactId: artifactId,
      project: str('project') ?? '',
      title: str('title'),
      deepLink: str('deepLink'),
    );
  }

  final String org;
  final String eventType;

  /// `workItem`, `pullRequest`, `build` or `approval`.
  final String artifactType;
  final String artifactId;
  final String project;
  final String? title;

  /// What the relay suggested, without the account segment: either a full
  /// account route (already `/a/...`) or an org-relative path.
  final String? deepLink;

  /// The in-app route for one signed-in account.
  ///
  /// A `deepLink` that already names an account is taken as it is; anything
  /// else is built from the ids, so the relay can never steer the app at a
  /// route belonging to another account.
  String route(String accountId) {
    final link = deepLink;
    if (link != null && link.startsWith('/a/')) return link;
    final byType = switch (artifactType) {
      'pullRequest' => Routes.pullRequest(accountId, org, artifactId),
      'workItem' when project.isNotEmpty => Routes.workItem(
        accountId,
        org,
        project,
        artifactId,
      ),
      'build' when project.isNotEmpty => Routes.pipelineRun(
        accountId,
        org,
        project,
        artifactId,
      ),
      'approval' when project.isNotEmpty => Routes.pipelines(
        accountId,
        org,
        project,
      ),
      _ => null,
    };
    // The test push and anything unroutable land on the org's activity feed,
    // which is where a person would look next anyway.
    return byType ?? Routes.activity(accountId, org);
  }

  /// Heading and body for the foreground notification, matching what the
  /// relay puts in the APNs/FCM alert so a pushed notification reads the same
  /// whether the app was open or not.
  (String, String) get message => (
    switch (eventType) {
      'boardhop.test' => 'Boardhop',
      'git.pullrequest.created' => 'New pull request',
      'git.pullrequest.updated' => 'Pull request updated',
      'git.pullrequest.merged' => 'Pull request merged',
      'ms.vss-code.git-pullrequest-comment-event' => 'New comment',
      'workitem.created' => 'New work item',
      'workitem.updated' => 'Work item updated',
      'workitem.commented' => 'Work item comment',
      'build.complete' => 'Build finished',
      'ms.vss-pipelines.stage-state-changed-event' => 'Pipeline stage changed',
      'ms.vss-pipelinechecks-events.approval-pending' =>
        'Approval waiting for you',
      _ => switch (artifactType) {
        'workItem' => 'Work item',
        'pullRequest' => 'Pull request',
        'build' => 'Build',
        'approval' => 'Approval',
        _ => 'Boardhop',
      },
    },
    title ?? '$_label $artifactId${project.isEmpty ? '' : ' in $project'}',
  );

  String get _label => switch (artifactType) {
    'workItem' => 'Work item',
    'pullRequest' => 'Pull request',
    'build' => 'Build',
    'approval' => 'Approval for',
    _ => 'Item',
  };

  /// Stable per artifact, so repeated events on one pull request replace each
  /// other in the shade instead of stacking.
  int get notificationId =>
      Object.hash(org, artifactType, artifactId) & 0x7fffffff;
}
