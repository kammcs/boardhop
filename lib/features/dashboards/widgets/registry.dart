import 'package:flutter/material.dart';

import '../../../data/models/dashboard.dart';
import '../charts/chart_payload.dart';
import '../team_overview.dart';
import 'cards/assigned_to_me_card.dart';
import 'cards/build_history_card.dart';
import 'cards/burndown_card.dart';
import 'cards/cfd_card.dart';
import 'cards/code_tile_card.dart';
import 'cards/cycle_time_card.dart';
import 'cards/links_card.dart';
import 'cards/markdown_card.dart';
import 'cards/pipeline_outcomes_card.dart';
import 'cards/pull_requests_card.dart';
import 'cards/query_results_card.dart';
import 'cards/query_tile_card.dart';
import 'cards/sprint_burndown_card.dart';
import 'cards/sprint_overview_card.dart';
import 'cards/team_members_card.dart';
import 'cards/velocity_card.dart';
import 'cards/work_by_state_card.dart';
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

  /// The kinds drawn by a chart (phase D-C). They all read Analytics, so
  /// they all degrade on their own through the D14 notice, and they all
  /// open the focus view when tapped (D7).
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

  /// True when tapping the card opens the chart focus view (D7) rather
  /// than a page of the app.
  static bool isChart(DashboardWidget widget) =>
      widget.isBuiltIn || chartKinds.contains(widget.kind);

  /// The builder for [widget], or null when Boardhop hides it (D10).
  static DashboardCardBuilder? cardFor(DashboardWidget widget) {
    if (widget.isBuiltIn) return _builtIn(widget.builtInKind);
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
      case WidgetKind.burndown || WidgetKind.burnup:
        final typed = settings! as BurndownSettings;
        return (args) => BurndownCard(
          args: args,
          settings: typed,
          burnup: kind == WidgetKind.burnup,
        );
      case WidgetKind.sprintBurndown || WidgetKind.sprintBurndownLegacy:
        final typed = settings! as SprintBurndownSettings;
        return (args) => SprintBurndownCard(args: args, settings: typed);
      case WidgetKind.velocity:
        // Velocity's settings are null on every dashboard seen, and the
        // parser answers `defaults` rather than null for that (D3).
        final typed =
            settings as VelocitySettings? ?? VelocitySettings.defaults;
        return (args) => VelocityCard(args: args, settings: typed);
      case WidgetKind.cumulativeFlow:
        final typed = settings! as CfdSettings;
        return (args) => CfdCard(args: args, settings: typed);
      case WidgetKind.cycleTime || WidgetKind.leadTime:
        final typed = settings! as CycleTimeSettings;
        return (args) => CycleTimeCard(
          args: args,
          settings: typed,
          lead: kind == WidgetKind.leadTime,
        );
      default:
        return null;
    }
  }

  /// The Team overview's six cards (D9). Each is the same card class the
  /// matching dashboard widget uses, with no settings behind it.
  static DashboardCardBuilder? _builtIn(String builtInKind) =>
      switch (builtInKind) {
        TeamOverview.sprintBurndown => (args) => SprintBurndownCard(args: args),
        TeamOverview.workByState => (args) => WorkByStateCard(args: args),
        TeamOverview.cumulativeFlow => (args) => CfdCard(args: args),
        TeamOverview.cycleLeadTime => (args) => CycleTimeCard(
          args: args,
          showBoth: true,
        ),
        TeamOverview.velocity => (args) => VelocityCard(
          args: args,
          settings: VelocitySettings.defaults,
        ),
        TeamOverview.pipelineOutcomes => (args) => PipelineOutcomesCard(
          args: args,
        ),
        _ => (args) => ComingCard(args: args),
      };

  /// Loads a chart's data without its card — what the focus view uses when
  /// it is opened cold and has no payload to draw (D7).
  ///
  /// The same `load` each card calls, so a focus view opened from a deep
  /// link shows exactly what the card would have.
  static Future<ChartPayload?> loadChart(
    BuildContext context,
    DashboardCardArgs args, {
    required bool refresh,
  }) {
    final widget = args.widget;
    if (widget.isBuiltIn) {
      return switch (widget.builtInKind) {
        TeamOverview.sprintBurndown => SprintBurndownCard.load(
          context,
          args,
          null,
          refresh: refresh,
        ),
        TeamOverview.workByState => WorkByStateCard.load(
          context,
          args,
          refresh: refresh,
        ),
        TeamOverview.cumulativeFlow => CfdCard.load(
          context,
          args,
          null,
          refresh: refresh,
        ),
        TeamOverview.cycleLeadTime => CycleTimeCard.load(
          context,
          args,
          null,
          lead: false,
          showBoth: true,
          refresh: refresh,
        ),
        TeamOverview.velocity => VelocityCard.load(
          context,
          args,
          VelocitySettings.defaults,
          refresh: refresh,
        ),
        TeamOverview.pipelineOutcomes => PipelineOutcomesCard.load(
          context,
          args,
          refresh: refresh,
        ),
        _ => Future<ChartPayload?>.value(),
      };
    }
    final settings = parseWidgetSettings(widget);
    return switch (widget.kind) {
      WidgetKind.burndown ||
      WidgetKind.burnup when settings is BurndownSettings => BurndownCard.load(
        context,
        args,
        settings,
        burnup: widget.kind == WidgetKind.burnup,
        refresh: refresh,
      ),
      WidgetKind.sprintBurndown || WidgetKind.sprintBurndownLegacy
          when settings is SprintBurndownSettings =>
        SprintBurndownCard.load(context, args, settings, refresh: refresh),
      WidgetKind.velocity => VelocityCard.load(
        context,
        args,
        settings as VelocitySettings? ?? VelocitySettings.defaults,
        refresh: refresh,
      ),
      WidgetKind.cumulativeFlow when settings is CfdSettings => CfdCard.load(
        context,
        args,
        settings,
        refresh: refresh,
      ),
      WidgetKind.cycleTime || WidgetKind.leadTime
          when settings is CycleTimeSettings =>
        CycleTimeCard.load(
          context,
          args,
          settings,
          lead: widget.kind == WidgetKind.leadTime,
          showBoth: false,
          refresh: refresh,
        ),
      _ => Future<ChartPayload?>.value(),
    };
  }
}
