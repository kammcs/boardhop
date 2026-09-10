import 'package:flutter/material.dart';

import '../shared/feature_placeholder_page.dart';

/// Milestone 1: Kanban board with column moves via the WEF column field
/// (spike w02; drag-and-drop chosen by spike F4).
class BoardsPage extends StatelessWidget {
  const BoardsPage({super.key, required this.org, required this.project});

  final String org;
  final String project;

  @override
  Widget build(BuildContext context) => FeaturePlaceholderPage(
    title: 'Boards · $project',
    plannedIn: 'milestone 1',
    backTo: '/orgs/${Uri.encodeComponent(org)}/projects',
  );
}
