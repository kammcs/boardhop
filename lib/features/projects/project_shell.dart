import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/display_cutout.dart';
import '../../data/write_queue.dart';
import '../../theme/theme.dart';
import '../shared/pending_writes_banner.dart';
import '../shared/account_scope.dart';
import '../shared/widgets/glass_navigation_rail.dart';
import 'glass_shell_layout.dart';

/// Bottom navigation (phones) or a rail (wider) across a project's areas.
/// Each branch keeps its own navigator and scroll state. Also the place
/// where queued writes are retried: on open and whenever the app resumes.
class ProjectShell extends StatefulWidget {
  const ProjectShell({
    super.key,
    required this.shell,
    required this.org,
    required this.project,
    required this.location,
  });

  final StatefulNavigationShell shell;
  final String org;
  final String project;

  /// Current path inside the shell, used to tell sideways-scrolling
  /// pages (which run under the glass rail) from vertical ones.
  final String location;

  @override
  State<ProjectShell> createState() => _ProjectShellState();
}

class _ProjectShellState extends State<ProjectShell>
    with WidgetsBindingObserver {
  StatefulNavigationShell get shell => widget.shell;
  String get org => widget.org;
  String get project => widget.project;

  /// Where the Dynamic Island is while in landscape (Apple only), so the
  /// glass rail can hug the other edge; read again after every rotation.
  CutoutSide _cutout = CutoutSide.unknown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
    _readCutout();
  }

  @override
  void didChangeMetrics() => _readCutout();

  Future<void> _readCutout() async {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    final side = await DisplayCutout.side();
    if (mounted && side != _cutout) setState(() => _cutout = side);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _drain();
  }

  Future<void> _drain() async {
    if (!mounted) return;
    await context.read<WriteQueue>().drain();
  }

  static const _destinations =
      <({String label, IconData icon, IconData selected, String path})>[
        (
          label: 'Home',
          icon: Icons.home_outlined,
          selected: Icons.home,
          path: 'home',
        ),
        (
          label: 'Work',
          icon: Icons.assignment_outlined,
          selected: Icons.assignment,
          path: 'work-items',
        ),
        (
          label: 'Repos',
          icon: Icons.source_outlined,
          selected: Icons.source,
          path: 'repos',
        ),
        (
          label: 'Pipelines',
          icon: Icons.play_circle_outline,
          selected: Icons.play_circle,
          path: 'pipelines',
        ),
      ];

  /// Pages whose content scrolls sideways (the Kanban board) run under
  /// the glass rail; see [GlassShellLayout].
  static bool _bleedsUnderRail(String location) => location.endsWith('/boards');

  String projectPath(BuildContext context, String tail) =>
      '${orgRoute(context, org)}/projects/${Uri.encodeComponent(project)}/$tail';

  void _select(BuildContext context, int index) {
    // Branch routes carry path parameters, so navigate to the concrete
    // location instead of relying on a branch default (`goBranch` would
    // use the placeholder initialLocation from the router). Going to the
    // root of the current branch pops it back to that root.
    context.go(projectPath(context, _destinations[index].path));
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PendingWritesBanner(),
        Expanded(child: shell),
      ],
    );
    if (context.breakpoint.isCompact) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => _select(context, i),
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selected),
                label: d.label,
              ),
          ],
        ),
      );
    }
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      // Apple tablets, and phones in landscape, get the floating glass
      // rail on the side chosen in Settings > Appearance (right by
      // default); the layout rules live in GlassShellLayout.
      return GlassShellLayout(
        body: body,
        destinations: [
          for (final d in _destinations)
            GlassRailDestination(
              icon: d.icon,
              selectedIcon: d.selected,
              label: d.label,
            ),
        ],
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => _select(context, i),
        bleedsUnderRail: _bleedsUnderRail(widget.location),
        railOnRight: ThemeScope.of(context).railSide == RailSide.right,
        cutoutSide: _cutout,
      );
    }
    return Scaffold(
      // Android keeps Material's rail. The row as a whole keeps clear of a
      // display cutout on the side, as the glass layout does (no Android
      // device in landscape checked yet).
      body: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (i) => _select(context, i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
