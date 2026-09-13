/// The pointer contract (research/06, "Push gateway"; research/14 §3.2 for the
/// R2.3 fields).
///
/// Everything that leaves the relay for Apple or Google goes through this
/// type, and this type carries ids, a short title, a display name and a
/// closed-vocabulary verb — never a comment body, a PR description, a diff or a
/// field value. "Rejects anything else at the boundary" is a compile-time
/// promise here: [PushSender.send] takes a [PushPointer] and nothing else, so
/// there is no way to smuggle a payload past it, and every field below is
/// either an id, an enum, or a string with a length cap.
///
/// `gateway/` imports nothing from `routing/`; the shared vocabulary
/// (`lib/src/verb.dart`) sits above both. The adapter that turns a routed
/// `Notification` into a pointer lives on the routing side, in
/// `routing/push_pointer_adapter.dart`.
library;

import 'dart:convert';

import '../verb.dart';

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

  /// The short family the collapse keys, the mute list and FCM's four
  /// per-device collapse keys all share: `wi`, `pr`, `build`, `approval`.
  String get family => switch (this) {
    PushArtifactType.workItem => 'wi',
    PushArtifactType.pullRequest => 'pr',
    PushArtifactType.build => 'build',
    PushArtifactType.approval => 'approval',
  };

  /// How the artifact is written in a sentence: `#15545`, `!8348`. Builds and
  /// approvals name themselves in the title, so they have no reference.
  String? ref(String artifactId) => switch (this) {
    PushArtifactType.workItem => '#$artifactId',
    PushArtifactType.pullRequest => '!$artifactId',
    _ => null,
  };
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
    String? actor,
    String? actorId,
    this.verb,
    String? detail,
    String? anchor,
    String? runId,
    String? subId,
    String? collapseKey,
    DateTime? sentAt,
  }) : title = _truncate(title, maxTitle),
       actor = _truncate(actor, maxActor),
       actorId = _id(actorId),
       detail = verb?.sanitizeDetail(detail),
       anchor = _anchor(anchor),
       runId = _id(runId),
       subId = _id(subId),
       collapseKey = _collapse(collapseKey),
       sentAt = sentAt?.toUtc();

  /// Maximum length of the one short line a pointer may carry.
  static const maxTitle = 80;

  /// research/14 §3.2: `actor` is a display name, capped at 60.
  static const maxActor = 60;

  /// APNs caps `apns-collapse-id` at 64 bytes, so nothing longer is useful.
  static const maxCollapseKey = 64;

  /// Ids (identity GUIDs, run ids, subscription ids) are short by nature; the
  /// cap only stops a malformed one from growing the payload.
  static const maxId = 64;

  /// The anchors of research/14 §3.2, and nothing else.
  static final _anchorPattern = RegExp(r'^(?:comment|thread|approval):[A-Za-z0-9._\-]{1,64}$|^tab:files$');

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
  /// It already reads as the artifact line — `#15545 · Fix the snackbar` — the
  /// relay having prefixed the id in `routing/links.dart`.
  final String? title;

  /// The app's account-scoped route, e.g.
  /// `/a/{account}/orgs/{org}/pull-requests/8336`. The account segment is
  /// filled in by the app, which knows which identity is signed in; the relay
  /// sends the org-relative part or a full route when it has one.
  final String? deepLink;

  /// Who did it, as a display name of at most [maxActor] characters. Null for
  /// a service identity and for the events whose body names nobody.
  final String? actor;

  /// The actor's identity GUID, so the app can hide a self-caused notification
  /// that slipped through and enrichment can compare.
  final String? actorId;

  /// What they did. The relay sends the enum **name**; the app turns it into
  /// words. Null only on a pointer built before R2.3 or by a malformed body.
  final Verb? verb;

  /// The metadata the verb needs: a state name, a vote label, a stage name, a
  /// build result. Validated against [Verb.detailVocabulary] where the verb has
  /// one and capped at [Verb.maxDetail] otherwise — never free text.
  final String? detail;

  /// `comment:{id}`, `thread:{id}`, `approval:{id}` or `tab:files`.
  final String? anchor;

  /// Approvals only: the run the approval belongs to.
  final String? runId;

  /// The hook subscription that produced it, for support and the health view.
  /// Never shown.
  final String? subId;

  /// The routed collapse key (`pr.8348.t42`), when the notification had one.
  /// [collapseId] falls back to the per-artifact derivation.
  final String? collapseKey;

  /// When the relay sent it, so enrichment can skip a stale pointer (>10 min).
  final DateTime? sentAt;

  static String? _truncate(String? value, int max) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length <= max) return trimmed;
    return '${trimmed.substring(0, max - 1)}…';
  }

  /// An id is kept as it is or dropped; a truncated id would be a wrong id.
  static String? _id(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxId) return null;
    return trimmed;
  }

  /// A collapse key is trimmed from the **left**: the artifact and its thread
  /// suffix are what tell two notifications apart, and the org prefix is the
  /// expendable head.
  static String? _collapse(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length <= maxCollapseKey) return trimmed;
    return trimmed.substring(trimmed.length - maxCollapseKey);
  }

  static String? _anchor(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return _anchorPattern.hasMatch(trimmed) ? trimmed : null;
  }

  /// Collapse (APNs `apns-collapse-id` and `thread-id`, Android notification
  /// tag) id: repeated events on one artifact replace each other in the shade
  /// instead of stacking up. The routed [collapseKey] when there is one — it is
  /// org-scoped and separates a comment thread from a state change on the same
  /// artifact — else the per-artifact derivation. Both are capped at 64 bytes
  /// from the left, so the artifact survives and the org prefix is what goes.
  String get collapseId {
    final routed = collapseKey;
    if (routed != null) return routed;
    final id = '$org.${artifactType.name}.$artifactId';
    return id.length <= maxCollapseKey ? id : id.substring(id.length - maxCollapseKey);
  }

  /// FCM allows four collapse keys per device at a time, so Android collapses
  /// by **family** and uses the exact key only as the notification tag
  /// (research/14 §3.3).
  String get collapseFamily => artifactType.family;

  /// The heading the phone shows (research/14 §3.1): the artifact line, which
  /// is the [title] the relay already prefixed with `#id` or `!id`.
  String get notificationTitle {
    if (eventType == 'boardhop.test') return 'Boardhop';
    return title ?? '$_artifactLabel $artifactId';
  }

  /// iOS subtitle / Android sub-text: the project, nothing else. The pointer
  /// does not carry a repository name, so a PR shows its project.
  String? get notificationSubtitle => project.isEmpty ? null : project;

  /// The body line (research/14 §3.1): `{actor} {verb phrase}`, or the phrase
  /// alone for a service identity. A pointer with no verb — only the test push
  /// and anything malformed — falls back to naming the artifact.
  String get notificationBody {
    final v = verb;
    if (v == null) return title ?? '$_artifactLabel $artifactId in $project';
    return verbPhrase(v, actor: actor, detail: detail, artifactRef: artifactType.ref(artifactId));
  }

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
    if (actor != null) 'actor': actor!,
    if (actorId != null) 'actorId': actorId!,
    if (verb != null) 'verb': verb!.name,
    if (detail != null) 'detail': detail!,
    if (anchor != null) 'anchor': anchor!,
    if (runId != null) 'runId': runId!,
    if (subId != null) 'subId': subId!,
    if (sentAt != null) 'sentAt': sentAt!.toIso8601String(),
  };

  /// How many bytes [toData] costs on the wire. APNs and FCM both cap a
  /// payload at 4 KB and research/14 §3.2 keeps the pointer under 1 KB; a test
  /// pins the longest legal pointer against [dataBudget].
  int get dataBytes => utf8.encode(jsonEncode(toData())).length;

  /// research/14 §3.2: "the pointer stays well under 1 KB".
  static const dataBudget = 1024;

  /// Parses the pointer half of a request body. Returns null when a required
  /// field is missing or the artifact type is not one of the four; a `verb`,
  /// `detail`, `anchor` or `sentAt` this relay does not recognise is dropped
  /// rather than taken, so one bad field cannot break routing.
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
      actor: json['actor'] as String?,
      actorId: json['actorId'] as String?,
      verb: Verb.tryParse(json['verb'] as String?),
      detail: json['detail'] as String?,
      anchor: json['anchor'] as String?,
      runId: json['runId'] as String?,
      subId: json['subId'] as String?,
      collapseKey: json['collapseKey'] as String?,
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? ''),
    );
  }

  @override
  String toString() =>
      'PushPointer($org/$project ${artifactType.name}/$artifactId $eventType ${verb?.name ?? 'noVerb'})';
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
