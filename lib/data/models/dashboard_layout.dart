import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'dashboard.dart';

/// One widget, placed: its widget plus the span it actually gets on this
/// device, which is the web's [DashboardWidget.columnSpan] clamped to the
/// number of columns that fit.
class PlacedWidget extends Equatable {
  const PlacedWidget({
    required this.widget,
    required this.column,
    required this.columnSpan,
    required this.rowSpan,
  });

  final DashboardWidget widget;

  /// 1-based, within the laid-out grid (not the web's).
  final int column;
  final int columnSpan;

  /// The web's row span, unchanged: it is the card's relative height, and
  /// the page multiplies it by a row height (research/19 §4.2).
  final int rowSpan;

  @override
  List<Object?> get props => [widget, column, columnSpan, rowSpan];
}

/// One laid-out row: the widgets that share it, left to right, and the tallest
/// row span among them.
class LayoutRow extends Equatable {
  const LayoutRow(this.widgets);

  final List<PlacedWidget> widgets;

  int get rowSpan => widgets.fold(1, (m, w) => math.max(m, w.rowSpan));

  int get columnsUsed => widgets.fold(0, (m, w) => m + w.columnSpan);

  @override
  List<Object?> get props => [widgets];
}

/// The pure grid mapper behind the dashboard page (decision D4).
///
/// The web lays widgets out on a **10-column** grid with 1-based positions.
/// A phone cannot show that, and horizontal scrolling is out, so:
///
/// * **phones get one column** and the widgets stack in reading order (row,
///   then column) — what every native dashboard app in the survey does;
/// * **tablets get `min(webColumns, floor(width / 168))` columns**, packed
///   first-fit in reading order with each `columnSpan` clamped to the grid
///   width, so a two-wide card stays twice as wide as a one-wide card and the
///   dashboard keeps the shape its author gave it.
///
/// Nothing here knows about Flutter: it is arithmetic over the widget list,
/// which is why it is unit-testable at 390, 700 and 1120 dp.
abstract final class DashboardLayout {
  /// The narrowest a card may be before it stops being readable. Chosen so a
  /// 700 dp tablet pane gets four columns and a 1120 dp one gets six, which
  /// is what the web draws at the same widths.
  static const columnWidth = 168.0;

  /// Below this the layout is always one column (D4: phones stack).
  static const singleColumnMaxWidth = 600.0;

  /// The web grid's width.
  static const webGridColumns = 10;

  /// How many columns the dashboard's own widgets actually occupy: a
  /// three-widget dashboard that never reaches column 5 is not stretched to
  /// ten.
  static int webColumns(List<DashboardWidget> widgets) {
    var used = 1;
    for (final w in widgets) {
      final span = w.columnSpan < 1 ? 1 : w.columnSpan;
      final right = w.column - 1 + span;
      if (right > used) used = right;
    }
    if (used < 1) return 1;
    return used > webGridColumns ? webGridColumns : used;
  }

  /// The number of columns to lay [widgets] out in at [width] logical pixels
  /// of *content* width (the page's, inside its padding).
  static int columnsFor(
    double width, {
    required List<DashboardWidget> widgets,
  }) {
    if (width < singleColumnMaxWidth) return 1;
    final fits = (width / columnWidth).floor();
    final columns = math.min(webColumns(widgets), fits);
    return columns < 1 ? 1 : columns;
  }

  /// Packs [widgets] into rows of [columns] columns.
  ///
  /// Reading order is preserved (row, then column), each widget's span is
  /// clamped to `columns`, and a widget that does not fit in what is left of
  /// the current row starts a new one. Disabled widgets are dropped: the
  /// service keeps them on the dashboard and the web does not draw them.
  static List<LayoutRow> layout(List<DashboardWidget> widgets, int columns) {
    final width = columns < 1 ? 1 : columns;
    final ordered = [...widgets.where((w) => w.isEnabled)]
      ..sort((a, b) {
        final byRow = a.row.compareTo(b.row);
        return byRow != 0 ? byRow : a.column.compareTo(b.column);
      });
    final rows = <LayoutRow>[];
    var current = <PlacedWidget>[];
    var used = 0;
    for (final widget in ordered) {
      final raw = widget.columnSpan < 1 ? 1 : widget.columnSpan;
      final span = raw > width ? width : raw;
      if (used + span > width && current.isNotEmpty) {
        rows.add(LayoutRow(current));
        current = <PlacedWidget>[];
        used = 0;
      }
      current.add(
        PlacedWidget(
          widget: widget,
          column: used + 1,
          columnSpan: span,
          rowSpan: widget.rowSpan < 1 ? 1 : widget.rowSpan,
        ),
      );
      used += span;
      if (used >= width) {
        rows.add(LayoutRow(current));
        current = <PlacedWidget>[];
        used = 0;
      }
    }
    if (current.isNotEmpty) rows.add(LayoutRow(current));
    return rows;
  }

  /// [layout] at the column count [columnsFor] picks for [width].
  static List<LayoutRow> layoutFor(
    List<DashboardWidget> widgets,
    double width,
  ) => layout(widgets, columnsFor(width, widgets: widgets));
}
