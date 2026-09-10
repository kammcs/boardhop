import 'package:flutter/material.dart';

import '../shared/feature_placeholder_page.dart';

/// Milestone 1: "assigned to me" list and work item detail
/// (HTML/Markdown rendering, comments, lightweight edits with `test /rev`).
class WorkItemsPage extends StatelessWidget {
  const WorkItemsPage({super.key, required this.org, required this.project});

  final String org;
  final String project;

  @override
  Widget build(BuildContext context) => FeaturePlaceholderPage(
    title: 'Work items · $project',
    plannedIn: 'milestone 1',
    backTo: '/orgs/${Uri.encodeComponent(org)}/projects',
  );
}
