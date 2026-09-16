import 'package:flutter/material.dart';

import '../../../data/models/pr_check.dart';
import '../../../data/models/pull_request.dart';
import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import '../../work_items/widgets/work_item_visuals.dart';
import 'conflicts_list.dart';
import 'pr_visuals.dart';

/// The one action the merge box offers, chosen by the pull request's state
/// (R2). Null — no action at all — is a completed pull request, one whose
/// auto-complete is already set (the banner owns Cancel), and one that is
/// blocked on a target with no blocking policy to auto-complete against.
enum PrPrimaryAction {
  complete('Complete', Icons.merge_type),
  setAutoComplete('Set auto-complete', Icons.schedule_send),
  publish('Publish', Icons.publish),
  reactivate('Reactivate', Icons.restart_alt);

  const PrPrimaryAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Whether the pull request's own merge evaluation is out of the way.
///
/// `notSet` is what the service answers before it has looked; a pull
/// request that has never been evaluated is not treated as blocked, but
/// `queued` (still merging) and `conflicts` are.
bool prMergeReady(PullRequest pr) => switch (pr.mergeStatus) {
  null || '' || 'succeeded' || 'notSet' => true,
  _ => false,
};

/// A blocking policy or status that has not passed yet.
bool prHasUnmetBlocking(List<PrCheck> checks) => checks.any(
  (c) =>
      c.isBlocking &&
      (c.state == PrCheckState.failed ||
          c.state == PrCheckState.pending ||
          c.state == PrCheckState.error),
);

/// R2's state machine, kept out of the widget so the states are testable
/// without a pump.
PrPrimaryAction? prPrimaryAction({
  required PullRequest pr,
  required PrPolicySet? policies,
  List<PrCheck> checks = const [],
}) {
  if (pr.status == 'completed') return null;
  if (pr.status == 'abandoned') return PrPrimaryAction.reactivate;
  // A draft cannot merge at all; publishing it is the only way forward.
  if (pr.isDraft) return PrPrimaryAction.publish;
  // Already waiting on the service: the banner offers Cancel instead.
  if (pr.isAutoCompleteSet) return null;
  if (prMergeReady(pr) && !prHasUnmetBlocking(checks)) {
    return PrPrimaryAction.complete;
  }
  // Without a blocking policy the service merges the moment auto-complete
  // lands (research/22 §1), which is not what the button says it does.
  if (policies?.hasBlocking ?? false) return PrPrimaryAction.setAutoComplete;
  return null;
}

/// The reviewer behind an identity GUID, matched without regard to case:
/// a policy's `requiredReviewerIds` and a reviewer's `id` are the same GUID
/// but the service does not always spell them the same way (research/22 §1
/// makes the same point about the work item artifact url).
PrReviewer? reviewerByGuid(PullRequest pr, String guid) {
  final wanted = guid.toLowerCase();
  for (final r in pr.reviewers) {
    if (r.id.toLowerCase() == wanted) return r;
  }
  return null;
}

/// The rows the merge box lists: every evaluated check, plus any blocking
/// policy on the target that produced no evaluation, with `isBlocking`
/// corrected from the policy read (an evaluation of a policy scoped by
/// prefix sometimes comes back without it).
List<PrCheck> mergePolicyRows(List<PrCheck> checks, PrPolicySet? policies) {
  if (policies == null) return checks;
  final blocking = <String>{
    for (final p in policies.policies)
      if (p.isBlocking && p.displayName.isNotEmpty) p.displayName.toLowerCase(),
  };
  final out = <PrCheck>[
    for (final c in checks)
      if (!c.isBlocking && blocking.contains(c.name.toLowerCase()))
        PrCheck(
          name: c.name,
          state: c.state,
          detail: c.detail,
          isBlocking: true,
          url: c.url,
        )
      else
        c,
  ];
  final seen = {for (final c in out) c.name.toLowerCase()};
  for (final p in policies.policies) {
    if (!p.isBlocking || p.displayName.isEmpty) continue;
    if (!seen.add(p.displayName.toLowerCase())) continue;
    out.add(
      PrCheck(
        name: p.displayName,
        state: PrCheckState.notApplicable,
        detail: 'Not evaluated yet',
        isBlocking: true,
      ),
    );
  }
  return out;
}

/// One status block on the Overview (R2): the merge state with its
/// conflicts, every policy and status with blocking ones first, the target's
/// required reviewers and their votes, and the one action the state allows.
///
/// It replaces the first pass's Checks section, which said nothing about
/// what to do next.
class MergeBox extends StatelessWidget {
  const MergeBox({
    super.key,
    required this.pr,
    required this.checks,
    required this.policies,
    required this.conflicts,
    required this.requiredReviewers,
    required this.onPrimary,
    this.busy = false,
  });

  final PullRequest pr;
  final List<PrCheck> checks;

  /// The target branch's policies, or null when the read was refused (a
  /// client project often is): the box then shows what it has.
  final PrPolicySet? policies;

  /// Read only while `mergeStatus` is `conflicts`.
  final List<PrConflict> conflicts;

  /// Names for the identity GUIDs a "Required reviewers" policy carries,
  /// resolved by the page through `PeopleRepository.identityById`. A GUID
  /// with no answer is shown as its own short form rather than dropped.
  final Map<String, IdentityRef> requiredReviewers;

  final ValueChanged<PrPrimaryAction> onPrimary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = mergePolicyRows(checks, policies);
    final required = [
      for (final c in rows)
        if (c.isBlocking) c,
    ];
    final optional = [
      for (final c in rows)
        if (!c.isBlocking) c,
    ];
    final merge = mergeStatusLabel(context, pr.mergeStatus);
    final blocked = required
        .where(
          (c) =>
              c.state == PrCheckState.failed || c.state == PrCheckState.error,
        )
        .length;
    final action = prPrimaryAction(pr: pr, policies: policies, checks: rows);
    final reviewerIds = policies?.requiredReviewerIds ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MergeTitle('Merge${blocked > 0 ? ' · $blocked blocking' : ''}'),
        if (merge != null)
          ListTile(
            dense: true,
            leading: Icon(
              pr.mergeStatus == 'succeeded'
                  ? Icons.check_circle
                  : Icons.warning_amber,
              color: merge.$2,
            ),
            title: Text(merge.$1),
            subtitle: switch (pr.mergeFailureMessage) {
              final String m when m.isNotEmpty => Text(m),
              _ =>
                pr.hasMultipleMergeBases
                    ? const Text('The branches have more than one merge base.')
                    : null,
            },
          ),
        if (conflicts.isNotEmpty) ConflictsList(conflicts: conflicts),
        for (final c in [...required, ...optional]) _CheckRow(check: c),
        if (reviewerIds.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.sm,
              Spacing.lg,
              0,
            ),
            child: Text(
              'Required by policy',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final id in reviewerIds)
            _RequiredReviewerRow(
              identity: requiredReviewers[id.toLowerCase()],
              guid: id,
              reviewer: reviewerByGuid(pr, id),
            ),
        ],
        if (action != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.lg,
              Spacing.sm,
            ),
            child: FilledButton.icon(
              onPressed: busy ? null : () => onPrimary(action),
              icon: Icon(action.icon),
              label: Text(action.label),
            ),
          ),
      ],
    );
  }
}

class _MergeTitle extends StatelessWidget {
  const _MergeTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Spacing.lg,
      Spacing.lg,
      Spacing.lg,
      Spacing.sm,
    ),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final PrCheck check;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(
        checkIcon(check.state, isBlocking: check.isBlocking),
        color: checkColor(context, check.state, isBlocking: check.isBlocking),
      ),
      title: Text(check.name),
      subtitle: check.detail == null || check.detail!.isEmpty
          ? null
          : Text(check.detail!),
      // "optional" is said out loud on a failing policy that does not
      // block: the absence of "required" was easy to miss next to a red
      // row (iPhone walkthrough, finding k).
      trailing: Text(
        check.isBlocking
            ? 'required'
            : (check.state == PrCheckState.failed ? 'optional' : ''),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A reviewer the target's policy demands, with the vote they have cast so
/// far — the NEXT-STEPS item 8 gap ("required-reviewer names in Checks").
class _RequiredReviewerRow extends StatelessWidget {
  const _RequiredReviewerRow({
    required this.guid,
    required this.identity,
    required this.reviewer,
  });

  final String guid;
  final IdentityRef? identity;
  final PrReviewer? reviewer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vote = reviewer?.vote ?? PrVote.none;
    final name =
        identity?.displayName ??
        reviewer?.displayName ??
        (guid.length > 8 ? '${guid.substring(0, 8)}…' : guid);
    return ListTile(
      dense: true,
      leading: identity == null && reviewer == null
          ? Icon(Icons.person_outline, color: scheme.onSurfaceVariant)
          : IdentityAvatar(
              identity: identity ?? reviewer!.identity,
              radius: 14,
            ),
      title: Text(name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        reviewer == null ? 'Not a reviewer yet' : vote.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(voteIcon(vote), color: voteColor(context, vote)),
    );
  }
}
