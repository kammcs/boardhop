import 'package:boardhop/data/models/dashboard.dart';
import 'package:boardhop/data/models/dashboard_layout.dart';
import 'package:flutter_test/flutter_test.dart';

const dashboards = 'ms.vss-dashboards-web.Microsoft.VisualStudioOnline'
    '.Dashboards';

DashboardWidget w(
  String id, {
  int row = 1,
  int column = 1,
  int rowSpan = 1,
  int columnSpan = 1,
  bool isEnabled = true,
  String contributionId = '$dashboards.QueryScalarWidget',
}) => DashboardWidget(
  id: id,
  name: id,
  contributionId: contributionId,
  row: row,
  column: column,
  rowSpan: rowSpan,
  columnSpan: columnSpan,
  isEnabled: isEnabled,
);

/// The scratch project's Overview after spike w36: thirteen widgets on the
/// web's ten-column grid, the shape decision D4 has to survive.
final scratchOverview = <DashboardWidget>[
  w('query-tile', row: 1, column: 1),
  w('code-tile', row: 1, column: 2),
  w('build-history', row: 1, column: 3, columnSpan: 2),
  w('sprint-overview', row: 1, column: 5, columnSpan: 2),
  w('markdown', row: 1, column: 7, rowSpan: 2, columnSpan: 2),
  w('query-results', row: 2, column: 1, rowSpan: 2, columnSpan: 3),
  w('wit-chart', row: 2, column: 4, rowSpan: 2, columnSpan: 2),
  w('cfd', row: 4, column: 1, rowSpan: 2, columnSpan: 3),
  w('cycle-time', row: 4, column: 4, rowSpan: 2, columnSpan: 3),
  w('lead-time', row: 4, column: 7, rowSpan: 2, columnSpan: 3),
  w('velocity', row: 6, column: 1, rowSpan: 2, columnSpan: 3),
  w('pull-requests', row: 6, column: 4, rowSpan: 2, columnSpan: 3),
  w('assigned-to-me', row: 6, column: 7, rowSpan: 2, columnSpan: 3),
];

List<String> idsOf(List<LayoutRow> rows) => [
  for (final row in rows)
    for (final placed in row.widgets) placed.widget.id,
];

void main() {
  group('columnsFor', () {
    test('a phone at 390 dp is always one column', () {
      expect(DashboardLayout.columnsFor(390, widgets: scratchOverview), 1);
      // Even a landscape phone below the tablet breakpoint stacks.
      expect(DashboardLayout.columnsFor(599, widgets: scratchOverview), 1);
    });

    test('a 700 dp tablet pane gets four columns', () {
      // floor(700 / 168) = 4, and the dashboard is ten wide.
      expect(DashboardLayout.columnsFor(700, widgets: scratchOverview), 4);
    });

    test('a 1120 dp tablet gets six', () {
      expect(DashboardLayout.columnsFor(1120, widgets: scratchOverview), 6);
    });

    test('never wider than the dashboard the author drew', () {
      final narrow = [w('a'), w('b', column: 2)];
      // Two columns used on the web, so a 1120 dp tablet still gets two.
      expect(DashboardLayout.webColumns(narrow), 2);
      expect(DashboardLayout.columnsFor(1120, widgets: narrow), 2);
    });

    test('never wider than the web grid', () {
      final wide = [w('a', column: 9, columnSpan: 6)];
      expect(DashboardLayout.webColumns(wide), 10);
      expect(DashboardLayout.columnsFor(4000, widgets: wide), 10);
    });

    test('a dashboard with no widgets is one column', () {
      expect(DashboardLayout.webColumns(const []), 1);
      expect(DashboardLayout.columnsFor(1120, widgets: const []), 1);
    });
  });

  group('layout at one column (phones, D4)', () {
    test('every widget is its own row, in reading order', () {
      final rows = DashboardLayout.layout(scratchOverview, 1);
      expect(rows.length, scratchOverview.length);
      expect(rows.every((r) => r.widgets.length == 1), isTrue);
      expect(idsOf(rows), [
        'query-tile',
        'code-tile',
        'build-history',
        'sprint-overview',
        'markdown',
        'query-results',
        'wit-chart',
        'cfd',
        'cycle-time',
        'lead-time',
        'velocity',
        'pull-requests',
        'assigned-to-me',
      ]);
    });

    test('every span is clamped to the one column available', () {
      final rows = DashboardLayout.layout(scratchOverview, 1);
      expect(rows.every((r) => r.widgets.single.columnSpan == 1), isTrue);
      expect(rows.every((r) => r.widgets.single.column == 1), isTrue);
    });

    test('the web row span survives as the card\'s relative height', () {
      final rows = DashboardLayout.layout(scratchOverview, 1);
      final markdown = rows.firstWhere(
        (r) => r.widgets.single.widget.id == 'markdown',
      );
      expect(markdown.rowSpan, 2);
      final tile = rows.firstWhere(
        (r) => r.widgets.single.widget.id == 'query-tile',
      );
      expect(tile.rowSpan, 1);
    });
  });

  group('layout at four columns (a 700 dp tablet)', () {
    late List<LayoutRow> rows;

    setUp(() => rows = DashboardLayout.layoutFor(scratchOverview, 700));

    test('reading order is preserved across the rows', () {
      expect(idsOf(rows), [
        for (final widget in scratchOverview) widget.id,
      ]);
    });

    test('no row is wider than the grid', () {
      expect(rows.every((r) => r.columnsUsed <= 4), isTrue);
    });

    test('a three-wide card stays three wide, a one-wide card stays one', () {
      final placed = {
        for (final row in rows)
          for (final p in row.widgets) p.widget.id: p,
      };
      expect(placed['query-tile']!.columnSpan, 1);
      expect(placed['build-history']!.columnSpan, 2);
      expect(placed['cfd']!.columnSpan, 3);
    });

    test('the first row packs the two 1x1 tiles beside the 1x2 tile', () {
      expect(idsOf([rows.first]), ['query-tile', 'code-tile', 'build-history']);
      expect(rows.first.columnsUsed, 4);
      expect(rows.first.widgets.map((p) => p.column), [1, 2, 3]);
    });

    test('a card that does not fit what is left starts a new row', () {
      // Sprint Overview (2) + Markdown (2) fill the second row exactly.
      expect(idsOf([rows[1]]), ['sprint-overview', 'markdown']);
      // Query Results is 3 wide: the Chart (2) cannot join it.
      expect(idsOf([rows[2]]), ['query-results']);
      expect(idsOf([rows[3]]), ['wit-chart']);
    });
  });

  group('layout at six columns (a 1120 dp tablet)', () {
    late List<LayoutRow> rows;

    setUp(() => rows = DashboardLayout.layoutFor(scratchOverview, 1120));

    test('reading order is preserved', () {
      expect(idsOf(rows), [
        for (final widget in scratchOverview) widget.id,
      ]);
    });

    test('no row is wider than six', () {
      expect(rows.every((r) => r.columnsUsed <= 6), isTrue);
    });

    test('two three-wide charts share a row when nothing precedes them', () {
      final together = rows.firstWhere(
        (r) => r.widgets.any((p) => p.widget.id == 'cycle-time'),
      );
      expect(idsOf([together]), ['cycle-time', 'lead-time']);
      expect(together.widgets.map((p) => p.column), [1, 4]);
      expect(together.rowSpan, 2);
    });

    test('packing is greedy, so a chart follows whatever left room', () {
      // Query Results (3) leaves one column of the second row, so the 2-wide
      // chart drops to the third row and the CFD joins it there rather than
      // waiting for a row of its own.
      final withCfd = rows.firstWhere(
        (r) => r.widgets.any((p) => p.widget.id == 'cfd'),
      );
      expect(idsOf([withCfd]), ['wit-chart', 'cfd']);
      expect(withCfd.columnsUsed, 5);
    });
  });

  group('edge cases', () {
    test('a disabled widget is not laid out', () {
      final rows = DashboardLayout.layout([
        w('a'),
        w('off', column: 2, isEnabled: false),
        w('b', column: 3),
      ], 4);
      expect(idsOf(rows), ['a', 'b']);
    });

    test('a widget wider than the grid is clamped, not dropped', () {
      final rows = DashboardLayout.layout([w('wide', columnSpan: 10)], 4);
      expect(rows.single.widgets.single.columnSpan, 4);
    });

    test('a nonsense span or column count does not break the packing', () {
      final rows = DashboardLayout.layout([
        w('zero', columnSpan: 0, rowSpan: 0),
        w('negative', column: 2, columnSpan: -3),
      ], 0);
      expect(rows.length, 2);
      expect(rows.first.widgets.single.columnSpan, 1);
      expect(rows.first.widgets.single.rowSpan, 1);
    });

    test('widgets out of wire order are sorted into reading order', () {
      final rows = DashboardLayout.layout([
        w('third', row: 2, column: 1),
        w('first', row: 1, column: 1),
        w('second', row: 1, column: 4),
      ], 1);
      expect(idsOf(rows), ['first', 'second', 'third']);
    });

    test('an empty dashboard lays out to nothing', () {
      expect(DashboardLayout.layout(const [], 4), isEmpty);
    });
  });
}
