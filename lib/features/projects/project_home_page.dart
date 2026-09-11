import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/util/ado_tiles.dart';
import '../../data/models/project.dart';
import '../../data/repositories/project_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import '../shared/widgets/ado_tile.dart';

/// Landing tab of a project. Phase 0 of the repos plan: the project's
/// tile and description with links into the other tabs and the pull
/// request list. Phase 4 fills it with pinned repos, my pull requests,
/// my work items and the latest runs.
class ProjectHomePage extends StatelessWidget {
  const ProjectHomePage({super.key, required this.org, required this.project});

  final String org;
  final String project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = projectRoute(context, org, project);
    return Scaffold(
      appBar: AppBar(
        title: Text(project, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: 'Projects',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('${orgRoute(context, org)}/projects'),
        ),
      ),
      body: StreamBuilder<List<Project>>(
        stream: context.read<ProjectRepository>().watch(org),
        builder: (context, snapshot) {
          Project? current;
          for (final p in snapshot.data ?? const <Project>[]) {
            if (p.name == project) current = p;
          }
          final description = current?.description;
          return ListView(
            padding: const EdgeInsets.only(bottom: Spacing.xl),
            children: [
              Padding(
                padding: Spacing.page,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AdoTile(
                      name: project,
                      color: AdoTiles.serviceColor(project),
                      initials: AdoTiles.serviceInitials(project),
                      source: current?.tileSource(org),
                      size: 56,
                    ),
                    const SizedBox(width: Spacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(project, style: theme.textTheme.titleLarge),
                          if (description != null && description.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: Spacing.xs),
                              child: Text(
                                description,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.call_merge),
                title: const Text('Pull requests'),
                subtitle: const Text('Active pull requests in this project'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('$base/pull-requests'),
              ),
              ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: const Text('Work items'),
                subtitle: const Text(
                  'Assigned to me, recently updated, queries',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('$base/work-items'),
              ),
              ListTile(
                leading: const Icon(Icons.view_kanban_outlined),
                title: const Text('Board'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('$base/boards'),
              ),
              ListTile(
                leading: const Icon(Icons.source_outlined),
                title: const Text('Repositories'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('$base/repos'),
              ),
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Pipelines'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('$base/pipelines'),
              ),
            ],
          );
        },
      ),
    );
  }
}
