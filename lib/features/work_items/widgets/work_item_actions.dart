import 'package:flutter/material.dart';

import '../../../data/models/work_item.dart';
import '../../../data/models/work_item_form.dart';
import '../../../theme/theme.dart';
import 'work_item_visuals.dart';

/// What the state sheet answers with: the target state and, when the type's
/// rules require one, the reason for the move.
class StateChange {
  const StateChange(this.state, {this.reason});

  final String state;
  final String? reason;
}

/// Bottom sheet listing the **legal transitions** from the item's current
/// state (`transitions[state]`, spike w18), not every state of the type.
///
/// The type list read carries `transitions` for every type (spike s32), so
/// the sheet costs no extra call. [reason] is the type's `System.Reason`
/// rule: when it is `alwaysRequired`, the sheet asks for a reason in a
/// second step before the patch goes out.
Future<StateChange?> pickState(
  BuildContext context, {
  required WorkItem item,
  required WorkItemVisuals visuals,
  FieldSpec? reason,
  List<String> transitions = const [],
}) {
  final type = visuals.typeOf(item);
  final legal = transitions.isNotEmpty
      ? transitions
      : (type?.transitions[item.state] ??
            [for (final s in type?.states ?? const <WorkItemState>[]) s.name]);
  return pickStateChange(
    context,
    states: legal,
    current: item.state,
    colorOf: (context, state) => visuals.stateColorFor(context, item, state),
    categoryOf: (state) => type?.stateNamed(state)?.category,
    reason: reason,
  );
}

/// The state sheet itself, over a plain list of state names, so the work
/// item form's header chip and the detail page share one picker.
Future<StateChange?> pickStateChange(
  BuildContext context, {
  required List<String> states,
  required String current,
  required Color Function(BuildContext context, String state) colorOf,
  String? Function(String state)? categoryOf,
  FieldSpec? reason,
}) {
  return showModalBottomSheet<StateChange>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _StateSheet(
      states: states,
      current: current,
      colorOf: colorOf,
      categoryOf: categoryOf,
      reason: reason,
    ),
  );
}

class _StateSheet extends StatefulWidget {
  const _StateSheet({
    required this.states,
    required this.current,
    required this.colorOf,
    this.categoryOf,
    this.reason,
  });

  final List<String> states;
  final String current;
  final Color Function(BuildContext context, String state) colorOf;
  final String? Function(String state)? categoryOf;
  final FieldSpec? reason;

  @override
  State<_StateSheet> createState() => _StateSheetState();
}

class _StateSheetState extends State<_StateSheet> {
  /// The state chosen in step one while step two asks for its reason.
  String? _pending;

  bool _needsReason(String state) {
    final reason = widget.reason;
    return state != widget.current &&
        reason != null &&
        reason.alwaysRequired &&
        reason.allowedValues.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = _pending;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: pending == null
            ? [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    0,
                    Spacing.lg,
                    Spacing.sm,
                  ),
                  child: Text('State', style: theme.textTheme.titleMedium),
                ),
                if (widget.states.isEmpty)
                  const ListTile(
                    title: Text('No transitions known for this type.'),
                  ),
                for (final state in widget.states)
                  ListTile(
                    leading: StateDot(
                      color: widget.colorOf(context, state),
                      size: 12,
                    ),
                    title: Text(state),
                    subtitle: widget.categoryOf?.call(state) == null
                        ? null
                        : Text(widget.categoryOf!(state)!),
                    trailing: state == widget.current
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => _needsReason(state)
                        ? setState(() => _pending = state)
                        : Navigator.of(context).pop(StateChange(state)),
                  ),
              ]
            : [
                ListTile(
                  leading: IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => _pending = null),
                  ),
                  title: Text(
                    'Reason for $pending',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                for (final value in widget.reason!.allowedValues)
                  ListTile(
                    title: Text(value),
                    onTap: () =>
                        Navigator.of(context)
                            .pop(StateChange(pending, reason: value)),
                  ),
              ],
      ),
    );
  }
}

enum AssignAction { toMe, unassign }

Future<AssignAction?> pickAssignment(
  BuildContext context, {
  required WorkItem item,
  required String? meLabel,
}) {
  return showModalBottomSheet<AssignAction>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
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
              'Assigned to',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(
              meLabel == null ? 'Assign to me' : 'Assign to $meLabel',
            ),
            enabled: meLabel != null,
            onTap: () => Navigator.of(context).pop(AssignAction.toMe),
          ),
          ListTile(
            leading: const Icon(Icons.person_off_outlined),
            title: const Text('Unassign'),
            enabled: item.assignedTo != null,
            onTap: () => Navigator.of(context).pop(AssignAction.unassign),
          ),
        ],
      ),
    ),
  );
}

/// One-line comment composer anchored at the bottom of the detail page.
class CommentComposer extends StatefulWidget {
  const CommentComposer({super.key, required this.onSubmit, this.busy = false});

  final Future<bool> Function(String text) onSubmit;
  final bool busy;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.busy) return;
    final ok = await widget.onSubmit(text);
    if (ok && mounted) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.sm,
            Spacing.sm,
            Spacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Add a comment (Markdown)',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.xs),
              IconButton.filled(
                tooltip: 'Post comment',
                icon: widget.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                onPressed: _hasText && !widget.busy ? _send : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
