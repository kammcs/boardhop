import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/organization.dart';
import '../../data/repositories/org_repository.dart';

class OrgPickerPage extends StatefulWidget {
  const OrgPickerPage({super.key});

  @override
  State<OrgPickerPage> createState() => _OrgPickerPageState();
}

class _OrgPickerPageState extends State<OrgPickerPage> {
  String? _error;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
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
                if (username != null)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(username),
                    dense: true,
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
                    leading: const Icon(Icons.business_outlined),
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
