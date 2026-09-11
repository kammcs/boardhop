import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/ado_tiles.dart';
import '../../data/models/organization.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/org_repository.dart';
import '../../theme/theme.dart';
import '../shared/widgets/ado_tile.dart';
import 'widgets/account_header.dart';

class OrgPickerPage extends StatefulWidget {
  const OrgPickerPage({super.key});

  @override
  State<OrgPickerPage> createState() => _OrgPickerPageState();
}

class _OrgPickerPageState extends State<OrgPickerPage> {
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

  /// Cached header first, then Graph / profile; the photo arrives on its
  /// own so the text never waits for it.
  Future<void> _loadHeader() async {
    final account = context.read<AccountRepository>();
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
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await context.read<OrgRepository>().refresh();
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final username = auth is AuthSignedIn ? auth.account.username : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizations'),
        actions: [
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
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () =>
                context.read<AuthBloc>().add(const AuthSignOutRequested()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: StreamBuilder<List<Organization>>(
          stream: context.read<OrgRepository>().watch(),
          builder: (context, snapshot) {
            final orgs = snapshot.data ?? const <Organization>[];
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                AccountHeaderBar(
                  header: _header,
                  fallbackEmail: username,
                  photo: _photo,
                ),
                if (_refreshing) const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    Spacing.lg,
                    Spacing.lg,
                    Spacing.xs,
                  ),
                  child: Text(
                    'Azure DevOps organizations',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
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
                      context.read<OrgRepository>().markOpened(org.name);
                      context.go(
                        '/orgs/${Uri.encodeComponent(org.name)}/projects',
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
