import '../gateway/pointer.dart';
import '../hooks/hook_kind.dart';
import '../hooks/routing_view.dart';
import 'candidate.dart';

/// The artifact family a hook kind points at.
PushArtifactType artifactTypeOf(HookKind kind) {
  if (kind.isWorkItem) return PushArtifactType.workItem;
  if (kind.isPullRequest) return PushArtifactType.pullRequest;
  if (kind.isApproval) return PushArtifactType.approval;
  return PushArtifactType.build;
}

/// The prefix the collapse key, the artifact key, the mute list and FCM's
/// per-family collapse key share. Defined once, on the pointer's own type.
String artifactPrefix(PushArtifactType type) => type.family;

/// research/14 §2's collapse keys: one per artifact, with a thread or comment
/// suffix so a discussion and a state change on the same artifact do not eat
/// each other in the shade.
///
/// **Org-scoped**: a phone registered for two organizations would otherwise
/// collapse `pr.8348` in one against `pr.8348` in the other. Capped from the
/// **left**, because the artifact and its suffix are the distinguishing part —
/// [PushPointer.collapseId] trims the same way.
String collapseKeyFor(String org, PushArtifactType type, String artifactId, String? anchor) {
  final base = '$org.${artifactPrefix(type)}.$artifactId';
  final key = switch (type) {
    PushArtifactType.workItem => Anchors.commentId(anchor) == null ? base : '$base.comments',
    PushArtifactType.pullRequest => Anchors.threadId(anchor) == null ? base : '$base.t${Anchors.threadId(anchor)}',
    _ => base,
  };
  return capCollapseKey(key);
}

/// APNs caps `apns-collapse-id` at 64 bytes; the tail is what identifies the
/// artifact, so an over-long key loses its head.
String capCollapseKey(String key) =>
    key.length <= PushPointer.maxCollapseKey ? key : key.substring(key.length - PushPointer.maxCollapseKey);

/// research/14 §3.1: the alert heading is the artifact line — the id the relay
/// prefixes, then the artifact's own title. Metadata, nothing else.
String? titleFor(PushArtifactType type, String artifactId, String? title) {
  final prefix = switch (type) {
    PushArtifactType.workItem => '#$artifactId',
    PushArtifactType.pullRequest => '!$artifactId',
    // Builds and approvals already read as `definition · number` and
    // `pipeline → stage`, which name themselves.
    _ => null,
  };
  if (prefix == null) return title;
  return title == null || title.isEmpty ? prefix : '$prefix · $title';
}

/// The app's **org-relative** route (research/14 §2's route column). The relay
/// never names an account: `PushPointer.route(accountId)` prefixes `/a/{id}`.
///
/// [project] is a project name where the relay knows one and the project id
/// otherwise — Azure DevOps accepts either in the paths the app builds from it.
String deepLinkFor({
  required HookKind kind,
  required PushArtifactType type,
  required String artifactId,
  String? project,
  String? runId,
  String? anchor,
}) {
  final p = project == null || project.isEmpty ? null : Uri.encodeComponent(project);
  switch (type) {
    case PushArtifactType.pullRequest:
      // The PR route is org-level; the project is informational.
      final base = '/pull-requests/${Uri.encodeComponent(artifactId)}';
      final threadId = Anchors.threadId(anchor);
      if (threadId != null) return '$base?thread=${Uri.encodeComponent(threadId)}';
      if (anchor == Anchors.files) return '$base?tab=files';
      return base;
    case PushArtifactType.workItem:
      if (p == null) return _fallback;
      final base = '/projects/$p/work-items/${Uri.encodeComponent(artifactId)}';
      final commentId = Anchors.commentId(anchor);
      return commentId == null ? base : '$base?comment=${Uri.encodeComponent(commentId)}';
    case PushArtifactType.build:
      if (p == null) return _fallback;
      return '/projects/$p/pipelines/runs/${Uri.encodeComponent(artifactId)}';
    case PushArtifactType.approval:
      if (p == null) return _fallback;
      // A decided approval has nothing left to decide, so it opens the run.
      if (kind == HookKind.approvalCompleted && runId != null) {
        return '/projects/$p/pipelines/runs/${Uri.encodeComponent(runId)}';
      }
      return '/projects/$p/pipelines?tab=approvals&approval=${Uri.encodeComponent(artifactId)}';
  }
}

/// Where a notification lands when the relay cannot build a real route
/// (research/14 §4.2).
const _fallback = '/activity';

/// The project the route should name: the payload's own name, else the name
/// the relay has learned for that id, else the id.
String? projectSegment(RoutingView view, String? Function(String org, String projectId) lookup) {
  final name = view.projectName;
  if (name != null && name.isNotEmpty) return name;
  final id = view.projectId;
  if (id == null) return null;
  return lookup(view.org, id) ?? id;
}
