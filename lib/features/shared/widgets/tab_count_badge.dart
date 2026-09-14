import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

/// A count on a tab label: "Comments ⟨3⟩".
///
/// The pill is quiet chrome — `surfaceContainerHighest` under
/// `onSurfaceVariant` — and lifts to the secondary container on the tab that
/// is selected, because the slate theme signals selection by weight rather
/// than by a tint (DESIGN.md §6). A count of zero, or one that is not known
/// yet, shows nothing at all: an empty pill is noise, and a "0" that turns
/// into a "3" a second later reads as a change that did not happen.
class TabCountBadge extends StatelessWidget {
  const TabCountBadge({super.key, required this.count, this.selected = false});

  /// Null while the page is still reading; nothing is drawn either way.
  final int? count;

  final bool selected;

  /// The gap before the pill, and the pill's own padding on each side.
  static const double _gap = Spacing.xs;
  static const double _sidePadding = Spacing.xs + 2;

  /// What a pill for [count] takes beside its label, gap included. Zero when
  /// nothing is drawn; [tabsMustScroll] budgets with it.
  static double widthFor(int? count, TextStyle? style, TextScaler scaler) =>
      count == null || count <= 0
      ? 0
      : _textWidth('$count', style, scaler) + _gap + _sidePadding * 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = count;
    if (value == null || value <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: _gap),
      padding: const EdgeInsets.symmetric(
        horizontal: _sidePadding,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.pill)),
      ),
      child: Text(
        '$value',
        style: theme.textTheme.labelSmall?.copyWith(
          color: selected
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
          height: 1.1,
        ),
      ),
    );
  }
}

/// One tab of a [CountedTabBar]: its label, and the count on its pill.
@immutable
class TabCount {
  const TabCount(this.label, [this.count]);

  final String label;

  /// Null or zero draws no pill.
  final int? count;
}

/// A tab strip whose labels carry [TabCountBadge] pills, scrolling only when
/// dividing the width evenly would squeeze one of them.
///
/// Shared so the work item and pull request pages read the same (Kelly,
/// 2026-09-14).
class CountedTabBar extends StatelessWidget implements PreferredSizeWidget {
  const CountedTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<TabCount> tabs;

  /// Tighter than Material's own 16 a side: the pill needs the room, and
  /// in an evenly divided strip the padding is only the label's minimum
  /// breathing space, not the gap between the tabs.
  static const EdgeInsets labelPadding = EdgeInsets.symmetric(
    horizontal: Spacing.sm,
  );

  TabBar _bar({required bool scrolling}) => TabBar(
    controller: controller,
    isScrollable: scrolling,
    tabAlignment: scrolling ? TabAlignment.start : null,
    labelPadding: labelPadding,
    tabs: [
      for (var i = 0; i < tabs.length; i++)
        _countedTab(
          label: tabs[i].label,
          count: tabs[i].count,
          selected: controller.index == i,
        ),
    ],
  );

  @override
  Size get preferredSize => _bar(scrolling: false).preferredSize;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // The width the strip actually has, not the window's: the work item
    // page is also drawn inside the tablet's detail pane.
    builder: (context, constraints) => _bar(
      scrolling: tabsMustScroll(
        context,
        width: constraints.maxWidth,
        tabs: tabs,
      ),
    ),
  );
}

/// One [Tab] whose label carries a [TabCountBadge].
///
/// The label is the flexible half, so a strip that is a hair too narrow
/// fades the word rather than overflowing the pill off the end.
Tab _countedTab({required String label, int? count, bool selected = false}) =>
    Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(label, softWrap: false, overflow: TextOverflow.fade),
          ),
          TabCountBadge(count: count, selected: selected),
        ],
      ),
    );

/// Whether a strip of [tabs] has to scroll rather than divide [width]
/// evenly between them.
///
/// Measured, not guessed. Three filled thirds clipped "Comments (3)" at
/// accessibility text sizes (iPhone walkthrough, defect 10), and a count
/// pill beside the word costs another ~28 dp, which a third of a phone
/// cannot always spare even at the ordinary size. Each tab wants its label
/// whole, its pill beside it, the strip's own label padding and [_slack] —
/// a hair over, and the fade shaves the last letter, as "Comments 14" did
/// on the iPhone at the ordinary size. When an even share is less than the
/// widest of those, the strip scrolls and every label stays readable.
bool tabsMustScroll(
  BuildContext context, {
  required double width,
  required List<TabCount> tabs,
}) {
  if (tabs.isEmpty || width <= 0) return false;
  final theme = Theme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final labelStyle = theme.tabBarTheme.labelStyle ?? theme.textTheme.titleSmall;
  final countStyle = theme.textTheme.labelSmall;
  var widest = 0.0;
  for (final tab in tabs) {
    widest = math.max(
      widest,
      _textWidth(tab.label, labelStyle, scaler) +
          TabCountBadge.widthFor(tab.count, countStyle, scaler),
    );
  }
  return width / tabs.length <
      widest + CountedTabBar.labelPadding.horizontal + _slack;
}

/// Room to spare before the strip is called wide enough: a measurement that
/// lands within a point or two of the width still fades the last letter.
const double _slack = Spacing.sm;

double _textWidth(String text, TextStyle? style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
