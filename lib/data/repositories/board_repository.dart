import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../models/board.dart';
import '../models/work_item.dart';
import 'work_item_repository.dart';

/// A board plus its cards, distributed into slots (columns, or the Doing
/// and Done halves of a split column).
class BoardSnapshot {
  const BoardSnapshot({
    required this.board,
    required this.cardsBySlot,
    required this.fetchedAt,
    this.rankField,
  });

  final Board board;
  final List<List<WorkItem>> cardsBySlot;
  final DateTime fetchedAt;

  /// The process's rank field (StackRank or BacklogPriority), null when the
  /// cards are ordered by change date only.
  final String? rankField;

  int get cardCount => cardsBySlot.fold(0, (n, c) => n + c.length);
}

class BoardRepository {
  BoardRepository(this._client, this._workItems);

  final AdoClient _client;
  final WorkItemRepository _workItems;

  static const apiVersion = '7.1';

  final Map<String, String> _defaultTeams = {};

  Future<List<BoardSummary>> boards(
    String org,
    String project, {
    String? team,
  }) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      team: team,
      path: '_apis/work/boards',
      apiVersion: apiVersion,
    );
    return ((json['value'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => BoardSummary.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  Future<Board> board(
    String org,
    String project,
    String boardId, {
    String? team,
  }) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      team: team,
      path: '_apis/work/boards/$boardId',
      apiVersion: apiVersion,
    );
    return Board.fromJson(json);
  }

  Future<TeamFieldValues?> teamFieldValues(
    String org,
    String project, {
    String? team,
  }) async {
    try {
      final json = await _client.getJson(
        org: org,
        project: project,
        team: team,
        path: '_apis/work/teamsettings/teamfieldvalues',
        apiVersion: apiVersion,
      );
      return TeamFieldValues.fromJson(json);
    } on AdoNotFoundException {
      return null;
    } on AdoForbiddenException {
      return null;
    }
  }

  /// The project's default team id, which the board calls without a team
  /// segment resolve to, and which the reorder route requires.
  Future<String> defaultTeamId(String org, String project) async {
    final key = '$org/$project';
    final cached = _defaultTeams[key];
    if (cached != null) return cached;
    final json = await _client.getJson(
      org: org,
      path: '_apis/projects/$project',
      apiVersion: apiVersion,
    );
    final id = (json['defaultTeam'] as Map?)?['id'] as String?;
    if (id == null) {
      throw AdoServerException('Project $project has no default team');
    }
    return _defaultTeams[key] = id;
  }

  static String _q(String s) => s.replaceAll("'", "''");

  /// WIQL for the cards on a board: the board's types, in the team's areas,
  /// not removed. [orderBy] is tried in turn because the rank field differs
  /// by process (StackRank for Agile/Basic/CMMI, BacklogPriority for Scrum).
  static String cardsWiql(
    Board board,
    TeamFieldValues? areas, {
    required String orderBy,
  }) {
    final types = board.workItemTypes.map((t) => "'${_q(t)}'").join(', ');
    final areaClauses = <String>[
      for (final v
          in areas?.values ?? const <({String value, bool includeChildren})>[])
        v.includeChildren
            ? "[System.AreaPath] UNDER '${_q(v.value)}'"
            : "[System.AreaPath] = '${_q(v.value)}'",
    ];
    final area = areaClauses.isEmpty
        ? ''
        : ' AND (${areaClauses.join(' OR ')})';
    return 'SELECT [System.Id] FROM WorkItems '
        'WHERE [System.TeamProject] = @project '
        'AND [System.WorkItemType] IN ($types) '
        "AND [System.State] <> 'Removed'$area "
        'ORDER BY $orderBy';
  }

  static const stackRank = 'Microsoft.VSTS.Common.StackRank';
  static const backlogPriority = 'Microsoft.VSTS.Common.BacklogPriority';

  static const _orderCandidates = <(String?, String)>[
    (stackRank, '[$stackRank] ASC, [System.ChangedDate] DESC'),
    (backlogPriority, '[$backlogPriority] ASC, [System.ChangedDate] DESC'),
    (null, '[System.ChangedDate] DESC'),
  ];

  /// Board definition, team areas, then the cards; cards are cached under
  /// the board id so the page can render from drift while refreshing.
  Future<BoardSnapshot> load(
    String org,
    String project,
    String boardId, {
    String? team,
  }) async {
    final board = await this.board(org, project, boardId, team: team);
    final areas = await teamFieldValues(org, project, team: team);
    List<int> ids = const [];
    String? rankField;
    AdoException? last;
    for (final (field, orderBy) in _orderCandidates) {
      try {
        ids = await _workItems.queryIds(
          org,
          project,
          cardsWiql(board, areas, orderBy: orderBy),
          top: 500,
        );
        rankField = field;
        last = null;
        break;
      } on AdoValidationException catch (e) {
        last = e;
      } on AdoServerException catch (e) {
        if (e.statusCode != 400) rethrow;
        last = e;
      }
    }
    if (last != null) throw last;
    final fields = <String>[
      ...WorkItemRepository.listFields,
      ?board.fields.columnField,
      ?board.fields.rowField,
      ?board.fields.doneField,
      ?rankField,
    ];
    final items = ids.isEmpty
        ? <WorkItem>[]
        : await _workItems.batch(org, project, ids, fields: fields);
    await _workItems.storeList(org, project, boardId, items);
    return BoardSnapshot(
      board: board,
      cardsBySlot: distribute(board, items),
      fetchedAt: DateTime.now(),
      rankField: rankField,
    );
  }

  /// What to send to the reorder route so that the card at [index] lands
  /// where it sits in [cards]: the card plus the contiguous run of unranked
  /// neighbours (the service cannot place anything relative to a card that
  /// has no rank), bounded by the nearest ranked cards.
  static ({List<int> ids, int previousId, int nextId}) reorderBlock(
    List<WorkItem> cards,
    int index,
    String? rankField,
  ) {
    bool ranked(WorkItem w) =>
        rankField != null && w.field<num>(rankField) != null;
    var start = index;
    while (start > 0 && !ranked(cards[start - 1])) {
      start--;
    }
    var end = index;
    while (end + 1 < cards.length && !ranked(cards[end + 1])) {
      end++;
    }
    return (
      ids: [for (var i = start; i <= end; i++) cards[i].id],
      previousId: start > 0 ? cards[start - 1].id : 0,
      nextId: end + 1 < cards.length ? cards[end + 1].id : 0,
    );
  }

  /// Lane (swimlane) of a card: the WEF row field, empty for the default.
  static String laneOf(Board board, WorkItem item) {
    final field = board.fields.rowField;
    return field == null ? '' : (item.field<String>(field) ?? '');
  }

  static bool isDone(Board board, WorkItem item) {
    final field = board.fields.doneField;
    return field == null
        ? item.boardColumnDone
        : (item.field<bool>(field) ?? item.boardColumnDone);
  }

  static List<List<WorkItem>> distribute(Board board, List<WorkItem> items) {
    final slots = board.slots;
    final out = List.generate(slots.length, (_) => <WorkItem>[]);
    if (out.isEmpty) return out;
    final columnField = board.fields.columnField;
    for (final item in items) {
      final value = columnField == null
          ? item.boardColumn
          : item.field<String>(columnField) ?? item.boardColumn;
      final column = board.columnIndexFor(
        type: item.type,
        state: item.state,
        columnValue: value,
      );
      final done = board.columns[column].isSplit ? isDone(board, item) : null;
      final slot = slots.indexWhere(
        (s) => s.columnIndex == column && s.done == done,
      );
      out[slot < 0 ? 0 : slot].add(item);
    }
    return out;
  }

  /// The JSON Patch for a move: the WEF column field plus the mapped state
  /// (both, the settled safe default from spike w02), and the Done flag only
  /// for a split column.
  static List<Map<String, Object?>> moveOps(
    Board board,
    WorkItem item,
    BoardSlot target,
  ) {
    final columnField = board.fields.columnField;
    final ops = <Map<String, Object?>>[];
    if (columnField != null &&
        item.field<String>(columnField) != target.column.name) {
      ops.add({
        'op': 'add',
        'path': '/fields/$columnField',
        'value': target.column.name,
      });
    }
    final state = target.column.stateMappings[item.type];
    if (state != null && state != item.state) {
      ops.add({'op': 'add', 'path': '/fields/System.State', 'value': state});
    }
    final doneField = board.fields.doneField;
    if (target.done != null && doneField != null) {
      ops.add({'op': 'add', 'path': '/fields/$doneField', 'value': target.done});
    }
    return ops;
  }

  Future<WorkItem> move(
    String org,
    String project,
    Board board,
    WorkItem item,
    BoardSlot target,
  ) async {
    final ops = moveOps(board, item, target);
    if (ops.isEmpty) return item;
    return _workItems.patch(org, project, item, ops);
  }

  /// `PATCH {team}/_apis/work/workitemsorder`: place [ids], in order,
  /// between [previousId] and [nextId] (0 = start / end). Returns the ranks
  /// the service renormalised, which may include neighbours.
  Future<Map<int, double>> reorder(
    String org,
    String project,
    List<int> ids, {
    required int previousId,
    required int nextId,
  }) async {
    final team = await defaultTeamId(org, project);
    final json = await _client.send(
      method: 'PATCH',
      org: org,
      project: project,
      team: team,
      path: '_apis/work/workitemsorder',
      apiVersion: apiVersion,
      body: {
        'ids': ids,
        'previousId': previousId,
        'nextId': nextId,
        'parentId': 0,
      },
    );
    return {
      for (final r in ((json['value'] as List?) ?? const []).whereType<Map>())
        r['id'] as int: (r['order'] as num?)?.toDouble() ?? 0,
    };
  }
}
