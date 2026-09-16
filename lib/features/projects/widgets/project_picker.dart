import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:msal_auth/msal_auth.dart' show Account;

import '../../../app.dart';
import '../../../auth/auth_bloc.dart';
import '../../../core/config/app_config.dart';
import '../../../core/http/ado_exceptions.dart';
import '../../../core/routes.dart';
import '../../../core/util/ado_tiles.dart';
import '../../../data/avatar_store.dart';
import '../../../data/models/organization.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/account_repository.dart';
import '../../../theme/theme.dart';
import '../../launch/launch_hooks.dart';
import '../../orgs/widgets/account_header.dart';
import '../../shared/account_scope.dart';
import '../../shared/widgets/ado_tile.dart';
import 'project_picker_landing.dart';

/// Width of the anchored panel on medium and expanded widths (L2).
const double kProjectPickerPanelWidth = 360;

/// Everything reachable from the project tile in the root tabs' leading slot
/// (research/21 L1): every signed-in account, its organizations, their
/// projects with the current one ticked, and the account and app rows at the
/// bottom.
///
/// A modal bottom sheet on a phone (L2: draggable, opens at 60 %, drags to
/// nearly full) and a panel anchored under the tile from medium width up,
/// dismissed by a tap outside or Escape.
Future<void> showProjectPicker(
  BuildContext context, {
  required String org,
  required String project,
}) {
  final accountId = AccountScope.of(context);
  final router = GoRouter.of(context);
  final compact = context.breakpoint.isCompact;

  Widget content(
    BuildContext host, {
    ScrollController? controller,
    bool shrinkWrap = false,
    bool handle = false,
  }) => ProjectPickerContent(
    currentAccountId: accountId,
    org: org,
    project: project,
    scrollController: controller,
    shrinkWrap: shrinkWrap,
    showHandle: handle,
    onClose: () => Navigator.of(host).pop(),
    go: router.go,
    push: router.push,
  );

  if (compact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // The content draws its own handle as the list's first row (so a
      // drag anywhere in the list moves the sheet); the theme's handle on
      // top of it showed two.
      showDragHandle: false,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) =>
            content(sheetContext, controller: controller, handle: true),
      ),
    );
  }

  final anchor = _anchorFor(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Padding(
      padding: EdgeInsets.only(left: anchor.dx, top: anchor.dy),
      child: Align(
        alignment: Alignment.topLeft,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(dialogContext).pop(),
          },
          child: Focus(
            autofocus: true,
            child: Material(
              elevation: 8,
              borderRadius: Radii.card,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: kProjectPickerPanelWidth,
                  // L2: at most 70 % of the window.
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.7,
                ),
                child: content(dialogContext, shrinkWrap: true),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Hands the picker to the launch phase's hook (research/21 L7): the shell's
/// "Choose another project" snackbar, raised when the project it is showing
/// has gone, opens this picker.
///
/// Idempotent, and called from [ProjectPickerButton], which is on screen in
/// every root tab — so the two phases meet here and neither imports the
/// other's widgets.
void registerProjectPickerHook() {
  LaunchHooks.onChooseAnotherProject ??= (context) {
    final state = GoRouterState.of(context);
    final org = state.pathParameters['org'];
    final project = state.pathParameters['project'];
    if (org == null || project == null) return;
    showProjectPicker(context, org: org, project: project);
  };
}

/// Top-left corner of the anchored panel: just under the widget the picker
/// was opened from (the tile in the leading slot), kept on screen.
Offset _anchorFor(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final insets = MediaQuery.paddingOf(context);
  var dx = Spacing.sm;
  var dy = insets.top + kToolbarHeight;
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    final origin = box.localToGlobal(Offset.zero);
    dx = origin.dx;
    dy = origin.dy + box.size.height + Spacing.xs;
  }
  final maxDx = size.width - kProjectPickerPanelWidth - Spacing.sm;
  return Offset(
    dx.clamp(Spacing.sm, maxDx > Spacing.sm ? maxDx : Spacing.sm),
    dy,
  );
}

/// The picker's body, shared by the sheet and the panel.
class ProjectPickerContent extends StatefulWidget {
  const ProjectPickerContent({
    super.key,
    required this.currentAccountId,
    required this.org,
    required this.project,
    required this.onClose,
    required this.go,
    required this.push,
    this.scrollController,
    this.shrinkWrap = false,
    this.showHandle = false,
    this.resolveLanding,
    this.showDiagnostics = AppConfig.diagnosticsEnabled,
  });

  /// The account, organization and project the picker was opened from; their
  /// row carries the tick.
  final String currentAccountId;
  final String org;
  final String project;

  /// Dismisses the sheet or panel.
  final VoidCallback onClose;

  /// Switching project or account replaces the stack; Activity, Settings and
  /// Diagnostics are pushed over it, because they pop back.
  final void Function(String route) go;
  final void Function(String route) push;

  /// The sheet's drag controller; null in the anchored panel.
  final ScrollController? scrollController;
  final bool shrinkWrap;
  final bool showHandle;

  /// Where to land after an account was added or signed out. Defaults to
  /// [landingResolverFor], which is phase LA's resolver.
  final ResolveLanding? resolveLanding;

  /// The Diagnostics row. Off in store builds, a parameter so a test can
  /// check both faces.
  final bool showDiagnostics;

  @override
  State<ProjectPickerContent> createState() => _ProjectPickerContentState();
}

/// What one account contributes to the list, filled from the caches first.
class _AccountData {
  AccountHeader? header;
  Uint8List? photo;
  List<Organization> orgs = const [];
  bool orgsLoading = false;
  final Map<String, List<Project>> projects = {};
  final Set<String> projectsLoading = {};
}

class _ProjectPickerContentState extends State<ProjectPickerContent> {
  /// Above this many projects in total the list gets a filter field.
  static const filterThreshold = 8;

  /// How long an account change waits for the bloc before giving up.
  static const _authTimeout = Duration(minutes: 3);

  final _filter = TextEditingController();
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _data = <String, _AccountData>{};
  final _watchedProjects = <String>{};
  final _refreshed = <String>{};

  List<Account> _accounts = const [];
  String _query = '';

  /// Activity items newer than the last visit, for the row's dot. Kept in
  /// state rather than a `StreamBuilder`: the rows shift index when the
  /// filter field appears, which would re-subscribe.
  int _unread = 0;

  AppDependencies get _root => context.read<AppDependencies>();

  @override
  void initState() {
    super.initState();
    final state = context.read<AuthBloc>().state;
    _accounts = state is AuthSignedIn ? state.accounts : const <Account>[];
    for (final account in _accounts) {
      _watchAccount(account);
    }
    _subscriptions.add(
      _root
          .forAccount(widget.currentAccountId)
          .activity
          .unread(widget.org)
          .listen((count) {
            if (mounted) setState(() => _unread = count);
          }),
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _filter.dispose();
    super.dispose();
  }

  void _watchAccount(Account account) {
    final deps = _root.forAccount(account.id);
    final data = _data[account.id] = _AccountData();
    unawaited(_loadHeader(deps, data));
    _subscriptions.add(
      deps.orgs.watch().listen((orgs) {
        if (!mounted) return;
        setState(() {
          data.orgs = [...orgs]..sort((a, b) => _byName(a.name, b.name));
        });
        if (orgs.isEmpty) {
          unawaited(_refresh('orgs:${account.id}', data, deps.orgs.refresh));
        }
        for (final org in orgs) {
          _watchProjects(account.id, deps, org.name);
        }
      }),
    );
  }

  /// Cached only: the picker opens offline and instantly. The photo comes
  /// from the avatar store, which serves it from disk when it has it.
  Future<void> _loadHeader(AccountDeps deps, _AccountData data) async {
    final cached = await deps.account.cached();
    if (mounted) {
      setState(() {
        data.header = cached;
        data.photo = deps.account.cachedPhoto();
      });
    }
    try {
      final bytes = await deps.account.photo();
      if (mounted && bytes != null) setState(() => data.photo = bytes);
    } on AdoException {
      // The header falls back to the initials.
    }
  }

  void _watchProjects(String accountId, AccountDeps deps, String org) {
    if (!_watchedProjects.add('$accountId|$org')) return;
    _subscriptions.add(
      deps.projects.watch(org).listen((projects) {
        if (!mounted) return;
        final data = _data[accountId];
        if (data == null) return;
        setState(() {
          data.projects[org] = [...projects]
            ..sort((a, b) => _byName(a.name, b.name));
        });
        if (projects.isEmpty) {
          unawaited(
            _refresh(
              'projects:$accountId|$org',
              data,
              () => deps.projects.refresh(org),
              org: org,
            ),
          );
        }
      }),
    );
  }

  /// Fills an empty list once, with a progress row while it runs. A failure
  /// is silent: the picker is transient, and the page behind it reports.
  Future<void> _refresh(
    String key,
    _AccountData data,
    Future<Object?> Function() fetch, {
    String? org,
  }) async {
    if (!_refreshed.add(key)) return;
    if (mounted) {
      setState(() {
        if (org == null) {
          data.orgsLoading = true;
        } else {
          data.projectsLoading.add(org);
        }
      });
    }
    try {
      await fetch();
    } on AdoException {
      // Nothing to show; the row simply stays empty.
    } finally {
      if (mounted) {
        setState(() {
          if (org == null) {
            data.orgsLoading = false;
          } else {
            data.projectsLoading.remove(org);
          }
        });
      }
    }
  }

  static int _byName(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  int get _totalProjects {
    var total = 0;
    for (final data in _data.values) {
      for (final list in data.projects.values) {
        total += list.length;
      }
    }
    return total;
  }

  /// The projects of [org] that the filter leaves: all of them when the
  /// organization itself matches, so its name works as a heading.
  List<Project> _visibleProjects(_AccountData data, String org) {
    final all = data.projects[org] ?? const <Project>[];
    if (_query.isEmpty || org.toLowerCase().contains(_query)) return all;
    return [
      for (final p in all)
        if (p.name.toLowerCase().contains(_query)) p,
    ];
  }

  void _goTo(String route) {
    widget.onClose();
    widget.go(route);
  }

  void _pushTo(String route) {
    widget.onClose();
    widget.push(route);
  }

  /// Waits for the bloc to settle on a state matching [test]; null when it
  /// never does (the account picker was cancelled).
  Future<AuthState?> _nextAuthState(
    AuthBloc auth,
    bool Function(AuthState) test,
  ) async {
    try {
      return await auth.stream.firstWhere(test).timeout(_authTimeout);
    } on TimeoutException {
      return null;
    } on StateError {
      return null;
    }
  }

  Future<void> _signOut(Account account) async {
    final auth = context.read<AuthBloc>();
    final resolve = widget.resolveLanding ?? landingResolverFor(context);
    final go = widget.go;
    widget.onClose();
    auth.add(AuthSignOutRequested(accountId: account.id));
    final next = await _nextAuthState(
      auth,
      (s) =>
          s is AuthSignedOut ||
          (s is AuthSignedIn && !s.accounts.any((a) => a.id == account.id)),
    );
    // Nothing left: the bloc's AuthSignedOut already redirects to sign-in.
    if (next is! AuthSignedIn) return;
    final route = await resolve(next.accounts);
    if (route != null) go(route);
  }

  Future<void> _addAccount() async {
    final auth = context.read<AuthBloc>();
    final resolve = widget.resolveLanding ?? landingResolverFor(context);
    final go = widget.go;
    final known = {for (final a in _accounts) a.id};
    widget.onClose();
    auth.add(const AuthSignInRequested());
    final next = await _nextAuthState(
      auth,
      (s) => s is AuthSignedIn && s.accounts.any((a) => !known.contains(a.id)),
    );
    if (next is! AuthSignedIn) return;
    final added = next.accounts.firstWhere((a) => !known.contains(a.id));
    final route = await resolve(next.accounts, preferAccountId: added.id);
    if (route != null) go(route);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (widget.showHandle) const _DragHandle(),
      if (_totalProjects > filterThreshold)
        _FilterField(
          controller: _filter,
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
        ),
      for (final account in _accounts) _accountSection(context, account),
      const Divider(height: 1),
      ..._bottomRows(context),
    ];
    return SafeArea(
      top: false,
      child: ListView(
        controller: widget.scrollController,
        shrinkWrap: widget.shrinkWrap,
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        children: children,
      ),
    );
  }

  Widget _accountSection(BuildContext context, Account account) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final deps = _root.forAccount(account.id);
    final data = _data[account.id] ?? _AccountData();
    final rows = <Widget>[
      AccountHeaderBar(
        header: data.header,
        fallbackEmail: account.username,
        photo: data.photo,
        trailing: IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout),
          onPressed: () => _signOut(account),
        ),
      ),
      if (data.orgsLoading && data.orgs.isEmpty)
        const _ProgressRow('Loading organizations…'),
    ];
    for (final org in data.orgs) {
      final projects = _visibleProjects(data, org.name);
      final loading = data.projectsLoading.contains(org.name);
      if (projects.isEmpty && _query.isNotEmpty) continue;
      rows.add(
        ListTile(
          dense: true,
          leading: AdoTile(
            name: org.name,
            color: AdoTiles.coinColor(org.name),
            initials: AdoTiles.coinInitials(org.name),
            size: 24,
          ),
          title: Text(
            org.name,
            style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // L3 revised (Kelly, 2026-09-16): the organization row is a
          // subhead, not a link. Nothing in the app leads to the project
          // list or the Accounts page any more; both stay only as routes.
        ),
      );
      if (projects.isEmpty && loading) {
        rows.add(const _ProgressRow('Loading projects…'));
      }
      for (final project in projects) {
        final current =
            account.id == widget.currentAccountId &&
            org.name == widget.org &&
            project.name == widget.project;
        rows.add(
          ListTile(
            leading: AdoTile(
              name: project.name,
              color: AdoTiles.serviceColor(project.name),
              initials: AdoTiles.serviceInitials(project.name),
              source: project.tileSource(org.name),
              size: 28,
            ),
            title: Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: current ? const Icon(Icons.check) : null,
            selected: current,
            onTap: () => _goTo(Routes.home(account.id, org.name, project.name)),
          ),
        );
      }
    }
    // The tiles resolve their pictures with this account's token.
    return RepositoryProvider<AvatarStore>.value(
      value: deps.avatars,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  List<Widget> _bottomRows(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      ListTile(
        leading: const Icon(Icons.person_add_alt_1_outlined),
        title: const Text('Add account'),
        onTap: _addAccount,
      ),
      ListTile(
        leading: Badge(
          isLabelVisible: _unread > 0,
          smallSize: 8,
          backgroundColor: scheme.error,
          child: const Icon(Icons.notifications_outlined),
        ),
        title: const Text('Activity'),
        subtitle: _unread > 0 ? Text('$_unread new') : null,
        onTap: () =>
            _pushTo(Routes.activity(widget.currentAccountId, widget.org)),
      ),
      ListTile(
        leading: const Icon(Icons.settings_outlined),
        title: const Text('Settings'),
        onTap: () => _pushTo('/settings'),
      ),
      if (widget.showDiagnostics)
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Diagnostics'),
          onTap: () => _pushTo('/diagnostics'),
        ),
    ];
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
        ),
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.sm,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Filter projects',
          prefixIcon: Icon(Icons.search),
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator.adaptive(strokeWidth: 2),
      ),
      title: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
