import '../../demo_world.dart';
import 'pr_files.dart';

/// One reviewer and their vote (10 approved, 5 with suggestions, 0 none,
/// -5 waiting for author, -10 rejected).
class DemoReviewer {
  const DemoReviewer(this.person, {this.vote = 0, this.isRequired = false});

  final DemoPerson person;
  final int vote;
  final bool isRequired;
}

/// One comment of a thread, [hoursAgo] before [DemoWorld.now].
class DemoComment {
  const DemoComment(
    this.author,
    this.text,
    this.hoursAgo, {
    this.likedBy = const [],
  });

  final DemoPerson author;
  final String text;
  final num hoursAgo;
  final List<DemoPerson> likedBy;
}

/// A person's thread: in the conversation ([path] null), on a file as a
/// whole, or on lines found by [anchor] — the first line containing it, on
/// the new side or, with [leftSide], the original one — spanning [span]
/// lines.
class DemoThread {
  const DemoThread(
    this.comments, {
    this.status = 'active',
    this.path,
    this.anchor,
    this.leftSide = false,
    this.span = 1,
  });

  final List<DemoComment> comments;
  final String status;
  final String? path;
  final String? anchor;
  final bool leftSide;
  final int span;
}

/// A system event thread (`CodeReviewThreadType`), with `{1}` standing for
/// [actor] as the service writes it.
class DemoEvent {
  const DemoEvent(
    this.kind,
    this.actor,
    this.text,
    this.hoursAgo, {
    this.properties = const {},
  });

  final String kind;
  final DemoPerson actor;
  final String text;
  final num hoursAgo;
  final Map<String, String> properties;
}

/// A policy evaluation: `approved`, `rejected`, `running`, `queued`.
class DemoCheck {
  const DemoCheck(this.policy, this.status);

  final DemoPolicy policy;
  final String status;
}

/// One branch policy on `main`, the same set in every repository.
class DemoPolicy {
  const DemoPolicy(
    this.id,
    this.typeId,
    this.displayName, {
    this.isBlocking = true,
    this.settings = const {},
  });

  final int id;
  final String typeId;
  final String displayName;
  final bool isBlocking;
  final Map<String, Object?> settings;
}

/// Everything one demo pull request shows.
class DemoPullRequest {
  const DemoPullRequest({
    required this.ref,
    required this.description,
    required this.files,
    this.reviewers = const [],
    this.labels = const [],
    this.iterationHoursAgo = const [],
    this.threads = const [],
    this.events = const [],
    this.checks = const [],
    this.coverage,
    this.mergeStatus = 'succeeded',
    this.autoCompleteSetBy,
  });

  final DemoPullRequestRef ref;
  final String description;
  final List<DemoFileChange> files;
  final List<DemoReviewer> reviewers;
  final List<String> labels;

  /// When each push landed; the first is the creation. Empty means one
  /// iteration at creation time.
  final List<num> iterationHoursAgo;
  final List<DemoThread> threads;
  final List<DemoEvent> events;
  final List<DemoCheck> checks;

  /// Line coverage for the `coverage/lcov` status, when there is one.
  final String? coverage;
  final String mergeStatus;
  final DemoPerson? autoCompleteSetBy;

  List<num> get pushes =>
      iterationHoursAgo.isEmpty ? [ref.createdHoursAgo] : iterationHoursAgo;
}

abstract final class DemoPolicies {
  static const minimumReviewers = DemoPolicy(
    31,
    'fa4e907d-c16b-4a4c-9dfa-4906e5d171dd',
    'Minimum number of reviewers',
    settings: {
      'minimumApproverCount': 1,
      'creatorVoteCounts': false,
      'resetOnSourcePush': false,
    },
  );
  static const build = DemoPolicy(
    32,
    '0609b952-1397-4640-95ec-e00a01b2c241',
    'Build',
    settings: {
      'buildDefinitionId': 7,
      'displayName': 'boardhop-ci',
      'queueOnSourceUpdateOnly': true,
      'validDuration': 720,
    },
  );
  static const workItemLinking = DemoPolicy(
    33,
    '40e92b44-2fe1-4dd6-b3d8-74a9c21d0c6e',
    'Work item linking',
  );
  static const mergeStrategy = DemoPolicy(
    34,
    'fa4e907d-c16b-4a4c-9dfa-4916e5d171ab',
    'Require a merge strategy',
    settings: {'allowSquash': true, 'allowNoFastForward': true},
  );

  static const all = [minimumReviewers, build, workItemLinking, mergeStrategy];

  /// The build pipeline each repository's build policy runs.
  static String pipelineFor(DemoRepo repo) => '${repo.name}-ci';
}

/// The demo's pull requests, in the order the inbox lists them (newest
/// first, as the service sorts).
abstract final class DemoPullRequests {
  static const _k = DemoWorld.kelly;
  static const _p = DemoWorld.priya;
  static const _m = DemoWorld.marcus;
  static const _s = DemoWorld.sofia;
  static const _j = DemoWorld.jonah;
  static const _a = DemoWorld.aiko;

  static const _passing = [
    DemoCheck(DemoPolicies.build, 'approved'),
    DemoCheck(DemoPolicies.minimumReviewers, 'approved'),
    DemoCheck(DemoPolicies.workItemLinking, 'approved'),
  ];

  /// !412, the store screenshots' pull request.
  static final sideBySide = DemoPullRequest(
    ref: DemoWorld.pullRequest(412),
    description: '''
Adds a **side-by-side** layout for the file diff on iPad and other wide windows. Closes #1238.

### What changed
- `SplitDiffView` shows the base and the change in two panes, one row per aligned line pair
- Both panes scroll together (`_syncing` swallows the echo), so long files stay lined up
- The layout follows the window: side by side from the expanded breakpoint, unified below it, with a toggle in the menu
- Tapping either gutter starts a comment, so removed lines can be discussed too

### Testing
- Widget tests for pane sync and left-side comments
- Checked on the iPad Pro 13" simulator in both orientations and in Split View

@<${DemoWorld.priya.id}> could you look at the scroll sync?''',
    files: splitDiffFiles,
    reviewers: const [
      DemoReviewer(_p, vote: 10, isRequired: true),
      DemoReviewer(_s, vote: 5),
      DemoReviewer(_k),
    ],
    labels: const ['tablet', 'diff'],
    iterationHoursAgo: const [26, 9, 2],
    threads: [
      const DemoThread(
        [
          DemoComment(
            _s,
            'Nit: this reads the breakpoint on every build. Could it come '
            'from the same getter the menu toggle uses?',
            20,
          ),
          DemoComment(
            _m,
            'Good call, both go through `_sideBySideNow` now.',
            9,
            likedBy: [_s],
          ),
        ],
        status: 'fixed',
        path: '/lib/features/pull_requests/pr_file_diff_page.dart',
        anchor: 'bool get _sideBySideNow',
        span: 2,
      ),
      DemoThread(
        [
          DemoComment(
            _p,
            '@<${DemoWorld.marcus.id}> both listeners fire during a fling. '
            'Can this ping-pong between the panes?',
            5,
          ),
          DemoComment(
            _m,
            'The follower\'s listener runs inside `jumpTo` while `_syncing` '
            'is still true, so it returns early. I added a widget test that '
            'flings the left pane and checks both offsets match.',
            1.8,
            likedBy: [_p],
          ),
          const DemoComment(
            _p,
            'Nice. One more: when the new file is shorter, clamp to the '
            'leader\'s extent too, or the old pane jumps back at the end.',
            0.6,
          ),
        ],
        path: kSplitDiffPath,
        anchor: kSplitDiffThreadLine,
      ),
      const DemoThread(
        [
          DemoComment(
            _s,
            'Do we still need the separate wrap key once this lands?',
            18,
          ),
          DemoComment(
            _m,
            'Yes, wrap applies to both layouts. Left it as is.',
            9,
          ),
        ],
        status: 'byDesign',
        path: '/lib/features/pull_requests/diff/diff_prefs.dart',
        anchor: "static const _wrapKey = 'diff.wrap';",
        leftSide: true,
      ),
      const DemoThread([
        DemoComment(
          _p,
          'Tried it on the iPad Pro 13" simulator: the panes stay locked '
          'together, even with the keyboard up for a comment. Lovely.',
          1.5,
          likedBy: [_m, _s],
        ),
        DemoComment(
          _m,
          'Thanks! Stage Manager at the smallest window size falls back to '
          'unified, as planned.',
          1.2,
        ),
      ]),
    ],
    events: const [
      DemoEvent(
        'ReviewersUpdate',
        _m,
        '{1} added Priya Raman, Sofia Alvarez and Kelly Kamm as reviewers',
        26,
      ),
      DemoEvent(
        'VoteUpdate',
        _s,
        '{1} approved with suggestions',
        19,
        properties: {'CodeReviewVoteResult': '5'},
      ),
      DemoEvent('RefUpdate', _m, '{1} pushed 3 commits', 9),
      DemoEvent('RefUpdate', _m, '{1} pushed 1 commit', 2),
      DemoEvent(
        'VoteUpdate',
        _p,
        '{1} approved the pull request',
        0.5,
        properties: {'CodeReviewVoteResult': '10'},
      ),
    ],
    checks: _passing,
    coverage: '84.6% of lines (+1.2%)',
  );

  static final all = <DemoPullRequest>[
    DemoPullRequest(
      ref: DemoWorld.pullRequest(418),
      description:
          'Adds a **Retry** action for failed stages on the run page (#1284).'
          '\n\nStill to do: confirm dialog and a widget test.',
      files: retryFiles,
      checks: const [DemoCheck(DemoPolicies.build, 'queued')],
    ),
    DemoPullRequest(
      ref: DemoWorld.pullRequest(417),
      description:
          'First pass at the floating glass rail from the iOS chrome review '
          '(#1257). Blur and capsule only; the selection indicator comes next.',
      files: glassRailFiles,
      reviewers: const [DemoReviewer(_m), DemoReviewer(_s)],
      labels: const ['ios', 'design'],
      checks: const [
        DemoCheck(DemoPolicies.build, 'approved'),
        DemoCheck(DemoPolicies.minimumReviewers, 'rejected'),
      ],
    ),
    DemoPullRequest(
      ref: DemoWorld.pullRequest(415),
      description:
          'APNs answers **410** once a token rotates, and the relay removed '
          'the device for good, so pushes stopped until the next sign-in '
          '(#1255).\n\n- 410 marks the device stale instead of deleting it\n'
          '- `register` accepts `previousToken` and swaps it in place\n'
          '- `BadDeviceToken` still removes the device',
      files: apnsRotationFiles,
      reviewers: const [
        DemoReviewer(_k, isRequired: true),
        DemoReviewer(_j, vote: 10),
      ],
      labels: const ['relay', 'push'],
      iterationHoursAgo: const [3, 1],
      threads: const [
        DemoThread(
          [
            DemoComment(
              _j,
              'Should `markStale` also stop us from retrying this token '
              'until the app checks in?',
              2,
            ),
            DemoComment(_a, 'Yes, `forUser` skips stale devices now.', 1),
          ],
          path: '/lib/src/push/apns_sender.dart',
          anchor: 'markStale',
        ),
      ],
      checks: const [
        DemoCheck(DemoPolicies.build, 'running'),
        DemoCheck(DemoPolicies.minimumReviewers, 'approved'),
        DemoCheck(DemoPolicies.workItemLinking, 'approved'),
      ],
    ),
    DemoPullRequest(
      ref: DemoWorld.pullRequest(414),
      description:
          'Adds an **Approve** button to the pipeline approval notification '
          '(#1241). It calls the Checks API directly, so the app does not '
          'need to open.',
      files: approveFiles,
      reviewers: const [
        DemoReviewer(_k, isRequired: true),
        DemoReviewer(_a, vote: 5),
      ],
      labels: const ['pipelines', 'push'],
      threads: const [
        DemoThread([
          DemoComment(
            _a,
            'The build failed on the Android lint step, looks unrelated to '
            'this change. Re-queued.',
            4,
          ),
        ]),
      ],
      checks: const [
        DemoCheck(DemoPolicies.build, 'rejected'),
        DemoCheck(DemoPolicies.minimumReviewers, 'approved'),
        DemoCheck(DemoPolicies.workItemLinking, 'approved'),
      ],
    ),
    sideBySide,
    DemoPullRequest(
      ref: DemoWorld.pullRequest(411),
      description:
          'The Marketplace hub now creates the relay\'s service hooks for a '
          'project in one click (#1285). Pipeline run and approval events '
          'are included.',
      files: hubFiles,
      reviewers: const [DemoReviewer(_k, vote: -5), DemoReviewer(_j)],
      labels: const ['extension'],
      threads: const [
        DemoThread(
          [
            DemoComment(
              _k,
              'This needs to stay in step with `hooks_lib.dart` in the relay. '
              'Can we add the two pipeline kinds there in the same change?',
              22,
            ),
          ],
          path: '/src/plan.ts',
          anchor: 'approval-pending',
        ),
      ],
      checks: const [
        DemoCheck(DemoPolicies.build, 'approved'),
        DemoCheck(DemoPolicies.minimumReviewers, 'rejected'),
        DemoCheck(DemoPolicies.workItemLinking, 'approved'),
      ],
    ),
    DemoPullRequest(
      ref: DemoWorld.pullRequest(409),
      description:
          'The burndown stopped a day early because the finish date was '
          'excluded from the range (#1252). The loop is inclusive now, with '
          'a test for a ten-day sprint.',
      files: burndownFiles,
      reviewers: const [DemoReviewer(_k, vote: 10), DemoReviewer(_p, vote: 10)],
      labels: const ['dashboards', 'bug'],
      checks: const [
        DemoCheck(DemoPolicies.build, 'running'),
        DemoCheck(DemoPolicies.minimumReviewers, 'approved'),
        DemoCheck(DemoPolicies.workItemLinking, 'approved'),
      ],
      coverage: '83.9% of lines (+0.1%)',
      autoCompleteSetBy: _s,
    ),
    DemoPullRequest(
      ref: DemoWorld.pullRequest(406),
      description:
          'People you mentioned recently come first in the `@` picker, then '
          'the team (#1248).',
      files: mentionFiles,
      reviewers: const [DemoReviewer(_a, vote: 10), DemoReviewer(_k, vote: 10)],
      labels: const ['mentions'],
      checks: _passing,
    ),
  ];

  static DemoPullRequest? byId(int id) {
    for (final pr in all) {
      if (pr.ref.id == id) return pr;
    }
    return null;
  }
}
