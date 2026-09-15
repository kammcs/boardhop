import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes.dart';
import '../../../../core/util/format.dart';
import '../../../../data/models/dashboard.dart';
import '../../../../data/repositories/work_item_repository.dart';
import '../../../shared/account_scope.dart';
import '../dashboard_card.dart';

/// Query Tile: one big number, the count of a saved query.
///
/// The count comes from `WorkItemRepository.queryCount`, which answers from
/// `HEAD wiql/{id}`'s `X-Total-Count` without fetching a single id (spike
/// s60). Tapping opens the query in the Work items page (D7).
class QueryTileCard extends StatefulWidget {
  const QueryTileCard({super.key, required this.args, required this.settings});

  final DashboardCardArgs args;
  final QueryTileSettings settings;

  @override
  State<QueryTileCard> createState() => _QueryTileCardState();
}

class _QueryTileCardState extends State<QueryTileCard> with DashboardCardMixin {
  int? _count;

  @override
  Future<void> fetch({required bool refresh}) async {
    final count = await context.read<WorkItemRepository>().queryCount(
      widget.args.org,
      widget.args.project,
      widget.settings.queryId,
    );
    apply(() => _count = count);
  }

  /// The tile's colour: the first enabled rule the count satisfies, else
  /// `defaultBackgroundColor`, else the theme's surface. Rules were never
  /// seen populated live (§1), so this is written from the settings shape
  /// and stays out of the way when the list is empty.
  Color? get _tileColor {
    final count = _count;
    if (count != null) {
      for (final rule in widget.settings.colorRules) {
        if (!rule.isEnabled) continue;
        final threshold = rule.threshold;
        if (threshold == null) continue;
        final matches = switch (rule.operator) {
          '>' => count > threshold,
          '>=' => count >= threshold,
          '<' => count < threshold,
          '<=' => count <= threshold,
          '=' || '==' => count == threshold,
          _ => false,
        };
        if (matches) {
          final color = parseHexColor(rule.backgroundColor);
          if (color != null) return color;
        }
      }
    }
    return parseHexColor(widget.settings.defaultBackgroundColor);
  }

  void _open() {
    context.go(
      Routes.workItems(
        AccountScope.of(context),
        widget.args.org,
        widget.args.project,
        query: widget.settings.queryId,
        queryName: widget.settings.label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _count;
    final name = widget.args.widget.name.isNotEmpty
        ? widget.args.widget.name
        : widget.settings.label ?? 'Query tile';
    return DashboardCard(
      title: name,
      icon: Icons.filter_alt_outlined,
      filled: widget.args.filled,
      maxBodyHeight: widget.args.maxBodyHeight,
      color: _tileColor,
      loading: loading && count == null,
      error: error,
      onTap: _open,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            count == null ? '—' : '$count',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
