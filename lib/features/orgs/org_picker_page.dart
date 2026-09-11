import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:msal_auth/msal_auth.dart' show Account;

import '../../app.dart';
import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/routes.dart';
import '../../core/util/ado_tiles.dart';
import '../../data/models/organization.dart';
import '../../data/repositories/account_repository.dart';
import '../shared/widgets/ado_tile.dart';
import 'widgets/account_header.dart';

/// Every signed-in account as a header row (photo, email, company, sign
/// out) followed by that account's Azure DevOps organizations. The app bar
/// adds another account through the Microsoft account picker.
class OrgPickerPage extends StatefulWidget {
  const OrgPickerPage({super.key});

  @override
  State<OrgPickerPage> createState() => _OrgPickerPageState();
}

class _OrgPickerPageState extends State<OrgPickerPage> {
  /// Bumped on pull-to-refresh so every section refreshes.
  int _refreshTick = 0;

  Future<void> _refreshAll() async {
    setState(() => _refreshTick++);
    // Sections refresh on their own; give the indicator a beat to show.
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, next) =>
          next is AuthSignedIn && next.error != null && prev != next,
      listener: (context, state) {
        final error = (state as AuthSignedIn).error!;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Organizations'),
          actions: [
            IconButton(
              tooltip: 'Add account',
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: () =>
                  context.read<AuthBloc>().add(const AuthSignInRequested()),
            ),
            IconButton(
              tooltip: 'Diagnostics',
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: () => context.push('/diagnostics'),
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push('/settings'),
            ),
          ],
        ),
        body: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            final accounts = state is AuthSignedIn
                ? state.accounts
                : const <Account>[];
            return RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  for (final account in accounts)
                    _AccountSection(
                      key: ValueKey(account.id),
                      account: account,
                      refreshTick: _refreshTick,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One account: its header bar and its organizations, refreshed on its own
/// so one account's failure never blanks the other.
class _AccountSection extends StatefulWidget {
  const _AccountSection({
    super.key,
    required this.account,
    required this.refreshTick,
  });

  final Account account;
  final int refreshTick;

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  late final AccountDeps _deps = context.read<AppDependencies>().forAccount(
    widget.account.id,
  );
  String? _error;
  bool _refreshing = false;
  AccountHeader? _header;
  Uint8List? _photo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHeader();
      _refresh();
    });
  }

  @override
  void didUpdateWidget(_AccountSection old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) {
      _loadHeader();
      _refresh();
    }
  }

  /// Cached header first, then Graph / profile; the photo arrives on its
  /// own so the text never waits for it.
  Future<void> _loadHeader() async {
    final account = _deps.account;
    final cached = await account.cached();
    if (mounted && cached != null) {
      setState(() {
        _header = cached;
        _photo = account.cachedPhoto();
      });
    }
    account.photo().then((bytes) {
      if (mounted && bytes != null) setState(() => _photo = bytes);
    });
    try {
      final fresh = await account.refresh();
      if (mounted) setState(() => _header = fresh);
    } on AdoException catch (e) {
      debugPrint('account header: ${e.message}');
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await _deps.orgs.refresh();
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(e.message, accountId: widget.account.id),
        );
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _signOut() async {
    final email = widget.account.username ?? _header?.email ?? 'this account';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          '$email will be signed out and everything cached for its '
          'organizations removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      context.read<AuthBloc>().add(
        AuthSignOutRequested(accountId: widget.account.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountId = widget.account.id;
    return StreamBuilder<List<Organization>>(
      stream: _deps.orgs.watch(),
      builder: (context, snapshot) {
        final orgs = snapshot.data ?? const <Organization>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountHeaderBar(
              header: _header,
              fallbackEmail: widget.account.username,
              photo: _photo,
              trailing: IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout),
                onPressed: _signOut,
              ),
            ),
            if (_refreshing) const LinearProgressIndicator(),
            if (_error != null)
              ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(_error!),
              ),
            if (orgs.isEmpty && !_refreshing && _error == null)
              const ListTile(
                title: Text('No organizations found for this account.'),
              ),
            for (final org in orgs)
              ListTile(
                leading: AdoTile(
                  name: org.name,
                  color: AdoTiles.coinColor(org.name),
                  initials: AdoTiles.coinInitials(org.name),
                ),
                title: Text(org.name),
                subtitle: Text(org.baseUrl),
                onTap: () {
                  _deps.orgs.markOpened(org.name);
                  context.go('${Routes.org(accountId, org.name)}/projects');
                },
              ),
          ],
        );
      },
    );
  }
}
