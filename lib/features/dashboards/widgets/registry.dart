import 'package:flutter/material.dart';

import '../../../data/models/dashboard.dart';
import '../team_overview.dart';
import 'cards/assigned_to_me_card.dart';
import 'cards/build_history_card.dart';
import 'cards/code_tile_card.dart';
import 'cards/links_card.dart';
import 'cards/markdown_card.dart';
import 'cards/pull_requests_card.dart';
import 'cards/query_results_card.dart';
import 'cards/query_tile_card.dart';
import 'cards/sprint_overview_card.dart';
import 'cards/team_members_card.dart';
import 'dashboard_card.dart';

typedef DashboardCardBuilder = Widget Function(DashboardCardArgs args);

/// Which widget kinds Boardhop draws, what draws them, and how tall a card
/// of each is allowed to get on a phone.
///
/// One place decides all three so the page never has to reason about kinds:
/// it asks [cardFor] for a builder and, when the answer is null, counts the
/// widget into the footer line (D10).
abstract final class DashboardRegistry {
  /// The kinds Boardhop will never draw (D10, and D2 for the work item
  /// chart), listed rather than inferred so adding a card is one line in
  /// [cardFor] and nothing else.
  ///
  /// * `workItemChart` — its settings hold only a `chartId`, `artifactId`
  ///   is empty and no chart route exists, so the app cannot even find the
  ///   query behind it (D2, revised after w36).
  /// * `embeddedWebpage` — an iframe.
  /// * the release, deployment and test kinds — classic Release lives on
  ///   another host and has no data here; the test widgets need Test Plans.
  /// * `sprintCapacity` — no puremedia sprint has capacity data at all.
  /// * `marketplace` and `unknown` — a third party's widget, or a first
  ///   party one this version has never heard of.
  static const hiddenKinds = <WidgetKind>{
    WidgetKind.workItemChart,
    WidgetKind.embeddedWebpage,
    WidgetKind.releaseOverview,
    WidgetKind.deploymentStatus,
    WidgetKind.testResultsTrend,
    WidgetKind.sprintCapacity,
    WidgetKind.marketplace,
    WidgetKind.unknown,
  };

  /// Kinds whose card cannot be drawn without typed settings: settings that
  /// fail to parse hide the widget (D10). The kinds that store `null`
  /// settings on purpose — the links, Assigned to Me, Team Members, Pull
  /// Requests — are deliberately not in here.
  static const needsSettings = <WidgetKind>{
    WidgetKind.queryTile,
    WidgetKind.queryResults,
    WidgetKind.buildHistory,
    WidgetKind.codeTile,
    WidgetKind.markdown,
    WidgetKind.burndown,
    WidgetKind.burnup,
    WidgetKind.sprintBurndown,
    WidgetKind.sprintBurndownLegacy,
    WidgetKind.cycleTime,
    WidgetKind.leadTime,
    WidgetKind.cumulativeFlow,
  };

  /// The chart kinds: recognised, laid out and named, but drawn by the
  /// placeholder until the charting phase lands. They are **not** hidden —
  /// a person who put a burndown on their dashboard should see it named
  /// where they put it, not be told a widget is missing.
  static const chartKinds = <WidgetKind>{
    WidgetKind.burndown,
    WidgetKind.burnup,
    WidgetKind.sprintBurndown,
    WidgetKind.sprintBurndownLegacy,
    WidgetKind.cycleTime,
    WidgetKind.leadTime,
    WidgetKind.cumulativeFlow,
    WidgetKind.velocity,
  };

  /// How tall a card of this kind may get on a phone, where cards size
  /// themselves (D4). Null is "as tall as its content".
  static double? phoneCap(DashboardWidget widget) {
    if (widget.isBuiltIn) return 240;
    return switch (widget.kind) {
      WidgetKind.queryResults ||
      WidgetKind.assignedToMe ||
      WidgetKind.pullRequests => 420,
      WidgetKind.teamMembers => 320,
      WidgetKind.markdown => 360,
      _ when chartKinds.contains(widget.kind) => 240,
      _ => null,
    };
  }

  /// True when the widget is drawn at all. A widget that is disabled on the
  /// service is already dropped by the layout mapper.
  static bool renders(DashboardWidget widget) => cardFor(widget) != null;

  /// The builder for [widget], or null when Boardhop hides it (D10).
  static DashboardCardBuilder? cardFor(DashboardWidget widget) {
    if (widget.isBuiltIn) {
      final note = TeamOverview.noteFor(widget.builtInKind);
      return (args) => ComingCard(args: args, note: note);
    }
    final kind = widget.kind;
    if (hiddenKinds.contains(kind)) return null;
    final settings = parseWidgetSettings(widget);
    if (needsSettings.contains(kind) && settings == null) return null;

    switch (kind) {
      case WidgetKind.queryTile:
        final typed = settings! as QueryTileSettings;
        return (args) => QueryTileCard(args: args, settings: typed);
      case WidgetKind.queryResults:
        final typed = settings! as QueryResultsSettings;
        return (args) => QueryResultsCard(args: args, settings: typed);
      case WidgetKind.assignedToMe:
        return (args) => AssignedToMeCard(args: args);
      case WidgetKind.pullRequests:
        return (args) => PullRequestsCard(args: args);
      case WidgetKind.teamMembers:
        return (args) => TeamMembersCard(args: args);
      case WidgetKind.markdown:
        final typed = settings! as MarkdownSettings;
        // The repo-file variant needs a file read per card and is out of
        // this phase (research/19 §4.2); the widget still shows its name.
        if (typed.isFile) return (args) => EmptyMarkdownCard(args: args);
        if (typed.content.trim().isEmpty) {
          return (args) => EmptyMarkdownCard(args: args);
        }
        return (args) => MarkdownCard(args: args, settings: typed);
      case WidgetKind.newWorkItem ||
          WidgetKind.welcome ||
          WidgetKind.otherLinks ||
          WidgetKind.vsShortcuts ||
          WidgetKind.workLinks:
        return (args) => LinksCard(args: args);
      case WidgetKind.buildHistory:
        final typed = settings! as BuildHistorySettings;
        return (args) => BuildHistoryCard(args: args, settings: typed);
      case WidgetKind.codeTile:
        final typed = settings! as CodeTileSettings;
        return (args) => CodeTileCard(args: args, settings: typed);
      case WidgetKind.sprintOverview:
        return (args) => SprintOverviewCard(args: args);
      case _ when chartKinds.contains(kind):
        return (args) => ComingCard(args: args);
      default:
        return null;
    }
  }
}
