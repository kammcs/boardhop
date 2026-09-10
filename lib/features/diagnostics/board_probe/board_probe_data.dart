import 'dart:math';
import 'dart:ui' show Color;

/// Generated Kanban data for spike F4. No client data: titles come from a
/// word bank, ids are sequential, colors imitate what the Boards API returns.
class ProbeColumn {
  ProbeColumn({
    required this.name,
    required this.stateName,
    required this.stateCategory,
    required this.apiColor,
  });

  final String name;
  final String stateName;
  final String stateCategory;

  /// What a team's column color from the Boards API would look like.
  final Color apiColor;
  final List<ProbeCard> cards = <ProbeCard>[];
}

class ProbeCard {
  const ProbeCard({
    required this.id,
    required this.title,
    required this.type,
    required this.assignee,
  });

  final int id;
  final String title;
  final String type;
  final String assignee;
}

class CardMove {
  const CardMove({
    required this.card,
    required this.fromColumn,
    required this.fromIndex,
    required this.toColumn,
    required this.toIndex,
  });

  final ProbeCard card;
  final int fromColumn;
  final int fromIndex;
  final int toColumn;
  final int toIndex;
}

class BoardData {
  BoardData(this.columns);

  final List<ProbeColumn> columns;

  int get cardCount => columns.fold(0, (n, c) => n + c.cards.length);

  /// Column and index of [card], or null if it is not on the board.
  (int, int)? locate(ProbeCard card) {
    for (var c = 0; c < columns.length; c++) {
      final i = columns[c].cards.indexWhere((x) => x.id == card.id);
      if (i >= 0) return (c, i);
    }
    return null;
  }

  /// Moves a card. [toIndex] is the index in the destination list after the
  /// card has been removed from its source (the convention every candidate
  /// package uses in its reorder callback).
  CardMove move({
    required int fromColumn,
    required int fromIndex,
    required int toColumn,
    required int toIndex,
  }) {
    final card = columns[fromColumn].cards.removeAt(fromIndex);
    final target = columns[toColumn].cards;
    final index = toIndex.clamp(0, target.length);
    target.insert(index, card);
    return CardMove(
      card: card,
      fromColumn: fromColumn,
      fromIndex: fromIndex,
      toColumn: toColumn,
      toIndex: index,
    );
  }

  static const _types = <String>[
    'Bug',
    'Task',
    'Task',
    'User Story',
    'User Story',
    'Feature',
    'Epic',
  ];

  static const _verbs = <String>[
    'Fix',
    'Add',
    'Remove',
    'Refactor',
    'Investigate',
    'Migrate',
    'Document',
    'Speed up',
    'Localize',
    'Retry',
  ];

  static const _objects = <String>[
    'checkout flow',
    'sprint burndown',
    'token refresh',
    'board column colors',
    'offline queue',
    'pull request list',
    'diff viewer',
    'push notifications',
    'attachment upload',
    'work item comments',
    'pipeline retry',
    'search index',
    'org picker',
    'dark mode contrast',
    'rate-limit backoff',
  ];

  static const _tails = <String>[
    '',
    ' on Android 17',
    ' for guest users',
    ' when offline',
    ' after sign-out',
    ' in landscape',
    ' with 500 items',
    ' behind a VPN',
  ];

  static const _people = <String>[
    'KK',
    'AM',
    'JR',
    'TS',
    'LP',
    'DN',
    'RB',
    'MG',
  ];

  /// Five columns shaped like a Scrum team's board, [cards] cards spread
  /// unevenly (most in the middle columns) so lists are long enough to
  /// scroll and short enough to be emptied after a few moves.
  static BoardData generate({int cards = 200, int seed = 42}) {
    final rng = Random(seed);
    final columns = <ProbeColumn>[
      ProbeColumn(
        name: 'New',
        stateName: 'New',
        stateCategory: 'Proposed',
        apiColor: const Color(0xFFB2B2B2),
      ),
      ProbeColumn(
        name: 'Active',
        stateName: 'Active',
        stateCategory: 'InProgress',
        apiColor: const Color(0xFF007ACC),
      ),
      ProbeColumn(
        name: 'Code Review',
        stateName: 'Active',
        stateCategory: 'InProgress',
        apiColor: const Color(0xFFC9B1E6),
      ),
      ProbeColumn(
        name: 'Testing',
        stateName: 'Resolved',
        stateCategory: 'Resolved',
        apiColor: const Color(0xFFF2CB1D),
      ),
      ProbeColumn(
        name: 'Done',
        stateName: 'Closed',
        stateCategory: 'Completed',
        apiColor: const Color(0xFF339947),
      ),
    ];
    const weights = <double>[0.20, 0.30, 0.20, 0.15, 0.15];
    for (var i = 0; i < cards; i++) {
      final title =
          '${_verbs[rng.nextInt(_verbs.length)]} '
          '${_objects[rng.nextInt(_objects.length)]}'
          '${_tails[rng.nextInt(_tails.length)]}';
      final card = ProbeCard(
        id: 10000 + i,
        title: title,
        type: _types[rng.nextInt(_types.length)],
        assignee: _people[rng.nextInt(_people.length)],
      );
      var r = rng.nextDouble();
      var column = weights.length - 1;
      for (var c = 0; c < weights.length; c++) {
        if (r < weights[c]) {
          column = c;
          break;
        }
        r -= weights[c];
      }
      columns[column].cards.add(card);
    }
    return BoardData(columns);
  }
}
