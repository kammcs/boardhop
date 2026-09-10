import 'package:flutter/material.dart';

import '../shared/feature_placeholder_page.dart';

/// Milestone 3: pipeline runs, logs, approvals.
class PipelinesPage extends StatelessWidget {
  const PipelinesPage({super.key, required this.org, required this.project});

  final String org;
  final String project;

  @override
  Widget build(BuildContext context) => FeaturePlaceholderPage(
    title: 'Pipelines · $project',
    plannedIn: 'milestone 3',
    backTo: '/orgs/${Uri.encodeComponent(org)}/projects',
  );
}
