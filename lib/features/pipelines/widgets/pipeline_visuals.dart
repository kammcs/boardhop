import 'package:flutter/material.dart';

import '../../../data/models/pipeline.dart';
import '../../../theme/theme.dart';

/// Glyph and color for a run from its `status` and `result`.
(IconData, Color) runGlyph(BuildContext context, String status, String result) {
  final colors = context.boardhopColors;
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    'inProgress' => (Icons.sync, colors.runInProgress),
    'cancelling' => (Icons.sync_disabled, colors.runCanceled),
    'notStarted' || 'postponed' => (Icons.schedule, scheme.onSurfaceVariant),
    _ => switch (result) {
      'succeeded' => (Icons.check_circle, colors.runSucceeded),
      'partiallySucceeded' => (Icons.warning_amber, colors.runPartial),
      'failed' => (Icons.cancel, colors.runFailed),
      'canceled' => (Icons.block, colors.runCanceled),
      _ => (Icons.help_outline, scheme.onSurfaceVariant),
    },
  };
}

/// Glyph and color for a timeline record.
(IconData, Color) recordGlyph(BuildContext context, TimelineRecord r) {
  final colors = context.boardhopColors;
  final scheme = Theme.of(context).colorScheme;
  if (r.isCheckpoint && !r.isCompleted) {
    return (Icons.how_to_reg_outlined, colors.runPartial);
  }
  return switch (r.state) {
    'inProgress' => (Icons.sync, colors.runInProgress),
    'pending' => (Icons.radio_button_unchecked, scheme.outline),
    _ => switch (r.result) {
      'succeeded' => (Icons.check_circle, colors.runSucceeded),
      'succeededWithIssues' => (Icons.warning_amber, colors.runPartial),
      'failed' => (Icons.cancel, colors.runFailed),
      'canceled' => (Icons.block, colors.runCanceled),
      'skipped' => (Icons.remove_circle_outline, scheme.onSurfaceVariant),
      'abandoned' => (Icons.block, scheme.onSurfaceVariant),
      _ => (Icons.radio_button_unchecked, scheme.outline),
    },
  };
}

String runResultLabel(String status, String result) => switch (status) {
  'inProgress' => 'Running',
  'cancelling' => 'Cancelling',
  'notStarted' => 'Queued',
  'postponed' => 'Postponed',
  _ => switch (result) {
    'succeeded' => 'Succeeded',
    'partiallySucceeded' => 'Partially succeeded',
    'failed' => 'Failed',
    'canceled' => 'Canceled',
    _ => status,
  },
};

String reasonLabel(String? reason) => switch (reason) {
  'manual' => 'Manual',
  'individualCI' || 'batchedCI' => 'CI',
  'schedule' || 'scheduleForced' => 'Scheduled',
  'pullRequest' => 'Pull request',
  'buildCompletion' => 'After another run',
  'resourceTrigger' => 'Resource trigger',
  'userCreated' => 'Manual',
  'validateShelveset' || 'checkInShelveset' => 'Shelveset',
  null || '' => '',
  _ => reason,
};

/// Log line accents: `##[error]`, `##[warning]`, `##[section]`.
TextStyle logLineStyle(BuildContext context, TextStyle base, String line) {
  final colors = context.boardhopColors;
  if (line.contains('##[error]')) return base.copyWith(color: colors.runFailed);
  if (line.contains('##[warning]')) {
    return base.copyWith(color: colors.runPartial);
  }
  if (line.contains('##[section]') || line.contains('##[group]')) {
    return base.copyWith(fontWeight: FontWeight.w600);
  }
  if (line.contains('##[debug]')) {
    return base.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
  }
  return base;
}

/// Strips the leading `2026-09-10T14:17:35.1234567Z ` timestamp.
String stripLogTimestamp(String line) =>
    line.replaceFirst(RegExp(r'^\d{4}-\d\d-\d\dT[\d:.]+Z\s?'), '');
