/// The routing label of one service-hook subscription (research/14 §1).
///
/// `git.pullrequest.updated` fires for reviewer votes, reviewer list changes,
/// status changes and new pushes with no "what changed" field in the body, so
/// the relay subscribes four times with the publisher's `notificationType`
/// filter and learns the kind from the subscription id rather than by diffing
/// state. Every other event maps one-to-one.
enum HookKind {
  prCreated('pr.created', 'git.pullrequest.created'),
  prUpdatedPush('pr.updated.push', 'git.pullrequest.updated', notificationType: 'PushNotification'),
  prUpdatedReviewers(
    'pr.updated.reviewers',
    'git.pullrequest.updated',
    notificationType: 'ReviewersUpdateNotification',
  ),
  prUpdatedStatus('pr.updated.status', 'git.pullrequest.updated', notificationType: 'StatusUpdateNotification'),
  prUpdatedVote('pr.updated.vote', 'git.pullrequest.updated', notificationType: 'ReviewerVoteNotification'),
  prComment('pr.comment', 'ms.vss-code.git-pullrequest-comment-event'),
  prMerged('pr.merged', 'git.pullrequest.merged'),
  wiCreated('wi.created', 'workitem.created'),
  wiUpdated('wi.updated', 'workitem.updated'),
  wiCommented('wi.commented', 'workitem.commented'),
  buildComplete('build.complete', 'build.complete'),
  runState('run.state', 'ms.vss-pipelines.run-state-changed-event'),
  stageState('stage.state', 'ms.vss-pipelines.stage-state-changed-event'),
  approvalPending('approval.pending', 'ms.vss-pipelinechecks-events.approval-pending'),
  approvalCompleted('approval.completed', 'ms.vss-pipelinechecks-events.approval-completed');

  const HookKind(this.label, this.eventType, {this.notificationType});

  /// What is stored in `hook_subscriptions.kind` and what the rules switch on.
  final String label;

  /// The Azure DevOps event id the subscription is created for.
  final String eventType;

  /// The `notificationType` filter input, for the four PR update kinds only.
  final String? notificationType;

  bool get isWorkItem => eventType.startsWith('workitem.');

  bool get isPullRequest =>
      eventType.startsWith('git.pullrequest.') || eventType == 'ms.vss-code.git-pullrequest-comment-event';

  bool get isBuild => this == HookKind.buildComplete;

  bool get isApproval => this == HookKind.approvalPending || this == HookKind.approvalCompleted;

  /// `run-state-changed` and `stage-state-changed`: the two events that only
  /// feed relay state and never notify.
  bool get isPipelineState => this == HookKind.runState || this == HookKind.stageState;

  /// The label as stored; null for anything the relay does not route.
  static HookKind? tryParse(String? label) {
    if (label == null) return null;
    for (final kind in values) {
      if (kind.label == label) return kind;
    }
    return null;
  }

  /// The kind a subscription for [eventType] with the `notificationType` filter
  /// [notificationType] produces. An empty or absent filter means "any", which
  /// only resolves for events that have a single kind — subscribing to
  /// `git.pullrequest.updated` unfiltered is deliberately not routable.
  static HookKind? fromEventTypeAndFilter(String eventType, String? notificationType) {
    final wanted = (notificationType == null || notificationType.isEmpty) ? null : notificationType;
    for (final kind in values) {
      if (kind.eventType == eventType && kind.notificationType == wanted) return kind;
    }
    // A filter value this relay does not know, on an event that takes only one
    // kind: the filter narrows nothing that matters to routing.
    for (final kind in values) {
      if (kind.eventType == eventType && kind.notificationType == null) return kind;
    }
    return null;
  }
}
