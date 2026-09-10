import 'package:flutter/material.dart';

import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import 'work_item_visuals.dart';

/// Bottom sheet listing the states the item's type allows.
Future<String?> pickState(
  BuildContext context, {
  required WorkItem item,
  required WorkItemVisuals visuals,
}) {
  final type = visuals.typeOf(item);
  final states = type?.states ?? const <WorkItemState>[];
  return showModalBottomSheet<String>(
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
            child: Text('State', style: Theme.of(context).textTheme.titleMedium),
          ),
          if (states.isEmpty)
            const ListTile(title: Text('No states known for this type.')),
          for (final s in states)
            ListTile(
              leading: StateDot(
                color: visuals.stateColorFor(context, item, s.name),
                size: 12,
              ),
              title: Text(s.name),
              subtitle: s.category == null ? null : Text(s.category!),
              trailing: s.name == item.state ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(s.name),
            ),
        ],
      ),
    ),
  );
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
            title: Text(meLabel == null ? 'Assign to me' : 'Assign to $meLabel'),
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
