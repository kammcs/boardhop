import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/auth_bloc.dart';
import '../../../core/http/ado_exceptions.dart';
import '../../../data/models/dashboard.dart';
import '../../../theme/theme.dart';
import '../../shared/account_scope.dart';

/// Everything a card needs to know about where it is. Cards read their own
/// data (research/19 §4.2), so they take the org, the project and the
/// dashboard's team rather than being handed rows.
class DashboardCardArgs {
  const DashboardCardArgs({
    required this.org,
    required this.project,
    required this.widget,
    this.teamId,
    this.filled = false,
    this.maxBodyHeight,
  });

  final String org;
  final String project;
  final DashboardWidget widget;

  /// The dashboard's owning team (`groupId`). Null on a project-scoped
  /// dashboard, which no puremedia project has.
  final String? teamId;

  /// True when the page has given the card a fixed height (a tablet's
  /// packed grid, D4), so the body fills the box instead of sizing itself.
  final bool filled;

  /// How tall the card's body may get where the card sizes itself (a
  /// phone), from `DashboardRegistry.phoneCap`. Null is "as tall as its
  /// content".
  final double? maxBodyHeight;

  DashboardCardArgs copyWith({bool? filled, double? maxBodyHeight}) =>
      DashboardCardArgs(
        org: org,
        project: project,
        widget: widget,
        teamId: teamId,
        filled: filled ?? this.filled,
        maxBodyHeight: maxBodyHeight ?? this.maxBodyHeight,
      );
}

/// The page's "reload everything" signal (D12).
///
/// Pull-to-refresh refetches the dashboard **and asks every card to reload**.
/// The cards are independent widgets that own their own data, so the page
/// bumps this and each card reloads itself; nothing has to be registered,
/// and a card that is scrolled off screen and rebuilt later simply reads
/// the current generation.
class DashboardReload extends ChangeNotifier {
  int _generation = 0;

  int get generation => _generation;

  void bump() {
    _generation++;
    notifyListeners();
  }
}

class DashboardReloadScope extends InheritedNotifier<DashboardReload> {
  const DashboardReloadScope({
    super.key,
    required DashboardReload super.notifier,
    required super.child,
  });

  static DashboardReload? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DashboardReloadScope>()
      ?.notifier;
}

/// What every card's `State` mixes in: cache-first load on first build,
/// reload when the page bumps [DashboardReloadScope], and the one error
/// treatment the whole dashboard shares.
///
/// `AdoAuthException` raises `AuthInteractionRequired` — a card must never
/// swallow "sign in again". `AnalyticsUnavailable` is *not* an error but a
/// state of its own (D14): the REST cards beside it still render, so the
/// card says so in place of its content.
mixin DashboardCardMixin<T extends StatefulWidget> on State<T> {
  int _generation = -1;
  bool loading = true;
  String? error;
  String? unavailable;

  /// Reads this card's data. [refresh] is true for every load after the
  /// first, which is what pull-to-refresh means.
  Future<void> fetch({required bool refresh});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final generation = DashboardReloadScope.maybeOf(context)?.generation ?? 0;
    if (generation == _generation) return;
    final first = _generation < 0;
    _generation = generation;
    unawaited(load(refresh: !first));
  }

  Future<void> load({bool refresh = false}) async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
      unavailable = null;
    });
    try {
      await fetch(refresh: refresh);
    } on AnalyticsUnavailable catch (e) {
      if (mounted) setState(() => unavailable = e.message);
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Applies state from inside [fetch] without each card repeating the
  /// mounted check.
  void apply(VoidCallback fn) {
    if (mounted) setState(fn);
  }
}

/// The frame every dashboard card wears: the widget's name as the header,
/// an optional trailing glyph, and one of four bodies — a skeleton while
/// loading, the Analytics notice (D14), a one-line error, or the content.
class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.onTap,
    this.loading = false,
    this.error,
    this.unavailable,
    this.filled = false,
    this.maxBodyHeight,
    this.color,
    this.padBody = true,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// True only while the card has nothing to draw yet; a reload over
  /// content shows the content, not a skeleton.
  final bool loading;
  final String? error;

  /// The reason Analytics refused, shown in place of the content (D14).
  final String? unavailable;

  /// The card has a fixed height and its body should fill it.
  final bool filled;

  /// Where the card sizes itself, how tall its body may get before it is
  /// clipped. A card that draws a list already limits its rows, so this is
  /// the backstop that keeps one long widget from owning a phone screen.
  final double? maxBodyHeight;

  /// The tile colour a Query Tile's rules ask for; null is the theme's
  /// surface.
  final Color? color;

  /// False for a body that draws its own padding (a list of `ListTile`s).
  final bool padBody;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onColor = color == null
        ? null
        : ThemeData.estimateBrightnessForColor(color!) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.md,
        Spacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: onColor ?? scheme.onSurfaceVariant),
            const SizedBox(width: Spacing.sm),
          ],
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(color: onColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Spacing.sm),
            trailing!,
          ],
        ],
      ),
    );
    final body = _body(context, onColor);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: filled ? MainAxisSize.max : MainAxisSize.min,
      children: [
        header,
        if (filled)
          Expanded(child: _clipped(body))
        else if (maxBodyHeight != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxBodyHeight!),
            child: _clipped(body),
          )
        else
          body,
      ],
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      color: color,
      margin: EdgeInsets.zero,
      child: onTap == null ? column : InkWell(onTap: onTap, child: column),
    );
  }

  /// Lets the body be its natural height inside a box that is shorter, and
  /// clips what does not fit — the web clips its widgets the same way.
  ///
  /// `OverflowBoxFit.deferToChild` is what makes this safe in both
  /// directions: the box takes the child's height where there is room, so a
  /// short card does not become a tall empty one, and the child overflows
  /// into the clip where there is not.
  /// Public so a card that clamps part of its own body — the Markdown
  /// card's More — clips it the same way.
  static Widget clipToHeight(Widget child, double maxHeight) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: _clipped(child),
  );

  static Widget _clipped(Widget body) => ClipRect(
    child: OverflowBox(
      alignment: Alignment.topCenter,
      maxHeight: double.infinity,
      fit: OverflowBoxFit.deferToChild,
      child: body,
    ),
  );

  Widget _body(BuildContext context, Color? onColor) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget note(IconData glyph, String text, Color tint) => Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, 0, Spacing.md, Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(glyph, size: 16, color: tint),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: tint),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    // Analytics refusing is the whole story: there is no content behind it
    // (D14). A failed read is not — a card that drew a cached copy keeps it
    // and says what went wrong above it, the way the page's own line does.
    if (unavailable != null) {
      return note(
        Icons.insights_outlined,
        'Analytics unavailable. $unavailable',
        scheme.onSurfaceVariant,
      );
    }
    if (loading) return const _CardSkeleton();
    final content = padBody
        ? Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              0,
              Spacing.md,
              Spacing.md,
            ),
            child: DefaultTextStyle.merge(
              style: onColor == null
                  ? const TextStyle()
                  : TextStyle(color: onColor),
              child: child,
            ),
          )
        : child;
    if (error == null) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [note(Icons.error_outline, error!, scheme.error), content],
    );
  }
}

/// Three grey bars: the card is loading and has nothing yet. Quieter than a
/// spinner in a grid of eight cards, and it keeps the card's height stable.
class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    final tint = Theme.of(context).colorScheme.onSurfaceVariant
        .withValues(alpha: 0.12);
    Widget bar(double widthFactor) => Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: Container(
          height: 12,
          decoration: BoxDecoration(color: tint, borderRadius: Radii.chip),
        ),
      ),
    );
    return Semantics(
      label: 'Loading',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          0,
          Spacing.md,
          Spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [bar(1), bar(0.8), bar(0.55)],
        ),
      ),
    );
  }
}

/// A card for a kind whose content is not built yet: the chart kinds and
/// the Team overview's six cards until D-C lands.
class ComingCard extends StatelessWidget {
  const ComingCard({super.key, required this.args, this.note});

  final DashboardCardArgs args;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DashboardCard(
      title: args.widget.name,
      icon: Icons.show_chart,
      filled: args.filled,
      maxBodyHeight: args.maxBodyHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.auto_graph_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              note ?? 'Chart arrives in the next phase.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
