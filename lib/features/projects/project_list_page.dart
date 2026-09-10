import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/project.dart';
import '../../data/repositories/project_repository.dart';

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({super.key, required this.org});

  final String org;

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
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
      await context.read<ProjectRepository>().refresh(widget.org);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.org),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/orgs'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: StreamBuilder<List<Project>>(
          stream: context.read<ProjectRepository>().watch(widget.org),
          builder: (context, snapshot) {
            final projects = snapshot.data ?? const <Project>[];
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_refreshing) const LinearProgressIndicator(),
                if (_error != null)
                  ListTile(
                    leading: Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(_error!),
                  ),
                for (final p in projects)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(p.name),
                    subtitle: p.description == null || p.description!.isEmpty
                        ? null
                        : Text(
                            p.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () => context.go(
                      '/orgs/${Uri.encodeComponent(widget.org)}'
                      '/projects/${Uri.encodeComponent(p.name)}/work-items',
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
