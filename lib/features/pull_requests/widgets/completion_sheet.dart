import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/models/pr_check.dart';
import '../../../data/models/pull_request.dart';
import '../../../theme/theme.dart';
import 'merge_box.dart';

/// The default merge commit message: the title with the pull request's own
/// reference under it, which is what the field opens on when the service
/// has no remembered message (R3).
String defaultMergeCommitMessage(PullRequest pr) => '${pr.title}\n\n!${pr.id}';

/// The strategy the sheet opens on: the remembered one when the target
/// still allows it, else the first allowed one in this order.
MergeStrategy? preferredStrategy(
  PrCompletionOptions? remembered,
  Set<MergeStrategy> allowed,
) {
  final wanted = remembered?.mergeStrategy;
  if (wanted != null && allowed.contains(wanted)) return wanted;
  for (final s in MergeStrategy.values) {
    if (allowed.contains(s)) return s;
  }
  return null;
}

/// The non-blocking policies auto-complete should not wait for, which is
/// what "wait for optional policies too" means when it is **off** (R3).
List<int> optionalPolicyIds(PrPolicySet? policies) => [
  for (final p in policies?.policies ?? const <PrPolicy>[])
    if (!p.isBlocking && p.id > 0) p.id,
];

/// The completion sheet, shared by Complete and Set auto-complete (R3).
///
/// Answers with the options to send, or null when the user backed out. The
/// caller decides which write they go to: [PullRequestRepository.complete]
/// or `setAutoComplete`.
Future<PrCompletionOptions?> showCompletionSheet(
  BuildContext context, {
  required PullRequest pr,
  required PrPolicySet? policies,
  required bool autoComplete,
  List<PrCheck> checks = const [],
}) {
  // From medium up a centered dialog, like every other picker (iPad
  // walkthrough); a phone keeps the sheet.
  if (!context.breakpoint.isCompact) {
    return showDialog<PrCompletionOptions>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _CompletionSheet(
            pr: pr,
            policies: policies,
            autoComplete: autoComplete,
            checks: checks,
            dialog: true,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<PrCompletionOptions>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _CompletionSheet(
      pr: pr,
      policies: policies,
      autoComplete: autoComplete,
      checks: checks,
    ),
  );
}

class _CompletionSheet extends StatefulWidget {
  const _CompletionSheet({
    required this.pr,
    required this.policies,
    required this.autoComplete,
    required this.checks,
    this.dialog = false,
  });

  final PullRequest pr;
  final PrPolicySet? policies;
  final bool autoComplete;
  final List<PrCheck> checks;
  final bool dialog;

  @override
  State<_CompletionSheet> createState() => _CompletionSheetState();
}

class _CompletionSheetState extends State<_CompletionSheet> {
  late final Set<MergeStrategy> _allowed =
      widget.policies?.allowedStrategies ?? MergeStrategy.values.toSet();
  late final PrCompletionOptions? _remembered = widget.pr.completionOptions;

  late MergeStrategy? _strategy = preferredStrategy(_remembered, _allowed);
  late bool _deleteSource = _remembered?.deleteSourceBranch ?? true;
  late bool _transition = _remembered?.transitionWorkItems ?? true;
  late bool _customMessage = (_remembered?.mergeCommitMessage ?? '')
      .trim()
      .isNotEmpty;
  late final TextEditingController _message = TextEditingController(
    text: _remembered?.mergeCommitMessage?.trim().isNotEmpty == true
        ? _remembered!.mergeCommitMessage
        : defaultMergeCommitMessage(widget.pr),
  );
  late bool _bypass = _remembered?.bypassPolicy ?? false;
  late final TextEditingController _reason = TextEditingController(
    text: _remembered?.bypassReason ?? '',
  );

  /// On by default: auto-complete waiting for the optional policies too is
  /// the service's own behaviour with no ignore list. A remembered ignore
  /// list means it was turned off last time.
  late bool _waitForOptional =
      (_remembered?.autoCompleteIgnoreConfigIds ?? const []).isEmpty;

  @override
  void dispose() {
    _message.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// Bypass is only worth offering while something is actually in the way.
  /// Whether the signed-in user *may* bypass is not readable (no permission
  /// route the app's token can ask), so the option is shown and the
  /// service's refusal is reported by the page.
  bool get _canOfferBypass =>
      prHasUnmetBlocking(widget.checks) || !prMergeReady(widget.pr);

  PrCompletionOptions get _options => PrCompletionOptions(
    mergeStrategy: _strategy,
    deleteSourceBranch: _deleteSource,
    transitionWorkItems: _transition,
    mergeCommitMessage: _customMessage ? _message.text.trim() : null,
    bypassPolicy: _canOfferBypass && _bypass,
    bypassReason: _reason.text.trim(),
    autoCompleteIgnoreConfigIds: widget.autoComplete && !_waitForOptional
        ? optionalPolicyIds(widget.policies)
        : const [],
  );

  String get _confirm => widget.autoComplete ? 'Set auto-complete' : 'Complete';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pr = widget.pr;
    final height = MediaQuery.sizeOf(context).height;
    final optional = optionalPolicyIds(widget.policies);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: widget.dialog ? math.min(620, height * 0.85) : height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                Spacing.lg,
                widget.dialog ? Spacing.lg : 0,
                Spacing.lg,
                Spacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.autoComplete
                        ? 'Set auto-complete on !${pr.id}'
                        : 'Complete !${pr.id}',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    widget.autoComplete
                        ? 'Merges ${pr.sourceBranch} into ${pr.targetBranch} '
                              'once every policy passes.'
                        : 'Merges ${pr.sourceBranch} into ${pr.targetBranch}.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.only(bottom: Spacing.lg),
                children: [
                  _Label('Merge type'),
                  RadioGroup<MergeStrategy>(
                    groupValue: _strategy,
                    onChanged: (s) => setState(() => _strategy = s),
                    child: Column(
                      children: [
                        for (final s in MergeStrategy.values)
                          RadioListTile<MergeStrategy>(
                            value: s,
                            // A forbidden strategy is accepted by the PATCH
                            // and only then evaluated as rejected, so it has
                            // to be filtered here (research/22 §1).
                            enabled: _allowed.contains(s),
                            title: Text(s.label),
                            subtitle: _allowed.contains(s)
                                ? null
                                : Text(
                                    'Not allowed by policy',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: _deleteSource,
                    onChanged: (v) => setState(() => _deleteSource = v),
                    title: const Text('Delete source branch'),
                  ),
                  SwitchListTile(
                    value: _transition,
                    onChanged: (v) => setState(() => _transition = v),
                    title: const Text('Complete linked work items'),
                  ),
                  SwitchListTile(
                    value: _customMessage,
                    onChanged: (v) => setState(() => _customMessage = v),
                    title: const Text('Customize merge commit message'),
                  ),
                  if (_customMessage)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.lg,
                        0,
                        Spacing.lg,
                        Spacing.md,
                      ),
                      child: TextField(
                        controller: _message,
                        minLines: 2,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Merge commit message',
                        ),
                      ),
                    ),
                  if (widget.autoComplete) ...[
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _waitForOptional,
                      onChanged: optional.isEmpty
                          ? null
                          : (v) => setState(() => _waitForOptional = v),
                      title: const Text('Wait for optional policies too'),
                      subtitle: Text(
                        optional.isEmpty
                            ? 'The target has no optional policies.'
                            : 'Off: merge as soon as the blocking policies '
                                  'pass.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  if (_canOfferBypass) ...[
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _bypass,
                      onChanged: (v) => setState(() => _bypass = v),
                      title: const Text('Override policies'),
                      subtitle: Text(
                        'Only some accounts may; the service refuses the '
                        'rest.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (_bypass)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.lg,
                          0,
                          Spacing.lg,
                          Spacing.md,
                        ),
                        child: TextField(
                          controller: _reason,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Reason',
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              // An OverflowBar rather than a Row: "Set auto-complete" beside
              // Cancel does not fit a phone at 400 dp, let alone at xxxL,
              // and this stacks them instead of clipping.
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: Spacing.sm,
                overflowSpacing: Spacing.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _strategy == null
                        ? null
                        : () => Navigator.of(context).pop(_options),
                    child: Text(_confirm),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.xs,
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
