import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/display_cutout.dart';
import '../../data/models/project.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/write_queue.dart';
import '../../theme/theme.dart';
import '../launch/launch_hooks.dart';
import '../launch/launch_resolver.dart';
import '../shared/pending_writes_banner.dart';
import '../shared/unsaved_work.dart';
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

  /// Watches the organization's cached project list so a project that has
  /// gone (research/21 L7) can offer a way out instead of an empty page.
  StreamSubscription<List<Project>>? _projects;
  bool _offeredAnother = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drain();
      _showLaunchNotice();
    });
    _watchProjects();
    _readCutout();
  }

  /// The launch settled for something other than the remembered project
  /// (research/21 L7); the shell is the first thing it built, so it is
  /// where the one line is said. Taken, not read: shown once.
  void _showLaunchNotice() {
    if (!mounted) return;
    final fallback = _read<LaunchResolver>()?.notice.take();
    if (fallback == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Your last project isn't available any more; "
          'opened ${fallback.project}.',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  /// The remembered project is opened without verifying it (L8), so a
  /// project that was deleted or lost shows up here: the organization's
  /// project list is cached and does not name it. An empty list is a cold
  /// cache, not an answer, so it says nothing.
  void _watchProjects() {
    final repo = _read<ProjectRepository>();
    if (repo == null) return;
    _projects = repo.watch(org).listen((projects) {
      if (!mounted || _offeredAnother || projects.isEmpty) return;
      if (projects.any((p) => p.name == project)) return;
      _offeredAnother = true;
      _offerAnotherProject();
    }, onError: (Object _) {});
  }

  void _offerAnotherProject() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"$project" is not available any more.'),
        // The picker belongs to the other launch phase; with nothing
        // registered (a test, a build without it) the line still shows,
        // just without the way out.
        action: LaunchHooks.canChooseProject
            ? SnackBarAction(
                label: 'Choose another project',
                onPressed: () {
                  if (mounted) LaunchHooks.chooseAnotherProject(context);
                },
              )
            : null,
        duration: const Duration(seconds: 8),
        // Flutter 3.47 keeps a snackbar with an action open until it is
        // dismissed, which also blocks every later snackbar.
        persist: false,
      ),
    );
  }

  /// Providers the shell can do without: a widget test that builds it on
  /// its own has neither the launch notice nor the account's repositories.
  T? _read<T extends Object>() {
    try {
      return context.read<T>();
    } catch (_) {
      return null;
    }
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
    _projects?.cancel();
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

  /// Pages whose content scrolls sideways (the Kanban board, the sprint
  /// taskboard) run under the glass rail; see [GlassShellLayout]. The
  /// location the shell is given is `state.uri.path`, so the sprint's
  /// `?iteration=` and `?tab=` are already off it.
  static bool _bleedsUnderRail(String location) =>
      location.endsWith('/boards') || location.endsWith('/sprint');

  String projectPath(BuildContext context, String tail) =>
      '${orgRoute(context, org)}/projects/${Uri.encodeComponent(project)}/$tail';

  Future<void> _select(BuildContext context, int index) async {
    // Branch routes carry path parameters, so navigate to the concrete
    // location instead of relying on a branch default (`goBranch` would
    // use the placeholder initialLocation from the router). Going to the
    // root of the current branch pops it back to that root.
    final path = projectPath(context, _destinations[index].path);
    if (index == shell.currentIndex) {
      // Re-tapping the current tab resets its branch, which would drop an
      // open page without its own `PopScope` ever running, so a form with
      // unsaved changes is asked first (phase 2 review).
      //
      // From medium width up that form is a dialog over the branch rather
      // than a route of its own, so the location is already the branch
      // root: the early return then swallowed the tap and the tablet
      // never asked at all (iPad walkthrough, defect 7). Ask, and close
      // what the branch has open by hand, because `go` to the location it
      // is already at leaves a dialog standing.
      final atRoot = widget.location == path;
      if (atRoot && !UnsavedWork.hasUnsaved) return;
      if (!await UnsavedWork.confirmLeave()) return;
      if (!context.mounted) return;
      if (atRoot) {
        _closeBranchOverlays(index);
        return;
      }
    }
    context.go(path);
  }

  /// Closes whatever the branch holds above its own pages — the tablet
  /// form dialog, a sheet — once the person has agreed to lose it.
  void _closeBranchOverlays(int index) {
    final navigator = shell.route.branches[index].navigatorKey.currentState;
    if (navigator == null) return;
    // `pop` rather than `maybePop`: the form's own `PopScope` already had
    // its say through the guard, and would otherwise ask twice.
    while (navigator.canPop()) {
      navigator.pop();
    }
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
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      // Apple devices get the floating glass chrome at every width: a
      // rail beside the page in landscape (on the side chosen in
      // Settings > Appearance, right by default) and a bar along the
      // bottom in portrait, phones included (Kelly, 2026-09-12: the
      // Material bottom bar on the iPhone was the odd one out). The
      // layout rules live in GlassShellLayout.
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
