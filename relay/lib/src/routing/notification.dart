import '../gateway/pointer.dart';
import '../hooks/hook_kind.dart';
import '../verb.dart';

/// One notification, addressed to everybody who should get exactly this line.
///
/// This is what the rule engine produces and what R2.3 turns into a
/// [PushPointer] per device. Everything on it is metadata: ids, an artifact
/// title, an actor's display name, a closed-vocabulary detail and a route.
/// Comment bodies, descriptions, field values and diffs never reach it, and
/// the two content-adjacent fields ([title] and [actorName]) exist **only**
/// inside this object — they are never stored and never logged.
class Notification {
  Notification({
    required this.org,
    required this.kind,
    required this.eventKey,
    required this.artifactType,
    required this.artifactId,
    required this.verb,
    required this.deepLink,
    required this.collapseKey,
    required Set<String> recipients,
    this.projectId,
    this.projectName,
    String? title,
    this.actorId,
    String? actorName,
    String? detail,
    this.anchor,
    this.runId,
    this.subId,
    DateTime? sentAt,
  }) : title = truncate(title, maxTitle),
       actorName = truncate(actorName, maxActorName),
       detail = verb.sanitizeDetail(detail),
       recipients = Set.unmodifiable(recipients),
       sentAt = sentAt ?? DateTime.now().toUtc();

  /// research/14 §3.1: the alert heading is the artifact line and nothing else.
  static const maxTitle = PushPointer.maxTitle;

  /// research/14 §3.2: `actor` is a display name, capped.
  static const maxActorName = 60;

  final String org;

  /// Which subscription family produced it; the event type comes from here.
  final HookKind kind;

  /// The delivery this notification belongs to. Two notifications from one
  /// event share it, which is how "one notification per person per event" is
  /// enforced in the send ledger.
  final String eventKey;

  final PushArtifactType artifactType;
  final String artifactId;
  final String? projectId;
  final String? projectName;

  /// `#15545 · Fix the snackbar`, `!8334 · …`, `def · number`,
  /// `pipeline → stage` (research/14 §3.1). Metadata, ≤ [maxTitle].
  final String? title;

  final String? actorId;

  /// The actor's display name, ≤ [maxActorName]. Null for a service identity,
  /// and null when the payload does not name the actor at all (a PR vote, a
  /// reviewer list change and a PR status change all arrive without one).
  final String? actorName;

  final Verb verb;

  /// Closed-vocabulary or length-capped metadata the verb needs; see
  /// [Verb.sanitizeDetail].
  final String? detail;

  /// `comment:{id}`, `thread:{id}`, `approval:{id}` or `tab:files`.
  final String? anchor;

  /// Approvals only: the run the approval belongs to.
  final String? runId;

  /// The hook subscription that produced it, for support (research/14 §3.2).
  final String? subId;

  /// The app's **org-relative** route. The relay never names an account.
  final String deepLink;

  /// APNs `apns-collapse-id` / `thread-id`, FCM tag: `wi.{id}`,
  /// `wi.{id}.comments`, `pr.{id}`, `pr.{id}.t{threadId}`, `build.{id}`,
  /// `approval.{id}` (research/14 §2).
  final String collapseKey;

  /// Identity ids. Devices are looked up per id in R2.3.
  final Set<String> recipients;

  final DateTime sentAt;

  /// Ids, counts and the verb: what may be written to a log line. Never
  /// [title], never [actorName], never [detail].
  Map<String, Object?> toLogFields() => {
    'org': org,
    'kind': kind.label,
    'eventKey': eventKey,
    'artifact': '${artifactType.name}/$artifactId',
    if (projectId != null) 'projectId': projectId,
    'verb': verb.name,
    if (anchor != null) 'anchor': anchor,
    'collapseKey': collapseKey,
    if (actorId != null) 'actorId': actorId,
    if (runId != null) 'runId': runId,
    if (subId != null) 'subId': subId,
    'recipients': recipients.length,
  };

  @override
  String toString() =>
      'Notification(${kind.label} ${artifactType.name}/$artifactId ${verb.name} → ${recipients.length})';

  /// Trims and truncates with an ellipsis, or null for nothing worth keeping.
  static String? truncate(String? value, int max) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length <= max) return trimmed;
    return '${trimmed.substring(0, max - 1)}…';
  }
}
