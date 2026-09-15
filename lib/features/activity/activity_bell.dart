import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../data/repositories/activity_repository.dart';
import '../shared/account_scope.dart';

/// The Activity bell in the root tabs' app bars (research/21 L5): the
/// organization's feed, with a dot while it holds items newer than the last
/// visit. The count comes from the cache only ([ActivityRepository.unread]),
/// so the bell costs nothing and follows the poll that is already running.
///
/// Status is never carried by colour alone (DESIGN §3): the tooltip names
/// how many items are new.
class ActivityBell extends StatefulWidget {
  const ActivityBell({super.key, required this.org, this.accountId});

  final String org;

  /// Defaults to the account in scope.
  final String? accountId;

  @override
  State<ActivityBell> createState() => _ActivityBellState();
}

class _ActivityBellState extends State<ActivityBell> {
  /// Built once: a fresh stream on every build would re-run the query
  /// behind it on each rebuild of the app bar.
  late Stream<int> _unread = context.read<ActivityRepository>().unread(
    widget.org,
  );

  @override
  void didUpdateWidget(ActivityBell old) {
    super.didUpdateWidget(old);
    if (old.org != widget.org) {
      _unread = context.read<ActivityRepository>().unread(widget.org);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final account = widget.accountId ?? AccountScope.of(context);
    return StreamBuilder<int>(
      stream: _unread,
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return IconButton(
          tooltip: unread > 0 ? 'Activity · $unread new' : 'Activity',
          icon: Badge(
            isLabelVisible: unread > 0,
            smallSize: 8,
            backgroundColor: scheme.error,
            child: const Icon(Icons.notifications_outlined),
          ),
          onPressed: () => context.push(Routes.activity(account, widget.org)),
        );
      },
    );
  }
}
