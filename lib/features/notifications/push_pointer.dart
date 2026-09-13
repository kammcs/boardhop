import '../../core/routes.dart';
import 'push_verbs.dart';

/// The pointer the relay pushes (research/06, "Push gateway"; the **v2** fields
/// of research/14 §3.2): ids, an event type, a verb from a closed list and at
/// most one short line — never a comment, a description or a diff.
///
/// This is the app's half of the same contract the relay enforces in
/// `relay/lib/src/gateway/pointer.dart`; the wire form is the `data` map both
/// APNs and FCM carry, whose values are always strings. Every v2 field is
/// optional, so an R1 pointer — and the pointer the relay sends when it knows
/// nothing about the actor — still parses.
class PushPointer {
  const PushPointer({
    required this.org,
    required this.eventType,
    required this.artifactType,
    required this.artifactId,
    required this.project,
    this.title,
    this.deepLink,
    this.actor,
    this.actorId,
    this.verb,
    this.detail,
    this.anchor,
    this.runId,
    this.subId,
    this.sentAt,
    this.collapseKey,
    this.fallbackTitle,
    this.fallbackBody,
    this.fallbackSubtitle,
    this.data = const {},
  });

  /// A pointer older than this is not worth enriching or showing: the app's own
  /// poll has answered it by now (research/14 §3.2, §4.1).
  static const staleAfter = Duration(minutes: 10);

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
      actor: str('actor'),
      actorId: str('actorId'),
      verb: PushVerb.tryParse(str('verb')),
      detail: str('detail'),
      anchor: str('anchor'),
      runId: str('runId'),
      subId: str('subId'),
      sentAt: DateTime.tryParse(str('sentAt') ?? ''),
      collapseKey: str('collapseKey'),
      fallbackTitle: str('fallbackTitle'),
      fallbackBody: str('fallbackBody'),
      fallbackSubtitle: str('fallbackSubtitle'),
      data: {
        for (final entry in data.entries)
          if (entry.value is String && (entry.value as String).isNotEmpty)
            entry.key: entry.value as String,
      },
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

  /// Who did it, as a display name. Absent for a service identity and for the
  /// events whose body names nobody (research/14 §8a).
  final String? actor;

  /// The actor's identity GUID.
  final String? actorId;

  /// What they did; the app turns it into words ([pushVerbPhrase]).
  final PushVerb? verb;

  /// The verb's own metadata: a state name, a vote label, a build result.
  final String? detail;

  /// `comment:{id}`, `thread:{id}`, `approval:{id}` or `tab:files`
  /// (research/14 §3.2); [route] turns it into a query string.
  final String? anchor;

  /// Approvals only: the run the approval belongs to.
  final String? runId;

  /// The hook subscription that produced it. Support only, never shown.
  final String? subId;

  /// When the relay sent it, so a pointer that sat in a queue is not shown.
  final DateTime? sentAt;

  /// The routed collapse key (`contoso.pr.8348.t4821`); [tag] falls back to the
  /// per-artifact derivation.
  final String? collapseKey;

  /// The heading, body and sub-text the relay already composed (research/14
  /// §3.1). The app prefers them so that the line the OS shows is the same one
  /// the relay would have shown, whatever the app's own vocabulary says.
  final String? fallbackTitle;
  final String? fallbackBody;
  final String? fallbackSubtitle;

  /// The wire map this pointer was read from, so a background-posted
  /// notification can carry it as its payload and a tap routes exactly like a
  /// foreground one.
  final Map<String, String> data;

  /// The short family the collapse keys and the mute list share: `wi`, `pr`,
  /// `build`, `approval`.
  String get family => switch (artifactType) {
    'workItem' => 'wi',
    'pullRequest' => 'pr',
    'build' => 'build',
    'approval' => 'approval',
    _ => 'other',
  };

  /// How the artifact is written in a sentence: `#15545`, `!8348`. Builds and
  /// approvals name themselves in the title, so they have no reference.
  String? get artifactRef => switch (artifactType) {
    'workItem' => '#$artifactId',
    'pullRequest' => '!$artifactId',
    _ => null,
  };

  /// True when the pointer is older than [staleAfter]: nothing is posted for
  /// it, because the app's own feed has it by now.
  bool get isStale => isStaleAt(DateTime.now());

  bool isStaleAt(DateTime now) {
    final sent = sentAt;
    if (sent == null) return false;
    return now.toUtc().difference(sent.toUtc()) > staleAfter;
  }

  /// The in-app route for one signed-in account.
  ///
  /// A `deepLink` that already names an account is taken as it is; anything
  /// else is built from the ids, so the relay can never steer the app at a
  /// route belonging to another account. The [anchor] is appended as a query
  /// string (research/14 §4.2); the pages read it from R2.5 on, and go_router
  /// ignores a query parameter no page asks for.
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
    if (byType == null) return Routes.activity(accountId, org);
    final query = anchorQuery;
    return query == null ? byType : '$byType?$query';
  }

  /// The [anchor] as a query string, or null when there is none to add.
  ///
  /// `comment:{id}` → `comment={id}`, `thread:{id}` → `thread={id}`,
  /// `tab:files` → `tab=files`, `approval:{id}` → `tab=approvals&approval={id}`
  /// (research/14 §4.2).
  ///
  /// The approval anchor carries the run as well when the pointer knows it
  /// (research/14 §2.4: the approval's `owner.id` **is** the run id), because
  /// an approval someone else already decided is no longer in the tab's list
  /// and the page then offers "Open run" instead (R2.5).
  String? get anchorQuery {
    final value = anchor;
    if (value == null) return null;
    final colon = value.indexOf(':');
    if (colon <= 0 || colon == value.length - 1) return null;
    final kind = value.substring(0, colon);
    final id = Uri.encodeQueryComponent(value.substring(colon + 1));
    final run = runId;
    return switch (kind) {
      'comment' => 'comment=$id',
      'thread' => 'thread=$id',
      'tab' => 'tab=$id',
      'approval' =>
        'tab=approvals&approval=$id'
            '${run == null ? '' : '&run=${Uri.encodeQueryComponent(run)}'}',
      _ => null,
    };
  }

  /// Heading and body for the notification the app posts, matching what the
  /// relay put in the alert so a pushed notification reads the same whether the
  /// app was open, backgrounded or closed.
  ///
  /// The relay's own `fallbackTitle` / `fallbackBody` win when they are there;
  /// otherwise the app composes the line itself from the verb, and an R1
  /// pointer with neither falls back to naming the artifact.
  (String, String) get message => (heading, body);

  String get heading =>
      fallbackTitle ??
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
        'ms.vss-pipelines.stage-state-changed-event' =>
          'Pipeline stage changed',
        'ms.vss-pipelinechecks-events.approval-pending' =>
          'Approval waiting for you',
        _ => switch (artifactType) {
          'workItem' => 'Work item',
          'pullRequest' => 'Pull request',
          'build' => 'Build',
          'approval' => 'Approval',
          _ => 'Boardhop',
        },
      };

  String get body {
    final fallback = fallbackBody;
    if (fallback != null) return fallback;
    final v = verb;
    if (v != null) {
      return pushVerbPhrase(
        v,
        actor: actor,
        detail: detail,
        artifactRef: artifactRef,
      );
    }
    return title ??
        '$_label $artifactId${project.isEmpty ? '' : ' in $project'}';
  }

  /// iOS subtitle / Android sub-text: the project, nothing more.
  String? get subtitle {
    final fallback = fallbackSubtitle;
    if (fallback != null) return fallback;
    return project.isEmpty ? null : project;
  }

  String get _label => switch (artifactType) {
    'workItem' => 'Work item',
    'pullRequest' => 'Pull request',
    'build' => 'Build',
    'approval' => 'Approval for',
    _ => 'Item',
  };

  /// The Android notification tag: the relay's collapse key when it sent one —
  /// it separates a comment thread from a state change on the same artifact —
  /// else the per-artifact derivation.
  String get tag => collapseKey ?? '$org.$artifactType.$artifactId';

  /// `setGroup`: the artifact family within the organization, so a phone
  /// registered for two organizations never groups two of them together
  /// (research/14 §4.1).
  String get groupKey => '$org.$family';

  /// Stable per [tag], so repeated events on one artifact (or one thread)
  /// replace each other in the shade instead of stacking.
  int get notificationId {
    final key = collapseKey;
    if (key != null) return key.hashCode & 0x7fffffff;
    return Object.hash(org, artifactType, artifactId) & 0x7fffffff;
  }

  /// The feed key the Activity list dedups on (`pr:8336`, `wi:15503`,
  /// `build:4242`), so a pushed item and the next poll's copy are one row.
  ///
  /// An approval belongs to a run, and the feed's vocabulary has no key of its
  /// own for one, so it takes its run's: the approval and the run it gates are
  /// one row. An approval whose pointer carries no `runId` — and the test push
  /// — get no feed row at all.
  String? get activityKey => switch (artifactType) {
    'workItem' => 'wi:$artifactId',
    'pullRequest' => 'pr:$artifactId',
    'build' => 'build:$artifactId',
    'approval' when runId != null => 'build:$runId',
    _ => null,
  };
}
