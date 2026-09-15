import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'launch_resolver.dart';

/// Writes the launch memory whenever a project route is entered
/// (research/21 §4).
///
/// Sits in the `/a/:account` shell route's builder, above every page of
/// that account, rather than in the pages themselves: one place catches the
/// four tabs, the standalone work item and wiki routes and the project's
/// pull request list alike. The store write is debounced by
/// `LaunchResolver.remember`, which only writes when the account,
/// organization or project actually changed — switching tabs costs nothing.
///
/// [project] is null on the account's organization-level routes (the
/// project list, the activity feed, the org pull request inbox); those
/// leave the memory alone.
class ProjectMemory extends StatefulWidget {
  const ProjectMemory({
    super.key,
    required this.accountId,
    required this.org,
    required this.project,
    required this.child,
  });

  final String accountId;
  final String? org;
  final String? project;
  final Widget child;

  @override
  State<ProjectMemory> createState() => _ProjectMemoryState();
}

class _ProjectMemoryState extends State<ProjectMemory> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _remember();
  }

  @override
  void didUpdateWidget(ProjectMemory old) {
    super.didUpdateWidget(old);
    if (old.accountId != widget.accountId ||
        old.org != widget.org ||
        old.project != widget.project) {
      _remember();
    }
  }

  void _remember() {
    final org = widget.org;
    final project = widget.project;
    if (org == null || project == null) return;
    // The provider is missing in widget tests that build one page on its
    // own; remembering is a convenience, never a requirement.
    final LaunchResolver resolver;
    try {
      resolver = context.read<LaunchResolver>();
    } on ProviderNotFoundException {
      return;
    }
    resolver.remember(widget.accountId, org, project);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
