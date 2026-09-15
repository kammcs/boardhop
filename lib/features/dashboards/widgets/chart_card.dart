import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes.dart';
import '../../../theme/theme.dart';
import '../../shared/account_scope.dart';
import '../charts/chart_format.dart';
import '../charts/chart_payload.dart';
import 'dashboard_card.dart';

/// What the chart focus route (D7) is handed when a card opens it: the
/// card's place and the payload it already drew, so the focus view never
/// refetches what is on screen. A cold open — a deep link, or the app
/// restarted over the route — arrives with none of this and loads it from
/// the cache instead.
@immutable
class ChartFocusArgs {
  const ChartFocusArgs({required this.args, required this.payload});

  final DashboardCardArgs args;
  final ChartPayload payload;
}

/// Pushes the focus view over the shell (D7, D15).
///
/// A push, not a `go`: the dashboard stays underneath and the back arrow
/// returns to it with its cards as they were.
void openChartFocus(
  BuildContext context, {
  required DashboardCardArgs args,
  required ChartPayload payload,
}) {
  context.push(
    Routes.chartFocus(
      AccountScope.of(context),
      args.org,
      args.project,
      widget: args.widget.id,
      dashboard: args.dashboardId,
    ),
    extra: ChartFocusArgs(args: args, payload: payload),
  );
}

/// The `State` every chart card shares: it loads a [ChartPayload], draws it
/// inside the D-B card frame, and opens the focus view when tapped.
///
/// Each card still owns its own file and its own `load`, because what a
/// burndown needs from Analytics has nothing to do with what a pipeline
/// needs — but the frame, the four states (loading, Analytics refused,
/// failed read, content), the empty note and the tap are one implementation.
abstract class ChartCardState<T extends StatefulWidget> extends State<T>
    with DashboardCardMixin<T> {
  ChartPayload? payload;

  DashboardCardArgs get cardArgs;

  /// The name the card wears when the widget on the dashboard has none —
  /// the Team overview's cards always do, the service's widgets sometimes.
  String get fallbackTitle;

  IconData get icon => Icons.show_chart;

  /// Reads this card's data. Cache-first on the first load, refetching on
  /// pull-to-refresh, exactly as the repositories' `refresh` flag means.
  Future<ChartPayload?> read({required bool refresh});

  String get cardTitle =>
      cardArgs.widget.name.isNotEmpty ? cardArgs.widget.name : fallbackTitle;

  @override
  Future<void> fetch({required bool refresh}) async {
    final loaded = await read(refresh: refresh);
    apply(() => payload = loaded);
  }

  @override
  Widget build(BuildContext context) {
    final loaded = payload;
    return DashboardCard(
      title: cardTitle,
      icon: icon,
      filled: cardArgs.filled,
      maxBodyHeight: cardArgs.maxBodyHeight,
      loading: loading && loaded == null,
      error: error,
      unavailable: unavailable,
      onTap: loaded == null || loaded.isEmpty
          ? null
          : () => openChartFocus(context, args: cardArgs, payload: loaded),
      child: loaded == null
          ? const SizedBox.shrink()
          : ChartCardBody(payload: loaded),
    );
  }
}

/// A chart inside a card: the headline, the chart at whatever height the
/// card has, and the legend under it.
///
/// A tablet's card has a fixed height and the chart takes what is left; a
/// phone's card sizes itself, so the chart gets a fixed height there and
/// the card's per-kind cap clips anything the text scale pushes past it.
class ChartCardBody extends StatelessWidget {
  const ChartCardBody({super.key, required this.payload});

  static const unboundedChartHeight = 120.0;

  final ChartPayload payload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (payload.isEmpty) {
      return Text(
        payload.emptyNote,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    final headline = payload.headline;
    final header = headline == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(headline, style: theme.textTheme.titleLarge),
              if (payload.summary case final summary?)
                Text(
                  summary,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          );
    final legend = Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: ChartLegend(keys: payload.keys(context), dense: true),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ?header,
              // The chart's top axis label sits at the very top of its box
              // and collided with the summary line above it (iPhone 17,
              // D-C check).
              const SizedBox(height: Spacing.xs),
              payload.chart(
                context,
                height: unboundedChartHeight,
                compact: true,
              ),
              legend,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?header,
            const SizedBox(height: Spacing.xs),
            Expanded(
              child: LayoutBuilder(
                builder: (context, inner) => payload.chart(
                  context,
                  height: inner.maxHeight,
                  compact: true,
                ),
              ),
            ),
            legend,
          ],
        );
      },
    );
  }
}
