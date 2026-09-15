import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/models/project.dart';
import '../../../../data/models/work_item.dart';
import '../../../../data/repositories/people_repository.dart';
import '../../../../data/repositories/project_repository.dart';
import '../../../../data/repositories/sprint_repository.dart';
import '../../../../theme/theme.dart';
import '../../../work_items/widgets/work_item_visuals.dart';
import '../dashboard_card.dart';

/// Team Members: the dashboard's own team, as avatars with names.
///
/// The members route needs the project **id**, not its name, so the id
/// comes off the cached project list the org picker already fills; the
/// team is the dashboard's `groupId`, falling back to the project's
/// default team for a project-scoped dashboard.
class TeamMembersCard extends StatefulWidget {
  const TeamMembersCard({super.key, required this.args});

  final DashboardCardArgs args;

  @override
  State<TeamMembersCard> createState() => _TeamMembersCardState();
}

class _TeamMembersCardState extends State<TeamMembersCard>
    with DashboardCardMixin {
  List<IdentityRef>? _members;

  @override
  Future<void> fetch({required bool refresh}) async {
    final org = widget.args.org;
    final project = widget.args.project;
    final projects = await context.read<ProjectRepository>().watch(org).first;
    if (!mounted) return;
    final id = projects
        .cast<Project?>()
        .firstWhere((p) => p?.name == project, orElse: () => null)
        ?.id;
    final teamId =
        widget.args.teamId ??
        await context.read<SprintRepository>().defaultTeamId(org, project);
    if (!mounted) return;
    final members = await context.read<PeopleRepository>().teamMembers(
      org,
      // The project name works on this route when the id is not cached
      // yet; the descriptor route is the one that insists on the id.
      id ?? project,
      teamId,
      refresh: refresh,
    );
    apply(() => _members = members);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final members = _members;
    return DashboardCard(
      title: widget.args.widget.name.isNotEmpty
          ? widget.args.widget.name
          : 'Team members',
      icon: Icons.group_outlined,
      filled: widget.args.filled,
      maxBodyHeight: widget.args.maxBodyHeight,
      loading: loading && members == null,
      error: error,
      child: members == null || members.isEmpty
          ? Text(
              'No members to show.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          : Wrap(
              spacing: Spacing.md,
              runSpacing: Spacing.sm,
              children: [
                for (final member in members)
                  SizedBox(
                    width: 88,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IdentityAvatar(identity: member, radius: 18),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          member.displayName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
