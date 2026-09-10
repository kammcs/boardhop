import 'package:flutter/material.dart';

import '../shared/feature_placeholder_page.dart';

/// Polled activity feed (≈0.013 TSTU per cycle, spike s09) until the
/// Marketplace extension and tenant relay deliver push (research/06).
class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.org});

  final String org;

  @override
  Widget build(BuildContext context) => FeaturePlaceholderPage(
    title: 'Activity · $org',
    plannedIn: 'milestone 1 (polling) and later push',
    backTo: '/orgs/${Uri.encodeComponent(org)}/projects',
  );
}
