import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../models/board.dart';
import '../models/work_item.dart';
import 'work_item_repository.dart';

/// A board plus its cards, distributed into columns.
class BoardSnapshot {
  const BoardSnapshot({
    required this.board,
    required this.cardsByColumn,
    required this.fetchedAt,
  });

  final Board board;
  final List<List<WorkItem>> cardsByColumn;
  final DateTime fetchedAt;

  int get cardCount => cardsByColumn.fold(0, (n, c) => n + c.length);
}

class BoardRepository {
  BoardRepository(this._client, this._workItems);

  final AdoClient _client;
  final WorkItemRepository _workItems;

  static const apiVersion = '7.1';

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
      for (final v in areas?.values ?? const <({String value, bool includeChildren})>[])
        v.includeChildren
            ? "[System.AreaPath] UNDER '${_q(v.value)}'"
            : "[System.AreaPath] = '${_q(v.value)}'",
    ];
    final area = areaClauses.isEmpty ? '' : ' AND (${areaClauses.join(' OR ')})';
    return 'SELECT [System.Id] FROM WorkItems '
        'WHERE [System.TeamProject] = @project '
        'AND [System.WorkItemType] IN ($types) '
        "AND [System.State] <> 'Removed'$area "
        'ORDER BY $orderBy';
  }

  static const _orderCandidates = <String>[
    '[Microsoft.VSTS.Common.StackRank] ASC, [System.ChangedDate] DESC',
    '[Microsoft.VSTS.Common.BacklogPriority] ASC, [System.ChangedDate] DESC',
    '[System.ChangedDate] DESC',
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
    AdoException? last;
    for (final orderBy in _orderCandidates) {
      try {
        ids = await _workItems.queryIds(
          org,
          project,
          cardsWiql(board, areas, orderBy: orderBy),
          top: 500,
        );
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
    ];
    final items = ids.isEmpty
        ? <WorkItem>[]
        : await _workItems.batch(org, project, ids, fields: fields);
    await _workItems.storeList(org, project, boardId, items);
    return BoardSnapshot(
      board: board,
      cardsByColumn: distribute(board, items),
      fetchedAt: DateTime.now(),
    );
  }

  static List<List<WorkItem>> distribute(Board board, List<WorkItem> items) {
    final columns = List.generate(board.columns.length, (_) => <WorkItem>[]);
    if (columns.isEmpty) return columns;
    final columnField = board.fields.columnField;
    for (final item in items) {
      final value = columnField == null
          ? item.boardColumn
          : item.field<String>(columnField) ?? item.boardColumn;
      columns[board.columnIndexFor(
            type: item.type,
            state: item.state,
            columnValue: value,
          )]
          .add(item);
    }
    return columns;
  }

  /// The JSON Patch for a column move: the WEF column field plus the
  /// mapped state (both, the settled safe default from spike w02), and the
  /// Done flag reset only when the target column is split.
  static List<Map<String, Object?>> moveOps(
    Board board,
    WorkItem item,
    BoardColumn target,
  ) {
    final columnField = board.fields.columnField;
    final ops = <Map<String, Object?>>[];
    if (columnField != null) {
      ops.add({'op': 'add', 'path': '/fields/$columnField', 'value': target.name});
    }
    final state = target.stateMappings[item.type];
    if (state != null && state != item.state) {
      ops.add({'op': 'add', 'path': '/fields/System.State', 'value': state});
    }
    final doneField = board.fields.doneField;
    if (target.isSplit && doneField != null) {
      ops.add({'op': 'add', 'path': '/fields/$doneField', 'value': false});
    }
    return ops;
  }

  Future<WorkItem> move(
    String org,
    String project,
    Board board,
    WorkItem item,
    BoardColumn target,
  ) => _workItems.patch(org, project, item, moveOps(board, item, target));
}
