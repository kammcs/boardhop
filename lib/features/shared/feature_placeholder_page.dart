import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Stand-in for a feature that is planned but not built yet.
class FeaturePlaceholderPage extends StatelessWidget {
  const FeaturePlaceholderPage({
    super.key,
    required this.title,
    required this.plannedIn,
    this.backTo,
  });

  final String title;
  final String plannedIn;
  final String? backTo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: backTo == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(backTo!),
              ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '$title is planned for $plannedIn.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
