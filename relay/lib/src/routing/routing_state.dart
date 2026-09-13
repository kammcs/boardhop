import '../db.dart';

/// The small per-artifact memory the rules need, as an interface, so the rule
/// files stay free of sqlite and the tests can run against a map.
///
/// Everything here is metadata (research/14 §5.1): ids, votes, a status word,
/// a commit sha, a branch name, a build result. Reads return the state **as it
/// was before this event**, which is the whole point — the service-hook body
/// is rendered at delivery time and carries no before/after (w24).
abstract interface class RoutingState {
  PrStateRow? pullRequest(String org, String prId);

  void savePullRequest(PrStateRow row);

  PrThreadStateRow? thread(String org, String prId, String threadId);

  /// Adds [userId] to a thread's participants, creating the row if it is new.
  void addThreadParticipant({
    required String org,
    required String prId,
    required String threadId,
    required String userId,
  });

  RunStateRow? run(String org, String runId);

  void saveRun(RunStateRow row);

  BuildStateRow? build(String org, String projectId, String definitionId, String branch);

  void saveBuild(BuildStateRow row);

  /// The name for a project id, when some payload has carried both.
  String? projectName(String org, String projectId);

  void saveProject(String org, String projectId, String projectName);
}

/// The production implementation: the routing tables of schema 4.
class DbRoutingState implements RoutingState {
  const DbRoutingState(this.db);

  final RelayDb db;

  @override
  PrStateRow? pullRequest(String org, String prId) => db.prState(org, prId);

  @override
  void savePullRequest(PrStateRow row) => db.savePrState(row);

  @override
  PrThreadStateRow? thread(String org, String prId, String threadId) => db.prThreadState(org, prId, threadId);

  @override
  void addThreadParticipant({
    required String org,
    required String prId,
    required String threadId,
    required String userId,
  }) {
    final existing = db.prThreadState(org, prId, threadId);
    final participants = [...?existing?.participantIds];
    if (participants.contains(userId)) return;
    participants.add(userId);
    db.savePrThreadState(PrThreadStateRow(org: org, prId: prId, threadId: threadId, participantIds: participants));
  }

  @override
  RunStateRow? run(String org, String runId) => db.runState(org, runId);

  @override
  void saveRun(RunStateRow row) => db.saveRunState(row);

  @override
  BuildStateRow? build(String org, String projectId, String definitionId, String branch) =>
      db.buildState(org, projectId, definitionId, branch);

  @override
  void saveBuild(BuildStateRow row) => db.saveBuildState(row);

  @override
  String? projectName(String org, String projectId) => db.projectName(org, projectId);

  @override
  void saveProject(String org, String projectId, String projectName) => db.saveProject(org, projectId, projectName);
}

/// The in-memory fake the rule tests run against: the same contract, four maps
/// and no sqlite.
class MemoryRoutingState implements RoutingState {
  final Map<String, PrStateRow> prs = {};
  final Map<String, PrThreadStateRow> threads = {};
  final Map<String, RunStateRow> runs = {};
  final Map<String, BuildStateRow> builds = {};
  final Map<String, String> projects = {};

  @override
  PrStateRow? pullRequest(String org, String prId) => prs['$org/$prId'];

  @override
  void savePullRequest(PrStateRow row) => prs['${row.org}/${row.prId}'] = row;

  @override
  PrThreadStateRow? thread(String org, String prId, String threadId) => threads['$org/$prId/$threadId'];

  @override
  void addThreadParticipant({
    required String org,
    required String prId,
    required String threadId,
    required String userId,
  }) {
    final key = '$org/$prId/$threadId';
    final participants = [...?threads[key]?.participantIds];
    if (participants.contains(userId)) return;
    participants.add(userId);
    threads[key] = PrThreadStateRow(org: org, prId: prId, threadId: threadId, participantIds: participants);
  }

  @override
  RunStateRow? run(String org, String runId) => runs['$org/$runId'];

  @override
  void saveRun(RunStateRow row) {
    final key = '${row.org}/${row.runId}';
    final existing = runs[key];
    runs[key] = RunStateRow(
      org: row.org,
      runId: row.runId,
      pipelineId: row.pipelineId ?? existing?.pipelineId,
      requestedForId: row.requestedForId ?? existing?.requestedForId,
      requestedById: row.requestedById ?? existing?.requestedById,
      createdAt: existing?.createdAt ?? row.createdAt,
    );
  }

  @override
  BuildStateRow? build(String org, String projectId, String definitionId, String branch) =>
      builds['$org/$projectId/$definitionId/$branch'];

  @override
  void saveBuild(BuildStateRow row) => builds['${row.org}/${row.projectId}/${row.definitionId}/${row.branch}'] = row;

  @override
  String? projectName(String org, String projectId) => projects['$org/$projectId'];

  @override
  void saveProject(String org, String projectId, String projectName) => projects['$org/$projectId'] = projectName;
}
