import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/work_item.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../data/write_queue.dart';
import '../shared/account_scope.dart';

/// What happened to a card move, once the optimistic update is on screen.
enum MoveOutcome {
  /// The writes went through.
  done,

  /// The token needs an interactive sign-in; [AuthInteractionRequired] has
  /// already been raised and the optimistic move was left alone, because
  /// the page is about to be replaced by the sign-in flow.
  signedOut,

  /// Offline: the patch is in the write queue, the card was updated
  /// locally and the snackbar was shown.
  queued,

  /// The service refused the move; the caller's [onFailed] has run.
  failed,

  /// The same, and the item changed elsewhere: the caller should reload.
  stale,
}

/// The move choreography, shared by the Kanban board and the sprint
/// taskboard (research/18 §4.2).
///
/// Both pages do the same four things around a drag, and only the writes in
/// the middle differ: apply the move optimistically, run the writes, and
/// then — depending on how they failed — push the user into an interactive
/// sign-in, queue the patch for later, or put the card back where it came
/// from with the message beside it. This function owns that dispatch so the
/// two pages cannot drift apart; the caller owns the optimistic update, the
/// writes and the revert, because those are the parts that are genuinely
/// different.
///
/// [offlineOps] is called only when the network failed, and answering an
/// empty list means "nothing worth queueing" — an in-slot reorder, whose
/// rank is recomputed on the next refresh (decision S9), or a sprint move
/// that only changes a taskboard column.
Future<MoveOutcome> runMoveChoreography(
  BuildContext context, {
  required String org,
  required String project,
  required WorkItem card,
  required Future<void> Function() write,
  required List<Map<String, Object?>> Function() offlineOps,
  required String offlineDescription,
  required void Function(WorkItem local) onQueued,
  required void Function(String message) onFailed,
  String? failureLabel,
}) async {
  try {
    await write();
    return MoveOutcome.done;
  } on AdoAuthException catch (e) {
    if (context.mounted) {
      context.read<AuthBloc>().add(
        AuthInteractionRequired(
          e.message,
          accountId: AccountScope.maybeOf(context),
        ),
      );
    }
    return MoveOutcome.signedOut;
  } on AdoNetworkException {
    // Offline: keep the move on screen and queue the patch. The rank is
    // deliberately not queued — it is recomputed on the next refresh.
    if (!context.mounted) return MoveOutcome.queued;
    final ops = offlineOps();
    if (ops.isEmpty) return MoveOutcome.queued;
    final queue = context.read<WriteQueue>();
    final workItems = context.read<WorkItemRepository>();
    await queue.enqueuePatch(
      org: org,
      project: project,
      item: card,
      ops: ops,
      description: offlineDescription,
    );
    final local = await workItems.applyLocally(
      org,
      project,
      card,
      WriteQueue.fieldsFromOps(ops),
    );
    if (!context.mounted) return MoveOutcome.queued;
    onQueued(local);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(kOfflineMoveMessage)));
    return MoveOutcome.queued;
  } on AdoException catch (e) {
    if (!context.mounted) return MoveOutcome.failed;
    onFailed(moveFailureMessage(card.id, e, label: failureLabel));
    return e is AdoStaleRevisionException
        ? MoveOutcome.stale
        : MoveOutcome.failed;
  }
}

const String kOfflineMoveMessage = 'Offline: the move will sync later.';

/// The sentence a failed move puts in the page's error strip. A stale
/// revision is not the user's mistake, so it says what happened and what to
/// do rather than quoting the 412.
String moveFailureMessage(int id, AdoException e, {String? label}) =>
    e is AdoStaleRevisionException
    ? 'Work item $id changed elsewhere; '
          'the ${label ?? 'board'} was reloaded, try again.'
    : 'Could not move $id: ${e.message}';
