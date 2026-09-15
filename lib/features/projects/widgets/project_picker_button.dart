import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/util/ado_tiles.dart';
import '../../../data/models/project.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../theme/theme.dart';
import '../../shared/widgets/ado_tile.dart';
import 'project_picker.dart';

/// The project's tile with a small chevron, in the `leading` slot of the four
/// root tabs in place of the back arrow (research/21 L4). Tapping it opens
/// [showProjectPicker].
class ProjectPickerButton extends StatelessWidget {
  const ProjectPickerButton({
    super.key,
    required this.org,
    required this.project,
  });

  final String org;
  final String project;

  /// What the app bars give the leading slot: the default 56 is a hair short
  /// for a 28 dp tile, its chevron and a 48 dp hit target.
  static const double leadingWidth = 64;

  /// Size of the tile itself (L4).
  static const double tileSize = 28;

  @override
  Widget build(BuildContext context) {
    // The shell's "Choose another project" (L7) opens the picker through
    // the launch hook; this is where the two phases are joined.
    registerProjectPickerHook();
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<Project>>(
      stream: context.read<ProjectRepository>().watch(org),
      builder: (context, snapshot) {
        Project? current;
        for (final p in snapshot.data ?? const <Project>[]) {
          if (p.name == project) current = p;
        }
        return IconButton(
          tooltip: 'Switch project',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: kMinTapTarget,
            minHeight: kMinTapTarget,
          ),
          onPressed: () =>
              showProjectPicker(context, org: org, project: project),
          icon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AdoTile(
                name: project,
                color: AdoTiles.serviceColor(project),
                initials: AdoTiles.serviceInitials(project),
                source: current?.tileSource(org),
                size: tileSize,
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        );
      },
    );
  }
}
