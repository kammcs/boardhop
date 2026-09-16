/// The invented organization the demo mode shows: the Boardhop team using
/// Boardhop, in Azure DevOps, to build Boardhop. Every fixture reads its
/// names, people, sprints and work items from here so the screens agree
/// with each other when someone looks closely.
///
/// Times are relative to [now], taken once per launch, so "2 hours ago"
/// and the current sprint stay current whenever the screenshots are taken.
abstract final class DemoWorld {
  static final DateTime now = DateTime.now().toUtc();

  static const org = 'kammcs';
  static const orgId = '5b1c7e0a-3f2d-4c8e-9a61-0d4b2f7c9e13';
  static const tenantId = '8e2f4a61-7b3c-4d1e-9f05-2a6c8b1d3e47';
  static const project = 'Boardhop';
  static const projectId = '1f6a2c9e-8b47-4d35-a0e2-6c93b5d7f148';
  static const team = 'Boardhop Team';
  static const teamId = '9d3e7b21-4a6c-4f58-b1d9-3e7a2c6b8f05';
  static const teamDescriptor = 'vssgp.Uy0xLTktMTU1MTM3NDI0NS0xMjA0NDAwOTY5';
  static const projectDescription =
      'The Azure DevOps mobile client for iOS and Android.';

  static const baseUrl = 'https://dev.azure.com/$org';
  static const projectUrl = '$baseUrl/$projectId';

  /// The signed-in person.
  static const me = kelly;

  static const kelly = DemoPerson(
    id: 'b7d2f0c4-6e1a-4c39-8a5b-2f9d7e3c1a60',
    name: 'Kelly Kamm',
    email: 'kelly@kammcs.com',
  );
  static const priya = DemoPerson(
    id: 'c4a9e1b7-2d6f-4e83-9b10-7a5c3f8d2e41',
    name: 'Priya Raman',
    email: 'priya@kammcs.com',
  );
  static const marcus = DemoPerson(
    id: 'e1f5b3a8-9c2d-47e6-8d41-5b0a6c9e3f72',
    name: 'Marcus Chen',
    email: 'marcus@kammcs.com',
  );
  static const sofia = DemoPerson(
    id: 'a8c3d6e2-5f1b-4a97-b2e0-9d4f7a1c6b38',
    name: 'Sofia Alvarez',
    email: 'sofia@kammcs.com',
  );
  static const jonah = DemoPerson(
    id: 'f2b6a9d1-3e7c-4b50-a8f3-1c6e9d2b5a07',
    name: 'Jonah Whitfield',
    email: 'jonah@kammcs.com',
  );
  static const aiko = DemoPerson(
    id: 'd9e4c2a7-1b8f-4d63-9e5a-6f2b3c7d8e19',
    name: 'Aiko Tanaka',
    email: 'aiko@kammcs.com',
  );

  static const people = [kelly, priya, marcus, sofia, jonah, aiko];

  static DemoPerson person(String id) =>
      people.firstWhere((p) => p.id == id || p.email == id, orElse: () => me);

  // --- Time -----------------------------------------------------------------

  /// Midnight UTC today, the anchor for sprint dates.
  static DateTime get today => DateTime.utc(now.year, now.month, now.day);

  static DateTime daysAgo(num days) =>
      now.subtract(Duration(minutes: (days * 24 * 60).round()));
  static DateTime hoursAgo(num hours) =>
      now.subtract(Duration(minutes: (hours * 60).round()));
  static DateTime minutesAgo(num minutes) =>
      now.subtract(Duration(seconds: (minutes * 60).round()));

  static String iso(DateTime t) => t.toUtc().toIso8601String();

  // --- Iterations -----------------------------------------------------------

  /// Two-week sprints; the current one started on the Monday of last week,
  /// so on a weekday it is on day 6 to 10 of its 10 working days. On a
  /// Saturday or Sunday the week ahead counts as "this week", which keeps
  /// the sprint current (a Monday-before-today-minus-8 rule ended the
  /// sprint on weekends and Mondays).
  static final List<DemoSprint> sprints = () {
    final thisMonday = _mondayOnOrBefore(today)
        .add(Duration(days: today.weekday >= DateTime.saturday ? 7 : 0));
    final currentStart = thisMonday.subtract(const Duration(days: 7));
    return [
      for (var i = 0; i < 5; i++)
        DemoSprint(
          number: 12 + i,
          id: '6c1d8e4f-2a7b-4e9$i-b3c5-8d0e1f2a3b4$i',
          start: currentStart.add(Duration(days: 14 * (i - 2))),
        ),
    ];
  }();

  static DemoSprint get currentSprint => sprints[2];

  static DateTime _mondayOnOrBefore(DateTime d) =>
      d.subtract(Duration(days: d.weekday - DateTime.monday));

  // --- Repositories ---------------------------------------------------------

  static const appRepo = DemoRepo(
    id: '3a7e9c1d-5b2f-4d86-a0e4-7c1b9d3f5e28',
    name: 'boardhop',
  );
  static const relayRepo = DemoRepo(
    id: '7d2b5f8a-1c4e-4a39-b6d7-0e3a8c5f1b92',
    name: 'boardhop-relay',
  );
  static const extensionRepo = DemoRepo(
    id: 'b5e8a2c6-9d1f-4b73-8e20-4a6d1c9b7f53',
    name: 'boardhop-extension',
  );
  static const repos = [appRepo, relayRepo, extensionRepo];

  // --- Work items -----------------------------------------------------------

  static const area = 'Boardhop';
  static String iterationPath(DemoSprint s) => 'Boardhop\\${s.name}';

  /// The backlog. States follow the Agile process: Epic/Feature/User Story
  /// New → Active → Resolved → Closed; Task To Do → In Progress → Done;
  /// Bug New → Active → Resolved → Closed.
  static final List<DemoWorkItem> workItems = [
    // Epics and features.
    const DemoWorkItem(
      1180,
      'Epic',
      'Boardhop 1.0 for iOS and Android',
      'Active',
      assignee: kelly,
      sprint: -1,
    ),
    const DemoWorkItem(
      1184,
      'Feature',
      'Boards and sprints',
      'Active',
      assignee: priya,
      parent: 1180,
      sprint: -1,
    ),
    const DemoWorkItem(
      1185,
      'Feature',
      'Pull request review',
      'Active',
      assignee: marcus,
      parent: 1180,
      sprint: -1,
    ),
    const DemoWorkItem(
      1186,
      'Feature',
      'Pipelines and approvals',
      'Active',
      assignee: jonah,
      parent: 1180,
      sprint: -1,
    ),
    const DemoWorkItem(
      1187,
      'Feature',
      'Push notifications through the tenant relay',
      'Active',
      assignee: aiko,
      parent: 1180,
      sprint: -1,
    ),
    const DemoWorkItem(
      1188,
      'Feature',
      'Dashboards on the phone',
      'Active',
      assignee: sofia,
      parent: 1180,
      sprint: -1,
    ),

    // Current sprint (Sprint 14) user stories and bugs.
    const DemoWorkItem(
      1231,
      'User Story',
      'Drag cards between split board columns',
      'Resolved',
      assignee: priya,
      parent: 1184,
      points: 8,
      column: 'Review',
      tags: ['boards', 'tablet'],
      priority: 1,
    ),
    const DemoWorkItem(
      1234,
      'User Story',
      'Sprint taskboard with capacity bars',
      'Active',
      assignee: kelly,
      parent: 1184,
      points: 5,
      column: 'In Progress',
      tags: ['sprints'],
      priority: 1,
    ),
    const DemoWorkItem(
      1238,
      'User Story',
      'Side-by-side diff on iPad',
      'Active',
      assignee: marcus,
      parent: 1185,
      points: 8,
      column: 'In Progress',
      tags: ['pull requests', 'tablet'],
      priority: 2,
    ),
    const DemoWorkItem(
      1241,
      'User Story',
      'Approve a waiting pipeline stage from a notification',
      'Active',
      assignee: jonah,
      parent: 1186,
      points: 5,
      column: 'In Progress',
      tags: ['pipelines', 'push'],
      priority: 1,
    ),
    const DemoWorkItem(
      1243,
      'User Story',
      'Burndown and velocity tiles on the dashboard',
      'New',
      assignee: sofia,
      parent: 1188,
      points: 5,
      column: 'Ready',
      tags: ['dashboards'],
      priority: 2,
    ),
    const DemoWorkItem(
      1246,
      'User Story',
      'Offline cache for boards and work items',
      'Closed',
      assignee: priya,
      parent: 1184,
      points: 3,
      column: 'Done',
      tags: ['offline'],
      priority: 2,
    ),
    const DemoWorkItem(
      1248,
      'User Story',
      '@mention autocomplete in comments',
      'Closed',
      assignee: aiko,
      parent: 1184,
      points: 3,
      column: 'Done',
      tags: ['mentions'],
      priority: 2,
    ),
    const DemoWorkItem(
      1252,
      'Bug',
      'Burndown skips the last working day of the sprint',
      'Closed',
      assignee: sofia,
      parent: 1188,
      points: 2,
      column: 'Done',
      tags: ['dashboards'],
      priority: 1,
      severity: '2 - High',
    ),
    const DemoWorkItem(
      1255,
      'Bug',
      'Relay drops pushes when the APNs token rotates',
      'New',
      assignee: aiko,
      parent: 1187,
      points: 3,
      column: 'Ready',
      tags: ['relay', 'push'],
      priority: 1,
      severity: '2 - High',
    ),
    const DemoWorkItem(
      1257,
      'User Story',
      'Liquid glass navigation rail on iPad',
      'New',
      assignee: kelly,
      parent: 1184,
      points: 3,
      column: 'Ready',
      tags: ['ios', 'tablet'],
      priority: 3,
    ),

    // Tasks under the current sprint's stories.
    const DemoWorkItem(
      1260,
      'Task',
      'Hit-test split column drop targets',
      'Done',
      assignee: priya,
      parent: 1231,
      remaining: 0,
    ),
    const DemoWorkItem(
      1261,
      'Task',
      'Widget tests for lane moves',
      'Done',
      assignee: priya,
      parent: 1231,
      remaining: 0,
    ),
    const DemoWorkItem(
      1262,
      'Task',
      'Capacity bar per person',
      'In Progress',
      assignee: kelly,
      parent: 1234,
      remaining: 4,
    ),
    const DemoWorkItem(
      1263,
      'Task',
      'Landscape taskboard grid',
      'Done',
      assignee: sofia,
      parent: 1234,
      remaining: 0,
    ),
    const DemoWorkItem(
      1264,
      'Task',
      'Remaining work rollup on story rows',
      'To Do',
      assignee: kelly,
      parent: 1234,
      remaining: 5,
    ),
    const DemoWorkItem(
      1265,
      'Task',
      'Myers diff over word tokens',
      'Done',
      assignee: marcus,
      parent: 1238,
      remaining: 0,
    ),
    const DemoWorkItem(
      1266,
      'Task',
      'Synchronized scrolling for both panes',
      'In Progress',
      assignee: marcus,
      parent: 1238,
      remaining: 6,
    ),
    const DemoWorkItem(
      1267,
      'Task',
      'Comment gutter in side-by-side mode',
      'In Progress',
      assignee: priya,
      parent: 1238,
      remaining: 2,
    ),
    const DemoWorkItem(
      1268,
      'Task',
      'Approval action on the push category',
      'Done',
      assignee: jonah,
      parent: 1241,
      remaining: 0,
    ),
    const DemoWorkItem(
      1269,
      'Task',
      'Checks API call for environment approvals',
      'Done',
      assignee: jonah,
      parent: 1241,
      remaining: 0,
    ),
    const DemoWorkItem(
      1270,
      'Task',
      'Stage graph on the run page',
      'To Do',
      assignee: aiko,
      parent: 1241,
      remaining: 5,
    ),
    const DemoWorkItem(
      1271,
      'Task',
      'Analytics OData query for burndown',
      'To Do',
      assignee: sofia,
      parent: 1243,
      remaining: 6,
    ),
    const DemoWorkItem(
      1272,
      'Task',
      'Velocity chart widget',
      'In Progress',
      assignee: sofia,
      parent: 1243,
      remaining: 3,
    ),
    const DemoWorkItem(
      1273,
      'Task',
      'Include the end date in the day range',
      'Done',
      assignee: sofia,
      parent: 1252,
      remaining: 0,
    ),
    const DemoWorkItem(
      1274,
      'Task',
      'Re-register device on token rotation',
      'To Do',
      assignee: aiko,
      parent: 1255,
      remaining: 4,
    ),
    // Added by the work fixtures: a story sitting in the Done half of the
    // split In Progress column, and done tasks for the closed stories so the
    // taskboard's Done column is not empty.
    const DemoWorkItem(
      1236,
      'User Story',
      'Pull to refresh on every list',
      'Active',
      assignee: jonah,
      parent: 1184,
      points: 2,
      column: 'In Progress',
      columnDone: true,
      tags: ['polish'],
      priority: 2,
    ),
    const DemoWorkItem(
      1276,
      'Task',
      'Refresh indicator under the glass app bar',
      'Done',
      assignee: jonah,
      parent: 1236,
      remaining: 0,
    ),
    const DemoWorkItem(
      1277,
      'Task',
      'Widget test for refresh on the board',
      'Done',
      assignee: jonah,
      parent: 1236,
      remaining: 0,
    ),
    const DemoWorkItem(
      1278,
      'Task',
      'Cache board snapshots in JsonCache',
      'Done',
      assignee: priya,
      parent: 1246,
      remaining: 0,
    ),
    const DemoWorkItem(
      1279,
      'Task',
      'Recent people band in the mention picker',
      'Done',
      assignee: aiko,
      parent: 1248,
      remaining: 0,
    ),
    const DemoWorkItem(
      1275,
      'Task',
      'Floating glass rail layout',
      'To Do',
      assignee: kelly,
      parent: 1257,
      remaining: 6,
    ),

    // Backlog beyond the sprint (board columns New / Ready).
    const DemoWorkItem(
      1280,
      'User Story',
      'Wiki pages with Mermaid diagrams',
      'New',
      assignee: marcus,
      parent: 1184,
      points: 5,
      column: 'New',
      sprint: 1,
      tags: ['wiki'],
      priority: 2,
    ),
    const DemoWorkItem(
      1281,
      'User Story',
      'Code search across repositories',
      'New',
      assignee: jonah,
      parent: 1185,
      points: 8,
      column: 'New',
      sprint: 1,
      tags: ['repos'],
      priority: 3,
    ),
    const DemoWorkItem(
      1282,
      'User Story',
      'Sign in with a personal access token',
      'New',
      parent: 1180,
      points: 3,
      column: 'New',
      sprint: -1,
      tags: ['auth'],
      priority: 3,
    ),
    const DemoWorkItem(
      1283,
      'Bug',
      'Diff gutter misaligns at the largest text size',
      'New',
      assignee: marcus,
      parent: 1185,
      points: 1,
      column: 'New',
      sprint: 1,
      tags: ['accessibility'],
      priority: 2,
      severity: '3 - Medium',
    ),
    const DemoWorkItem(
      1284,
      'User Story',
      'Retry failed pipeline jobs',
      'New',
      assignee: jonah,
      parent: 1186,
      points: 3,
      column: 'Ready',
      sprint: 1,
      tags: ['pipelines'],
      priority: 2,
    ),
    const DemoWorkItem(
      1285,
      'User Story',
      'Marketplace hub provisions relay hooks',
      'Active',
      assignee: aiko,
      parent: 1187,
      points: 5,
      column: 'Review',
      sprint: 0,
      tags: ['extension'],
      priority: 1,
    ),
    const DemoWorkItem(
      1286,
      'Bug',
      'Dark mode chips lose contrast on the board',
      'Closed',
      assignee: sofia,
      parent: 1184,
      points: 1,
      column: 'Done',
      sprint: 0,
      tags: ['design'],
      priority: 2,
      severity: '3 - Medium',
    ),

    // Last sprint, done.
    const DemoWorkItem(
      1210,
      'User Story',
      'Pull request inbox across repositories',
      'Closed',
      assignee: marcus,
      parent: 1185,
      points: 5,
      column: 'Done',
      sprint: -1,
      tags: ['pull requests'],
      priority: 1,
    ),
    const DemoWorkItem(
      1214,
      'User Story',
      'Live log tail for running jobs',
      'Closed',
      assignee: jonah,
      parent: 1186,
      points: 8,
      column: 'Done',
      sprint: -1,
      tags: ['pipelines'],
      priority: 2,
    ),
  ];

  static DemoWorkItem workItem(int id) =>
      workItems.firstWhere((w) => w.id == id);

  /// Change times (hours ago) for the items the screenshots look at closely;
  /// every other item derives one in [DemoWorkItem.changedHoursAgo].
  static const workItemChangedHoursAgo = <int, num>{
    1234: 0.4,
    1262: 0.4,
    1231: 1.1,
    1263: 3,
    1238: 4.5,
    1266: 4.5,
    1252: 6,
    1273: 6,
    1241: 7,
    1268: 7,
    1264: 20,
    1275: 22,
    1257: 23,
    1255: 26,
  };

  // --- Pull requests --------------------------------------------------------

  /// The active pull requests. Files, reviewers, checks and threads live in
  /// `fixtures/pull_requests/`; this is what other areas (activity, linked
  /// work items) need to agree with them.
  static const pullRequests = [
    DemoPullRequestRef(
      412,
      'Side-by-side diff on iPad',
      appRepo,
      marcus,
      'feature/side-by-side-diff',
      workItems: [1238, 1265, 1266],
      createdHoursAgo: 26,
    ),
    DemoPullRequestRef(
      415,
      'Re-register the device when the APNs token rotates',
      relayRepo,
      aiko,
      'fix/apns-token-rotation',
      workItems: [1255, 1274],
      createdHoursAgo: 3,
    ),
    DemoPullRequestRef(
      409,
      'Include the last working day in the burndown',
      appRepo,
      sofia,
      'fix/burndown-last-day',
      workItems: [1252, 1273],
      createdHoursAgo: 50,
    ),
    DemoPullRequestRef(
      417,
      'Floating liquid glass rail on iPad',
      appRepo,
      kelly,
      'feature/glass-rail',
      workItems: [1257, 1275],
      isDraft: true,
      createdHoursAgo: 0.7,
    ),
    DemoPullRequestRef(
      411,
      'Hub provisions relay hooks per project',
      extensionRepo,
      aiko,
      'feature/hub-provisioning',
      workItems: [1285],
      createdHoursAgo: 30,
    ),
    DemoPullRequestRef(
      414,
      'Approve a waiting stage from the notification',
      appRepo,
      jonah,
      'feature/approve-from-push',
      workItems: [1241, 1268],
      createdHoursAgo: 7,
    ),
    DemoPullRequestRef(
      406,
      '@mention autocomplete ranks recent people first',
      appRepo,
      priya,
      'feature/mention-recents',
      workItems: [1248],
      createdHoursAgo: 98,
    ),
    DemoPullRequestRef(
      418,
      'Retry failed jobs from the run page',
      appRepo,
      jonah,
      'feature/retry-failed-jobs',
      workItems: [1284],
      isDraft: true,
      createdHoursAgo: 0.3,
    ),
  ];

  static DemoPullRequestRef pullRequest(int id) =>
      pullRequests.firstWhere((p) => p.id == id);
}

/// One pull request of the invented organization, as other areas refer to
/// it.
class DemoPullRequestRef {
  const DemoPullRequestRef(
    this.id,
    this.title,
    this.repo,
    this.author,
    this.sourceBranch, {
    this.workItems = const [],
    this.isDraft = false,
    this.createdHoursAgo = 24,
  });

  final int id;
  final String title;
  final DemoRepo repo;
  final DemoPerson author;

  /// Branch name without `refs/heads/`; every one targets `main`.
  final String sourceBranch;
  final List<int> workItems;
  final bool isDraft;
  final num createdHoursAgo;
}

class DemoPerson {
  const DemoPerson({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;

  String get descriptor => 'aad.${id.replaceAll('-', '').substring(0, 24)}';

  /// An `IdentityRef` as work item fields, reviewers and runs carry it.
  Map<String, dynamic> identity() => {
    'displayName': name,
    'id': id,
    'uniqueName': email,
    'descriptor': descriptor,
    'url': 'https://spsprodcus5.vssps.visualstudio.com/_apis/Identities/$id',
    'imageUrl':
        '${DemoWorld.baseUrl}/_apis/GraphProfile/MemberAvatars/$descriptor',
    '_links': {
      'avatar': {
        'href':
            '${DemoWorld.baseUrl}/_apis/GraphProfile/MemberAvatars/$descriptor',
      },
    },
  };
}

class DemoSprint {
  const DemoSprint({
    required this.number,
    required this.id,
    required this.start,
  });

  final int number;
  final String id;
  final DateTime start;

  String get name => 'Sprint $number';
  String get path => 'Boardhop\\$name';

  /// Friday of the second week.
  DateTime get finish => start.add(const Duration(days: 11));
}

class DemoRepo {
  const DemoRepo({required this.id, required this.name});

  final String id;
  final String name;

  String get url => '${DemoWorld.baseUrl}/${DemoWorld.project}/_git/$name';
}

/// One work item of the invented backlog.
class DemoWorkItem {
  const DemoWorkItem(
    this.id,
    this.type,
    this.title,
    this.state, {
    this.assignee,
    this.parent,
    this.points,
    this.remaining,
    this.column,
    this.tags = const [],
    this.priority = 2,
    this.severity,
    this.sprint = 0,
    this.columnDone = false,
  });

  /// In a split board column (In Progress), whether the card sits in the
  /// Done half.
  final bool columnDone;

  bool get isTask => type == 'Task';

  /// Requirement-level work (a row on the taskboard, a card on the Stories
  /// board).
  bool get isRequirement => type == 'User Story' || type == 'Bug';

  /// The iteration path the item carries: epics, features and unplanned
  /// backlog items sit at the project root, everything else in its sprint.
  String get iterationPath {
    if (type == 'Epic' || type == 'Feature') return DemoWorld.area;
    if (id == 1282) return DemoWorld.area;
    return iteration.path;
  }

  /// When the item last changed, in hours before [DemoWorld.now]: the
  /// sprint's work moved today or yesterday, the rest longer ago.
  num get changedHoursAgo {
    final known = DemoWorld.workItemChangedHoursAgo[id];
    if (known != null) return known;
    final spread = (id * 37) % 23;
    if (type == 'Epic' || type == 'Feature') return 96 + spread * 5;
    final offset = type == 'Task' && parent != null
        ? DemoWorld.workItem(parent!).sprint
        : sprint;
    if (offset < 0) return 240 + spread * 6;
    if (offset > 0) return 50 + spread * 4;
    return 2 + spread * 1.5;
  }

  DateTime get changedDate => DemoWorld.hoursAgo(changedHoursAgo);

  /// Created a little before the sprint it belongs to started.
  DateTime get createdDate {
    final base = iteration.start.subtract(Duration(days: 3 + (id % 5)));
    final changed = changedDate;
    return base.isBefore(changed)
        ? base
        : changed.subtract(const Duration(days: 1));
  }

  final int id;
  final String type;
  final String title;
  final String state;
  final DemoPerson? assignee;
  final int? parent;
  final num? points;
  final num? remaining;

  /// Kanban column on the Stories board; tasks follow their parent.
  final String? column;
  final List<String> tags;
  final int priority;
  final String? severity;

  /// Sprint relative to the current one (0 current, -1 last, 1 next).
  /// Tasks follow their parent's sprint.
  final int sprint;

  DemoSprint get iteration {
    final parentItem = type == 'Task' && parent != null
        ? DemoWorld.workItem(parent!)
        : null;
    final offset = parentItem?.sprint ?? sprint;
    return DemoWorld.sprints[2 + offset];
  }
}
