import 'verb.dart';

/// One person a rule selected, with what to tell them.
///
/// Rules produce candidates; the engine drops the actor, collapses several
/// candidates for one person down to the highest-priority verb, applies
/// preferences and the caps, and only then builds notifications.
typedef Candidate = ({String userId, Verb verb, String? detail, String? anchor});

Candidate candidate(String userId, Verb verb, {String? detail, String? anchor}) =>
    (userId: userId, verb: verb, detail: detail, anchor: anchor);

/// Who caused the event, when the payload says. `null` for the events whose
/// body names nobody: a PR vote (no `votedBy`), a reviewer list change and a
/// PR status change (no `closedBy`, verified in the w24 key trees).
typedef ResolvedActor = ({String? id, String? name});

const ResolvedActor noActor = (id: null, name: null);

/// research/14 §3.2: the anchor the app scrolls to, made explicit next to the
/// deep link's query.
abstract final class Anchors {
  static String comment(String commentId) => 'comment:$commentId';

  static String thread(String threadId) => 'thread:$threadId';

  static String approval(String approvalId) => 'approval:$approvalId';

  /// The PR's Files tab, where a new push is worth looking at.
  static const files = 'tab:files';

  /// The comment id in a `comment:{id}` anchor, or null.
  static String? commentId(String? anchor) =>
      anchor != null && anchor.startsWith('comment:') ? anchor.substring('comment:'.length) : null;

  static String? threadId(String? anchor) =>
      anchor != null && anchor.startsWith('thread:') ? anchor.substring('thread:'.length) : null;

  static String? approvalId(String? anchor) =>
      anchor != null && anchor.startsWith('approval:') ? anchor.substring('approval:'.length) : null;
}
