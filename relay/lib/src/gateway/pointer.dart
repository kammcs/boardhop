/// The pointer contract (research/06, "Push gateway").
///
/// Everything that leaves the relay for Apple or Google goes through this
/// type, and this type carries ids and at most a short title — never a comment
/// body, a PR description, a diff or a field value. "Rejects anything else at
/// the boundary" is a compile-time promise here: [PushSender.send] takes a
/// [PushPointer] and nothing else, so there is no way to smuggle a payload
/// past it.
library;

/// What the notification points at. The four kinds the app can route to.
enum PushArtifactType {
  workItem,
  pullRequest,
  build,
  approval;

  static PushArtifactType? tryParse(String? value) {
    for (final t in PushArtifactType.values) {
      if (t.name == value) return t;
    }
    return null;
  }
}

/// An opaque pointer to one artifact in one organization.
class PushPointer {
  PushPointer({
    required this.org,
    required this.eventType,
    required this.artifactType,
    required this.artifactId,
    required this.project,
    String? title,
    this.deepLink,
  }) : title = _truncate(title);

  /// Maximum length of the one short line a pointer may carry.
  static const maxTitle = 80;

  /// The Azure DevOps organization (the relay's tenant key).
  final String org;

  /// The service-hook event type, e.g. `git.pullrequest.updated`.
  final String eventType;

  final PushArtifactType artifactType;

  /// The artifact's id in its org: a work item id, a PR id, a build id.
  final String artifactId;

  /// Project name or id; the app needs it to build most routes.
  final String project;

  /// One short line, truncated to [maxTitle]. Null when the event carries none.
  final String? title;

  /// The app's account-scoped route, e.g.
  /// `/a/{account}/orgs/{org}/pull-requests/8336`. The account segment is
  /// filled in by the app, which knows which identity is signed in; the relay
  /// sends the org-relative part or a full route when it has one.
  final String? deepLink;

  static String? _truncate(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length <= maxTitle) return trimmed;
    return '${trimmed.substring(0, maxTitle - 1)}…';
  }

  /// Collapse (APNs `apns-collapse-id`) and thread (FCM `tag`) id: repeated
  /// events on one artifact replace each other in the shade instead of
  /// stacking up. APNs caps the header at 64 bytes.
  String get collapseId {
    final id = '$org.${artifactType.name}.$artifactId';
    return id.length <= 64 ? id : id.substring(id.length - 64);
  }

  /// The heading the phone shows. Derived from the event type only — never
  /// from content.
  String get notificationTitle => switch (eventType) {
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
    'ms.vss-pipelinechecks-events.approval-pending' => 'Approval waiting for you',
    _ => switch (artifactType) {
      PushArtifactType.workItem => 'Work item',
      PushArtifactType.pullRequest => 'Pull request',
      PushArtifactType.build => 'Build',
      PushArtifactType.approval => 'Approval',
    },
  };

  /// The body line: the short title when there is one, else the artifact.
  String get notificationBody => title ?? '$_artifactLabel $artifactId in $project';

  String get _artifactLabel => switch (artifactType) {
    PushArtifactType.workItem => 'Work item',
    PushArtifactType.pullRequest => 'Pull request',
    PushArtifactType.build => 'Build',
    PushArtifactType.approval => 'Approval for',
  };

  /// The `data` payload both transports carry, and the only thing the app
  /// routes on. All values are strings: FCM's `data` map allows nothing else.
  Map<String, String> toData() => {
    'org': org,
    'eventType': eventType,
    'artifactType': artifactType.name,
    'artifactId': artifactId,
    'project': project,
    if (title != null) 'title': title!,
    if (deepLink != null) 'deepLink': deepLink!,
  };

  /// Parses the pointer half of a request body. Returns null when a required
  /// field is missing or the artifact type is not one of the four.
  static PushPointer? tryFromJson(Map<String, Object?> json) {
    final org = json['org'];
    final eventType = json['eventType'];
    final artifactId = json['artifactId'];
    final project = json['project'];
    final artifactType = PushArtifactType.tryParse(json['artifactType'] as String?);
    if (org is! String || org.isEmpty) return null;
    if (eventType is! String || eventType.isEmpty) return null;
    if (artifactId is! String || artifactId.isEmpty) return null;
    if (project is! String) return null;
    if (artifactType == null) return null;
    return PushPointer(
      org: org,
      eventType: eventType,
      artifactType: artifactType,
      artifactId: artifactId,
      project: project,
      title: json['title'] as String?,
      deepLink: json['deepLink'] as String?,
    );
  }

  @override
  String toString() => 'PushPointer($org/$project ${artifactType.name}/$artifactId $eventType)';
}

/// What one push attempt did. `dead` means the transport said the device is
/// gone, and the caller deletes the row.
enum PushOutcome { sent, dead, failed, skipped }

class PushResult {
  const PushResult(this.outcome, {this.status, this.id, this.error});

  final PushOutcome outcome;

  /// HTTP status from APNs or FCM, when there was one.
  final int? status;

  /// `apns-id` or the FCM message name; the handle support asks Apple/Google
  /// about.
  final String? id;

  /// A short reason, never a token and never a payload.
  final String? error;

  bool get ok => outcome == PushOutcome.sent;
}

/// The one door out of the relay. Implemented by the APNs and FCM senders.
abstract interface class PushSender {
  /// True when the transport has everything it needs to send.
  bool get ready;

  /// Why not, when [ready] is false. Shown by `/healthz`.
  String get status;

  Future<PushResult> send(String deviceToken, PushPointer pointer);

  Future<void> close();
}
