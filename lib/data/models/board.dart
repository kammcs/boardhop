import 'package:equatable/equatable.dart';

class BoardSummary extends Equatable {
  const BoardSummary({required this.id, required this.name});

  factory BoardSummary.fromJson(Map<String, dynamic> json) => BoardSummary(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
  );

  final String id;
  final String name;

  @override
  List<Object?> get props => [id];
}

class BoardColumn extends Equatable {
  const BoardColumn({
    required this.id,
    required this.name,
    required this.columnType,
    this.itemLimit = 0,
    this.isSplit = false,
    this.description,
    this.stateMappings = const {},
  });

  factory BoardColumn.fromJson(Map<String, dynamic> json) => BoardColumn(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    columnType: json['columnType'] as String? ?? 'inProgress',
    itemLimit: (json['itemLimit'] as num?)?.toInt() ?? 0,
    isSplit: json['isSplit'] as bool? ?? false,
    description: json['description'] as String?,
    stateMappings:
        (json['stateMappings'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ) ??
        const {},
  );

  final String id;
  final String name;

  /// `incoming`, `inProgress` or `outgoing`.
  final String columnType;
  final int itemLimit;
  final bool isSplit;
  final String? description;

  /// Work item type → state a card takes when it lands here.
  final Map<String, String> stateMappings;

  @override
  List<Object?> get props => [id, name, columnType, itemLimit, isSplit];
}

class BoardRow extends Equatable {
  const BoardRow({this.id, this.name, this.color});

  factory BoardRow.fromJson(Map<String, dynamic> json) => BoardRow(
    id: json['id'] as String?,
    name: json['name'] as String?,
    color: json['color'] as String?,
  );

  final String? id;
  final String? name;
  final String? color;

  @override
  List<Object?> get props => [id, name];
}

/// The per-team `WEF_{guid}_Kanban.*` field names. Always read from the
/// board; they cannot be derived from the board id (spike S10).
class BoardFields extends Equatable {
  const BoardFields({this.columnField, this.rowField, this.doneField});

  factory BoardFields.fromJson(Map<String, dynamic> json) => BoardFields(
    columnField: (json['columnField'] as Map?)?['referenceName'] as String?,
    rowField: (json['rowField'] as Map?)?['referenceName'] as String?,
    doneField: (json['doneField'] as Map?)?['referenceName'] as String?,
  );

  final String? columnField;
  final String? rowField;
  final String? doneField;

  @override
  List<Object?> get props => [columnField, rowField, doneField];
}

class Board extends Equatable {
  const Board({
    required this.id,
    required this.name,
    required this.columns,
    required this.rows,
    required this.fields,
    this.allowedMappings = const {},
    this.canEdit = false,
    this.isValid = true,
  });

  factory Board.fromJson(Map<String, dynamic> json) => Board(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    columns: ((json['columns'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => BoardColumn.fromJson(m.cast<String, dynamic>()))
        .toList(),
    rows: ((json['rows'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => BoardRow.fromJson(m.cast<String, dynamic>()))
        .toList(),
    fields: BoardFields.fromJson(
      (json['fields'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    allowedMappings: ((json['allowedMappings'] as Map?) ?? const {}).map(
      (columnType, byType) => MapEntry(
        columnType.toString(),
        ((byType as Map?) ?? const {}).map(
          (type, states) => MapEntry(
            type.toString(),
            ((states as List?) ?? const []).map((s) => s.toString()).toList(),
          ),
        ),
      ),
    ),
    canEdit: json['canEdit'] as bool? ?? false,
    isValid: json['isValid'] as bool? ?? true,
  );

  final String id;
  final String name;
  final List<BoardColumn> columns;
  final List<BoardRow> rows;
  final BoardFields fields;

  /// columnType → work item type → allowed states.
  final Map<String, Map<String, List<String>>> allowedMappings;
  final bool canEdit;
  final bool isValid;

  /// One drop target per column, two for a split column (Doing, Done).
  List<BoardSlot> get slots => [
    for (var i = 0; i < columns.length; i++)
      if (columns[i].isSplit) ...[
        BoardSlot(columnIndex: i, column: columns[i], done: false),
        BoardSlot(columnIndex: i, column: columns[i], done: true),
      ] else
        BoardSlot(columnIndex: i, column: columns[i]),
  ];

  /// Lane names in board order; the default lane is the empty string.
  List<String> get laneNames => [for (final r in rows) r.name ?? ''];

  bool get hasLanes => rows.length > 1;

  /// Work item types that live on this board.
  Set<String> get workItemTypes => {
    for (final byType in allowedMappings.values) ...byType.keys,
    for (final c in columns) ...c.stateMappings.keys,
  };

  /// Column index for a card: the WEF column value when present, else the
  /// first column whose state mapping for the type equals the state, else
  /// the first column.
  int columnIndexFor({
    required String type,
    required String state,
    String? columnValue,
  }) {
    if (columnValue != null) {
      final i = columns.indexWhere((c) => c.name == columnValue);
      if (i >= 0) return i;
    }
    final byState = columns.indexWhere((c) => c.stateMappings[type] == state);
    return byState >= 0 ? byState : 0;
  }

  @override
  List<Object?> get props => [id, name, columns, rows, fields, canEdit];
}

/// A drop target on the board: a column, or one half of a split column.
class BoardSlot extends Equatable {
  const BoardSlot({required this.columnIndex, required this.column, this.done});

  final int columnIndex;
  final BoardColumn column;

  /// null for a plain column; false = Doing half, true = Done half.
  final bool? done;

  String get id =>
      done == null ? column.id : '${column.id}/${done! ? 'done' : 'doing'}';
  String get title => column.name;
  String? get subtitle => switch (done) {
    null => null,
    false => 'Doing',
    true => 'Done',
  };

  @override
  List<Object?> get props => [column.id, done];
}

/// `GET .../work/teamsettings/teamfieldvalues`: the area paths the team's
/// board shows.
class TeamFieldValues extends Equatable {
  const TeamFieldValues({
    required this.field,
    required this.defaultValue,
    required this.values,
  });

  factory TeamFieldValues.fromJson(Map<String, dynamic> json) =>
      TeamFieldValues(
        field:
            (json['field'] as Map?)?['referenceName'] as String? ??
            'System.AreaPath',
        defaultValue: json['defaultValue'] as String? ?? '',
        values: ((json['values'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (m) => (
                value: m['value'] as String? ?? '',
                includeChildren: m['includeChildren'] as bool? ?? false,
              ),
            )
            .toList(),
      );

  final String field;
  final String defaultValue;
  final List<({String value, bool includeChildren})> values;

  @override
  List<Object?> get props => [field, defaultValue, values];
}
