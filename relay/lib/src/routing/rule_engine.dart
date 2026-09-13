import '../gateway/pointer.dart';
import '../hooks/hook_event.dart';
import '../hooks/hook_kind.dart';
import '../hooks/routing_view.dart';
import '../log.dart';
import '../verb.dart';
import 'approval_rules.dart';
import 'build_rules.dart';
import 'candidate.dart';
import 'links.dart';
import 'notification.dart';
import 'prefs.dart';
import 'pull_request_rules.dart';
import 'routing_state.dart';
import 'send_ledger.dart';
import 'sink.dart';
import 'work_item_rules.dart';

/// The audience engine (research/14 §2 and §5.2): one service-hook event in,
/// zero or more [Notification]s out.
///
/// The pipeline is fixed and every step is small enough to test on its own:
///
/// 1. **rules** — the family's pure function turns the [RoutingView] into
///    candidates, reading and then advancing the per-artifact state;
/// 2. **actor** — whoever caused it is removed from the audience, except for
///    builds and a lone self-approver (§5.2 rule 1);
/// 3. **collapse** — several candidates for one person become the one with the
///    highest [Verb.priority] (rule 2);
/// 4. **preferences** — each person's own settings and quiet hours (§6);
/// 5. **caps** — 50 recipients per event, 60 per person per hour (rule 6);
/// 6. **sink** — one notification per distinct (verb, detail, anchor).
///
/// No network call happens here, and nothing from a body is written or logged:
/// the title, the actor's display name and the detail exist only inside the
/// in-flight [Notification].
class RuleEngine implements HookProcessor {
  RuleEngine({
    required this.state,
    required this.prefs,
    required this.sink,
    required this.sends,
    this.maxRecipientsPerEvent = maxFanOut,
    this.maxPerUserPerHour = maxPerUserHourly,
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  /// research/14 §5.2 rule 6: a PR with 60 reviewers is a distribution list.
  static const maxFanOut = 50;

  /// …and nobody needs more than one notification a minute from one org.
  static const maxPerUserHourly = 60;

  final RoutingState state;
  final PrefsSource prefs;
  final NotificationSink sink;
  final SendLedger sends;
  final int maxRecipientsPerEvent;
  final int maxPerUserPerHour;
  final DateTime Function() _clock;

  static DateTime _utcNow() => DateTime.now().toUtc();

  @override
  Future<void> process(HookEvent event) async {
    final view = event.view;
    final now = _clock();
    final actor = _actorOf(view);
    final candidates = _evaluate(view);

    final artifactId = view.artifactId;
    final type = artifactTypeOf(view.kind);
    var dropped = 0;
    var throttled = 0;
    var capped = 0;

    final chosen = <String, Candidate>{};
    if (artifactId != null) {
      for (final candidate in _withoutActor(view, candidates, actor.id)) {
        final existing = chosen[candidate.userId];
        // research/14 §5.2 rule 2: one notification per person per event, and
        // the loudest verb wins.
        if (existing == null || candidate.verb.priority > existing.verb.priority) {
          chosen[candidate.userId] = candidate;
        }
      }
    }

    final artifactKey = artifactId == null ? null : '${artifactPrefix(type)}.$artifactId';
    final allowed = <Candidate>[];
    for (final candidate in chosen.values) {
      final settings = prefs.prefsFor(view.org, candidate.userId);
      if (!settings.allows(
        candidate.verb,
        reason: candidate.reason,
        detail: candidate.detail,
        artifactKey: artifactKey,
      )) {
        dropped++;
        continue;
      }
      // "Quiet, not lost" (§5.2 rule 7): a suppressed notification is dropped,
      // not queued. Approvals are exempt by default, which the preferences
      // decide (D5), not this loop.
      if (settings.quietHoursSuppress(candidate.verb, now, prefs.timeZoneOffsetMinutes(view.org, candidate.userId))) {
        dropped++;
        continue;
      }
      allowed.add(candidate);
    }

    final eventKey = _eventKeyOf(event);
    final recipients = <Candidate>[];
    for (final candidate in allowed) {
      if (recipients.length >= maxRecipientsPerEvent) {
        capped++;
        continue;
      }
      final since = now.subtract(const Duration(hours: 1));
      if (sends.countSince(org: view.org, userId: candidate.userId, since: since) >= maxPerUserPerHour) {
        throttled++;
        continue;
      }
      if (!sends.claim(org: view.org, eventKey: eventKey, userId: candidate.userId, at: now)) {
        // Already notified about this event: a replay, or a rule that ran twice.
        continue;
      }
      recipients.add(candidate);
    }

    logEvent(
      'hook routed',
      fields: {
        ...view.toLogFields(),
        'candidates': candidates.length,
        'recipients': recipients.length,
        if (dropped > 0) 'dropped': dropped,
        if (throttled > 0) 'throttled': throttled,
        if (capped > 0) 'capped': capped,
        'lagMs': now.difference(event.receivedAt).inMilliseconds,
      },
    );
    if (recipients.isEmpty || artifactId == null) return;

    for (final notification in _group(view, eventKey, type, artifactId, actor, recipients)) {
      await sink.deliver(notification);
    }
  }

  /// One notification per distinct (verb, detail, anchor): a comment that
  /// mentions somebody produces two, "mentioned you" and "commented on".
  List<Notification> _group(
    RoutingView view,
    String eventKey,
    PushArtifactType type,
    String artifactId,
    ResolvedActor actor,
    List<Candidate> recipients,
  ) {
    final groups = <String, List<Candidate>>{};
    for (final candidate in recipients) {
      final key = '${candidate.verb.name}|${candidate.detail ?? ''}|${candidate.anchor ?? ''}';
      (groups[key] ??= []).add(candidate);
    }
    final project = projectSegment(view, state.projectName);
    return [
      for (final group in groups.values)
        Notification(
          org: view.org,
          kind: view.kind,
          eventKey: eventKey,
          artifactType: type,
          artifactId: artifactId,
          projectId: view.projectId,
          projectName: project,
          title: titleFor(type, artifactId, view.title),
          actorId: actor.id,
          actorName: actor.name,
          verb: group.first.verb,
          detail: group.first.detail,
          anchor: group.first.anchor,
          runId: view.runId,
          subId: view.subId,
          deepLink: deepLinkFor(
            kind: view.kind,
            type: type,
            artifactId: artifactId,
            project: project,
            runId: view.runId,
            anchor: group.first.anchor,
          ),
          collapseKey: collapseKeyFor(view.org, type, artifactId, group.first.anchor),
          recipients: {for (final candidate in group) candidate.userId},
        ),
    ];
  }

  /// research/14 §5.2 rule 1, with its two exceptions: a build always reaches
  /// the person who caused it, and so does the only approver of their own run.
  Iterable<Candidate> _withoutActor(RoutingView view, List<Candidate> candidates, String? actorId) {
    if (actorId == null || view.kind.isBuild) return candidates;
    if (view.kind == HookKind.approvalPending && candidates.length == 1 && candidates.single.userId == actorId) {
      return candidates;
    }
    return candidates.where((candidate) => candidate.userId != actorId);
  }

  List<Candidate> _evaluate(RoutingView view) {
    if (view.kind.isWorkItem) return evaluateWorkItem(view, state);
    if (view.kind.isPullRequest) return evaluatePullRequest(view, state);
    if (view.kind.isBuild) return evaluateBuild(view, state);
    if (view.kind.isApproval) return evaluateApproval(view, state);
    return evaluatePipelineState(view, state);
  }

  ResolvedActor _actorOf(RoutingView view) {
    if (view.kind.isWorkItem) return workItemActor(view, state);
    if (view.kind.isPullRequest) return pullRequestActor(view, state);
    if (view.kind.isBuild) return buildActor(view, state);
    if (view.kind.isApproval) return approvalActor(view, state);
    return noActor;
  }

  /// What "this event" means to the send ledger. `X-VSS-ActivityId` is unique
  /// per delivery attempt and the ingest has already deduped on it, so it is
  /// also the right key for "this person has been told about this".
  static String _eventKeyOf(HookEvent event) =>
      event.activityId ??
      '${event.kind.label}:${event.view.artifactId ?? '-'}:${event.receivedAt.microsecondsSinceEpoch}';
}
