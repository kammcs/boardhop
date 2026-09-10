import 'package:flutter/material.dart';

import '../shared/feature_placeholder_page.dart';

/// Milestone 2: org-level PR list (`reviewerId` filter, spike s04), diff
/// viewer (spike F5), threads with `$iteration`/`$baseIteration` tracking,
/// suggestion comments (spike w03).
class PullRequestsPage extends StatelessWidget {
  const PullRequestsPage({super.key, required this.org});

  final String org;

  @override
  Widget build(BuildContext context) => FeaturePlaceholderPage(
    title: 'Pull requests · $org',
    plannedIn: 'milestone 2',
    backTo: '/orgs/${Uri.encodeComponent(org)}/projects',
  );
}
