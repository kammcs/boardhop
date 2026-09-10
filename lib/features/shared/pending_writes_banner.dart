import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/util/format.dart';
import '../../data/write_queue.dart';
import '../../theme/theme.dart';

/// Persistent, unobtrusive strip (DESIGN.md §7) while writes wait to sync
/// or need a decision after a conflict.
class PendingWritesBanner extends StatelessWidget {
  const PendingWritesBanner({super.key});

  Future<void> _retry(BuildContext context) async {
    final result = await context.read<WriteQueue>().drain();
    if (!context.mounted) return;
    final text = result.stoppedOffline
        ? 'Still offline; ${result.synced} synced so far.'
        : '${result.synced} synced'
              '${result.conflicts > 0 ? ', ${result.conflicts} need review' : ''}.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _review(BuildContext context, List<PendingWrite> writes) {
    final queue = context.read<WriteQueue>();
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: StreamBuilder<List<PendingWrite>>(
          stream: queue.watch(),
          initialData: writes,
          builder: (context, snapshot) {
            final theme = Theme.of(context);
            final list = snapshot.data ?? const <PendingWrite>[];
            return ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    0,
                    Spacing.lg,
                    Spacing.sm,
                  ),
                  child: Text(
                    'Waiting to sync',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (list.isEmpty)
                  const ListTile(title: Text('Everything is synced.')),
                for (final w in list)
                  ListTile(
                    leading: Icon(
                      w.isConflict
                          ? Icons.warning_amber_outlined
                          : Icons.cloud_upload_outlined,
                      color: w.isConflict ? theme.colorScheme.error : null,
                    ),
                    title: Text(w.description),
                    subtitle: Text(
                      w.isConflict
                          ? 'Changed elsewhere since; this change was not applied.'
                          : (w.lastError ??
                                'Queued ${relativeTime(w.createdAt)}'),
                    ),
                    trailing: TextButton(
                      onPressed: () => queue.discard(w.id),
                      child: const Text('Discard'),
                    ),
                  ),
                Padding(
                  padding: Spacing.page,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _retry(context);
                    },
                    icon: const Icon(Icons.sync),
                    label: const Text('Retry now'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<PendingWrite>>(
      stream: context.read<WriteQueue>().watch(),
      builder: (context, snapshot) {
        final writes = snapshot.data ?? const <PendingWrite>[];
        if (writes.isEmpty) return const SizedBox.shrink();
        final conflicts = writes.where((w) => w.isConflict).length;
        final waiting = writes.length - conflicts;
        final text = conflicts > 0
            ? '$conflicts change${conflicts == 1 ? '' : 's'} need review'
                  '${waiting > 0 ? ', $waiting waiting to sync' : ''}'
            : '$waiting change${waiting == 1 ? '' : 's'} waiting to sync';
        return Material(
          color: conflicts > 0
              ? scheme.errorContainer
              : scheme.tertiaryContainer,
          child: SafeArea(
            bottom: false,
            child: ListTile(
              dense: true,
              leading: Icon(
                conflicts > 0 ? Icons.warning_amber_outlined : Icons.cloud_off,
                color: conflicts > 0
                    ? scheme.onErrorContainer
                    : scheme.onTertiaryContainer,
              ),
              title: Text(
                text,
                style: TextStyle(
                  color: conflicts > 0
                      ? scheme.onErrorContainer
                      : scheme.onTertiaryContainer,
                ),
              ),
              trailing: TextButton(
                onPressed: () =>
                    conflicts > 0 ? _review(context, writes) : _retry(context),
                child: Text(conflicts > 0 ? 'Review' : 'Retry'),
              ),
              onTap: () => _review(context, writes),
            ),
          ),
        );
      },
    );
  }
}
