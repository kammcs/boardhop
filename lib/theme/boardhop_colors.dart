import 'package:flutter/material.dart';

/// Domain colors for Azure DevOps entities, provided as a theme extension so
/// widgets read them through `Theme.of(context)` and get the right variant
/// in light and dark mode.
///
/// Usage: `final colors = context.boardhopColors;`
///
/// These follow the hues Azure DevOps users already know (bug red, task
/// yellow, story blue, feature purple, epic orange) but are re-tuned for
/// contrast on our surfaces rather than copied.
@immutable
class BoardhopColors extends ThemeExtension<BoardhopColors> {
  const BoardhopColors({
    required this.bug,
    required this.task,
    required this.userStory,
    required this.feature,
    required this.epic,
    required this.issue,
    required this.testCase,
    required this.stateProposed,
    required this.stateInProgress,
    required this.stateResolved,
    required this.stateCompleted,
    required this.stateRemoved,
    required this.prActive,
    required this.prCompleted,
    required this.prAbandoned,
    required this.prDraft,
    required this.voteApproved,
    required this.voteApprovedWithSuggestions,
    required this.voteWaiting,
    required this.voteRejected,
    required this.runSucceeded,
    required this.runFailed,
    required this.runPartial,
    required this.runCanceled,
    required this.runInProgress,
    required this.diffAdded,
    required this.diffRemoved,
    required this.diffAddedBackground,
    required this.diffRemovedBackground,
    required this.codeBackground,
  });

  // Work item types
  final Color bug;
  final Color task;
  final Color userStory;
  final Color feature;
  final Color epic;
  final Color issue;
  final Color testCase;

  // Work item state categories (Azure DevOps state categories, not names)
  final Color stateProposed;
  final Color stateInProgress;
  final Color stateResolved;
  final Color stateCompleted;
  final Color stateRemoved;

  // Pull requests
  final Color prActive;
  final Color prCompleted;
  final Color prAbandoned;
  final Color prDraft;

  // Reviewer votes
  final Color voteApproved;
  final Color voteApprovedWithSuggestions;
  final Color voteWaiting;
  final Color voteRejected;

  // Pipeline runs
  final Color runSucceeded;
  final Color runFailed;
  final Color runPartial;
  final Color runCanceled;
  final Color runInProgress;

  // Diff viewer
  final Color diffAdded;
  final Color diffRemoved;
  final Color diffAddedBackground;
  final Color diffRemovedBackground;
  final Color codeBackground;

  static const light = BoardhopColors(
    bug: Color(0xFFCC293D),
    task: Color(0xFFB8860B),
    userStory: Color(0xFF0B6BCB),
    feature: Color(0xFF7B3FB8),
    epic: Color(0xFFE0700F),
    issue: Color(0xFF9E4A9E),
    testCase: Color(0xFF3C7A3C),
    stateProposed: Color(0xFF6B7280),
    stateInProgress: Color(0xFF0B6BCB),
    stateResolved: Color(0xFFD97706),
    stateCompleted: Color(0xFF2E8B57),
    stateRemoved: Color(0xFF9CA3AF),
    prActive: Color(0xFF0B6BCB),
    prCompleted: Color(0xFF2E8B57),
    prAbandoned: Color(0xFF6B7280),
    prDraft: Color(0xFF6B7280),
    voteApproved: Color(0xFF2E8B57),
    voteApprovedWithSuggestions: Color(0xFF5FA36E),
    voteWaiting: Color(0xFFD97706),
    voteRejected: Color(0xFFCC293D),
    runSucceeded: Color(0xFF2E8B57),
    runFailed: Color(0xFFCC293D),
    runPartial: Color(0xFFD97706),
    runCanceled: Color(0xFF6B7280),
    runInProgress: Color(0xFF0B6BCB),
    diffAdded: Color(0xFF1B7F3B),
    diffRemoved: Color(0xFFB42318),
    diffAddedBackground: Color(0xFFE6F4EA),
    diffRemovedBackground: Color(0xFFFCE8E6),
    codeBackground: Color(0xFFF3F4F6),
  );

  static const dark = BoardhopColors(
    bug: Color(0xFFF2707F),
    task: Color(0xFFE2B84A),
    userStory: Color(0xFF6FB1F5),
    feature: Color(0xFFB88BE8),
    epic: Color(0xFFF5A35C),
    issue: Color(0xFFD98BD9),
    testCase: Color(0xFF7FC27F),
    stateProposed: Color(0xFF9CA3AF),
    stateInProgress: Color(0xFF6FB1F5),
    stateResolved: Color(0xFFF5B54A),
    stateCompleted: Color(0xFF6CCB8A),
    stateRemoved: Color(0xFF6B7280),
    prActive: Color(0xFF6FB1F5),
    prCompleted: Color(0xFF6CCB8A),
    prAbandoned: Color(0xFF9CA3AF),
    prDraft: Color(0xFF9CA3AF),
    voteApproved: Color(0xFF6CCB8A),
    voteApprovedWithSuggestions: Color(0xFF9AD9AA),
    voteWaiting: Color(0xFFF5B54A),
    voteRejected: Color(0xFFF2707F),
    runSucceeded: Color(0xFF6CCB8A),
    runFailed: Color(0xFFF2707F),
    runPartial: Color(0xFFF5B54A),
    runCanceled: Color(0xFF9CA3AF),
    runInProgress: Color(0xFF6FB1F5),
    diffAdded: Color(0xFF7EE0A0),
    diffRemoved: Color(0xFFF59A93),
    diffAddedBackground: Color(0xFF12331C),
    diffRemovedBackground: Color(0xFF3B1714),
    codeBackground: Color(0xFF1B1F27),
  );

  /// Color for a work item type by its Azure DevOps name.
  Color workItemType(String name) => switch (name.toLowerCase()) {
    'bug' => bug,
    'task' => task,
    'user story' || 'product backlog item' || 'requirement' => userStory,
    'feature' => feature,
    'epic' => epic,
    'issue' || 'impediment' => issue,
    'test case' || 'test plan' || 'test suite' => testCase,
    _ => stateProposed,
  };

  /// Color for a state category (`Proposed`, `InProgress`, `Resolved`,
  /// `Completed`, `Removed`) as returned by the work item type states API.
  Color stateCategory(String category) => switch (category.toLowerCase()) {
    'proposed' => stateProposed,
    'inprogress' => stateInProgress,
    'resolved' => stateResolved,
    'completed' => stateCompleted,
    'removed' => stateRemoved,
    _ => stateProposed,
  };

  @override
  BoardhopColors copyWith({
    Color? bug,
    Color? task,
    Color? userStory,
    Color? feature,
    Color? epic,
    Color? issue,
    Color? testCase,
    Color? stateProposed,
    Color? stateInProgress,
    Color? stateResolved,
    Color? stateCompleted,
    Color? stateRemoved,
    Color? prActive,
    Color? prCompleted,
    Color? prAbandoned,
    Color? prDraft,
    Color? voteApproved,
    Color? voteApprovedWithSuggestions,
    Color? voteWaiting,
    Color? voteRejected,
    Color? runSucceeded,
    Color? runFailed,
    Color? runPartial,
    Color? runCanceled,
    Color? runInProgress,
    Color? diffAdded,
    Color? diffRemoved,
    Color? diffAddedBackground,
    Color? diffRemovedBackground,
    Color? codeBackground,
  }) {
    return BoardhopColors(
      bug: bug ?? this.bug,
      task: task ?? this.task,
      userStory: userStory ?? this.userStory,
      feature: feature ?? this.feature,
      epic: epic ?? this.epic,
      issue: issue ?? this.issue,
      testCase: testCase ?? this.testCase,
      stateProposed: stateProposed ?? this.stateProposed,
      stateInProgress: stateInProgress ?? this.stateInProgress,
      stateResolved: stateResolved ?? this.stateResolved,
      stateCompleted: stateCompleted ?? this.stateCompleted,
      stateRemoved: stateRemoved ?? this.stateRemoved,
      prActive: prActive ?? this.prActive,
      prCompleted: prCompleted ?? this.prCompleted,
      prAbandoned: prAbandoned ?? this.prAbandoned,
      prDraft: prDraft ?? this.prDraft,
      voteApproved: voteApproved ?? this.voteApproved,
      voteApprovedWithSuggestions:
          voteApprovedWithSuggestions ?? this.voteApprovedWithSuggestions,
      voteWaiting: voteWaiting ?? this.voteWaiting,
      voteRejected: voteRejected ?? this.voteRejected,
      runSucceeded: runSucceeded ?? this.runSucceeded,
      runFailed: runFailed ?? this.runFailed,
      runPartial: runPartial ?? this.runPartial,
      runCanceled: runCanceled ?? this.runCanceled,
      runInProgress: runInProgress ?? this.runInProgress,
      diffAdded: diffAdded ?? this.diffAdded,
      diffRemoved: diffRemoved ?? this.diffRemoved,
      diffAddedBackground: diffAddedBackground ?? this.diffAddedBackground,
      diffRemovedBackground:
          diffRemovedBackground ?? this.diffRemovedBackground,
      codeBackground: codeBackground ?? this.codeBackground,
    );
  }

  @override
  BoardhopColors lerp(ThemeExtension<BoardhopColors>? other, double t) {
    if (other is! BoardhopColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return BoardhopColors(
      bug: l(bug, other.bug),
      task: l(task, other.task),
      userStory: l(userStory, other.userStory),
      feature: l(feature, other.feature),
      epic: l(epic, other.epic),
      issue: l(issue, other.issue),
      testCase: l(testCase, other.testCase),
      stateProposed: l(stateProposed, other.stateProposed),
      stateInProgress: l(stateInProgress, other.stateInProgress),
      stateResolved: l(stateResolved, other.stateResolved),
      stateCompleted: l(stateCompleted, other.stateCompleted),
      stateRemoved: l(stateRemoved, other.stateRemoved),
      prActive: l(prActive, other.prActive),
      prCompleted: l(prCompleted, other.prCompleted),
      prAbandoned: l(prAbandoned, other.prAbandoned),
      prDraft: l(prDraft, other.prDraft),
      voteApproved: l(voteApproved, other.voteApproved),
      voteApprovedWithSuggestions: l(
        voteApprovedWithSuggestions,
        other.voteApprovedWithSuggestions,
      ),
      voteWaiting: l(voteWaiting, other.voteWaiting),
      voteRejected: l(voteRejected, other.voteRejected),
      runSucceeded: l(runSucceeded, other.runSucceeded),
      runFailed: l(runFailed, other.runFailed),
      runPartial: l(runPartial, other.runPartial),
      runCanceled: l(runCanceled, other.runCanceled),
      runInProgress: l(runInProgress, other.runInProgress),
      diffAdded: l(diffAdded, other.diffAdded),
      diffRemoved: l(diffRemoved, other.diffRemoved),
      diffAddedBackground: l(diffAddedBackground, other.diffAddedBackground),
      diffRemovedBackground: l(
        diffRemovedBackground,
        other.diffRemovedBackground,
      ),
      codeBackground: l(codeBackground, other.codeBackground),
    );
  }
}

extension BoardhopColorsContext on BuildContext {
  /// The domain palette for the current brightness. Always present because
  /// `BoardhopTheme` registers it on both themes.
  BoardhopColors get boardhopColors =>
      Theme.of(this).extension<BoardhopColors>() ?? BoardhopColors.light;
}
