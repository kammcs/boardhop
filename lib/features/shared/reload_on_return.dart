import 'package:flutter/material.dart';

/// Keeps a tab of the project shell fresh. The shell keeps every branch
/// alive so each tab holds its scroll position and state, which also
/// means a page built once never loads again; coming back to it after an
/// hour showed rows from an hour ago until the person pulled.
///
/// go_router hides an inactive branch behind a disabled [TickerMode], so
/// the mode flipping back on is the signal that this tab is on screen
/// again. Reloading then, but only when what is on screen has gone stale,
/// keeps tab switching instant while the page still catches up on return.
mixin ReloadOnReturn<T extends StatefulWidget> on State<T> {
  bool _visible = true;
  DateTime? _loadedAt;

  /// How old the page may be before returning to it triggers a reload.
  Duration get staleAfter => const Duration(minutes: 2);

  /// Re-reads whatever the page shows. Called on return, never on the
  /// first build: page state handles that.
  Future<void> reload();

  /// Call when a load finishes, so the next return can judge its age.
  void markLoaded() => _loadedAt = DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    final returned = visible && !_visible;
    _visible = visible;
    if (!returned) return;
    final at = _loadedAt;
    if (at != null && DateTime.now().difference(at) < staleAfter) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reload();
    });
  }
}
