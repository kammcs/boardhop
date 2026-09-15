import 'package:flutter/material.dart';

import '../../../core/text/mention.dart';
import '../../../data/models/work_item.dart';
import '../../../data/models/work_item_form.dart';
import '../../../theme/theme.dart';
import '../../shared/attachments/pending_attachments.dart';
import '../../shared/mention/mention_controller.dart';
import '../../shared/mention/mention_field.dart';
import '../../shared/mention/mention_hint.dart';
import '../../shared/mention/mention_source.dart';
import '../../wiki/wiki_page_source.dart';
import '../../wiki/widgets/wiki_page_picker_sheet.dart';
import '../form/controls/attachment_picker.dart';
import '../form/controls/attachments_section.dart' show AttachmentSource;
import 'work_item_visuals.dart';

/// What the state sheet answers with: the target state and, when the type's
/// rules require one, the reason for the move.
class StateChange {
  const StateChange(this.state, {this.reason});

  final String state;
  final String? reason;
}

/// The **legal transitions** from the item's current state
/// (`transitions[state]`, spike w18), not every state of the type, in the
/// type's own state order.
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
  final fallback = type == null
      ? const <String>[]
      : (type.transitionsFrom(item.state).isNotEmpty
            ? type.transitionsFrom(item.state)
            : [for (final s in type.states) s.name]);
  final legal = transitions.isNotEmpty ? transitions : fallback;
  return pickStateChange(
    context,
    states: legal,
    current: item.state,
    colorOf: (context, state) => visuals.stateColorFor(context, item, state),
    categoryOf: (state) => type?.stateNamed(state)?.category,
    reason: reason,
  );
}

/// The state picker itself, over a plain list of state names, so the work
/// item form's header chip and the detail page share one picker.
///
/// A phone gets the bottom sheet; from medium up it is the centered dialog
/// every other picker of the form uses, which also keeps the last row clear
/// of the screen edge (iPad walkthrough).
Future<StateChange?> pickStateChange(
  BuildContext context, {
  required List<String> states,
  required String current,
  required Color Function(BuildContext context, String state) colorOf,
  String? Function(String state)? categoryOf,
  FieldSpec? reason,
}) {
  if (!context.breakpoint.isCompact) {
    return showDialog<StateChange>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
            child: _StateSheet(
              states: states,
              current: current,
              colorOf: colorOf,
              categoryOf: categoryOf,
              reason: reason,
            ),
          ),
        ),
      ),
    );
  }
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
///
/// Serves the work item Discussion and the pull request Comments tab. With a
/// [mentions] source it offers people, work items and pull requests behind
/// `@`, `#` and `!`, and what it submits is the **wire** text — `@<guid>` for
/// each picked person — because that is what Azure DevOps turns into a real
/// mention (research/16 §1). The serialisation happens here rather than in a
/// repository so an offline comment is already in wire form when the write
/// queue stores it as a plain string (M13).
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.onSubmit,
    this.busy = false,
    this.mentions,
    this.attachments,
    this.wikiPages,
    this.offline = false,
    this.onAttachmentsDropped,
    this.pick = pickAttachment,
  });

  final Future<bool> Function(String text) onSubmit;
  final bool busy;

  /// Null leaves a plain field with no picker, which is what a host that has
  /// not loaded its people yet passes.
  final MentionSource? mentions;

  /// Where a picked file is uploaded on Send. Null — the default, and what
  /// every host that has not been wired passes — leaves no attach button
  /// at all (research/17 §4).
  final AttachmentSource? attachments;

  /// The project's wikis, for the book button beside attach. Null — what a
  /// host with no wiki in scope passes — leaves no button (research/20 K12).
  final WikiPageSource? wikiPages;

  /// The host's last request could not reach the service: attaching is off
  /// with the reason in the tooltip (decision T6).
  final bool offline;

  /// The host queues text offline, so a comment whose files could not be
  /// uploaded still posts later without them, and it is told how many were
  /// dropped so its message can say so (T6). Null leaves the comment
  /// unposted with the failure on the chip.
  final void Function(int files)? onAttachmentsDropped;

  /// The platform picker, injected by the tests.
  final Future<PickedAttachment?> Function(AttachmentPickSource) pick;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer>
    with ComposerAttachments<CommentComposer> {
  final _controller = MentionController();

  /// Owned here so the picker can give the focus back to the field after a
  /// page is inserted (K12).
  final _focus = FocusNode();
  bool _hasText = false;

  @override
  AttachmentSource? get attachmentSource => widget.attachments;

  @override
  Future<PickedAttachment?> Function(AttachmentPickSource) get attachmentPick =>
      widget.pick;

  @override
  bool get attachmentsOffline => widget.offline;

  @override
  void Function(int files)? get onAttachmentsDropped =>
      widget.onAttachmentsDropped;

  /// One busy state covers the uploads and the post (T3): the host only
  /// knows about the post.
  bool get _busy => widget.busy || uploadingAttachments;

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
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    // Wire form, not what is on screen: `@Kelly Kamm` posts as `@<guid>`.
    final text = _controller.toWire(MentionWire.markdown).trim();
    // A comment may be files alone (T3).
    if (text.isEmpty && pending.isEmpty) return;
    // Uploads first, then the links go on the end of the wire text (T8).
    // A refusal leaves the text and the chips where they are.
    final body = await bodyWithAttachments(text);
    if (body == null || body.isEmpty || !mounted) return;
    final ok = await widget.onSubmit(body);
    if (!ok || !mounted) return;
    _controller.clear();
    clearAttachments();
    // The keyboard goes with the comment (Kelly, 2026-09-14): the posted
    // comment is what you want to see next, not an empty box.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A `Scaffold` never lifts its `bottomNavigationBar` for the keyboard:
    // it only shortens the body, and the bar stays at the bottom of the box
    // it was given. Inside the project shell that box already stops above
    // the keyboard (the shell spends the inset and zeroes it below), so
    // this is 0 there; on a page over the shell — the pull request detail
    // page, a work item opened from one — the box is the whole screen and
    // the bar would sit behind the keyboard and its suggestion strip
    // (Kelly's iPhone, 2026-09-14). Growing the bar by the inset keeps the
    // field above the keyboard on both.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        // The home indicator is under the keyboard; nothing to clear.
        bottom: keyboard <= 0,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.sm,
            Spacing.sm,
            Spacing.sm + keyboard,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Above the Send button, so "@kelly is not a mention" is read
              // before the comment goes (M7).
              MentionHint(controller: _controller),
              // The files ride above the field, where what is about to be
              // sent can be read and removed (T7).
              attachmentsBar(busy: _busy),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: MentionField(
                      controller: _controller,
                      source: widget.mentions,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      contentInsertionConfiguration: contentInsertion,
                      decoration: const InputDecoration(
                        hintText: 'Add a comment (Markdown)',
                        isDense: true,
                      ),
                    ),
                  ),
                  // Left of Send, so Send stays the rightmost, thumb-
                  // reachable control (DESIGN §6).
                  if (widget.wikiPages != null)
                    WikiPageButton(
                      source: widget.wikiPages!,
                      controller: _controller,
                      focusNode: _focus,
                      enabled: !_busy,
                    ),
                  if (canAttach) attachButton(busy: _busy),
                  const SizedBox(width: Spacing.xs),
                  IconButton.filled(
                    tooltip: 'Post comment',
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: (_hasText || pending.isNotEmpty) && !_busy
                        ? _send
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
