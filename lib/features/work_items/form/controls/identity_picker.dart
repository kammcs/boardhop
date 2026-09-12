import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/http/ado_exceptions.dart';
import '../../../../data/models/work_item.dart';
import '../../../../data/models/work_item_form.dart';
import '../../../../theme/theme.dart';
import '../../widgets/work_item_visuals.dart';
import '../work_item_form_state.dart';
import 'form_field_slot.dart';

/// What the people sheet answers with; a null [person] is "Unassigned".
class IdentityChoice {
  const IdentityChoice(this.person);

  final IdentityRef? person;
}

/// Everything the people sheet needs, so the form body stays testable
/// without a repository above it.
class IdentitySource {
  const IdentitySource({
    required this.members,
    required this.search,
    required this.resolve,
    this.me,
    this.recent = const [],
    this.onPicked,
  });

  /// The team's members: the cached offline list (spike s25 found the type's
  /// identity `allowedValues` empty).
  final Future<List<IdentityRef>> Function() members;

  /// Project-scoped Graph subject query, debounced by the sheet.
  final Future<List<IdentityRef>> Function(String query) search;

  /// `graph/storagekeys` for a Graph hit, which carries no identity id.
  final Future<IdentityRef> Function(IdentityRef person) resolve;

  final IdentityRef? me;

  /// Recently assigned people for this project, most recent first.
  final List<IdentityRef> recent;

  final void Function(IdentityRef person)? onPicked;
}

Future<IdentityChoice?> pickIdentity(
  BuildContext context, {
  required String title,
  required IdentitySource source,
  IdentityRef? current,
}) {
  // A tablet gets the same content in a centered dialog instead of a
  // full-height sheet (research/11 §4.5).
  if (!context.breakpoint.isCompact) {
    return showDialog<IdentityChoice>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _IdentitySheet(
            title: title,
            source: source,
            current: current,
            dialog: true,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<IdentityChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) =>
        _IdentitySheet(title: title, source: source, current: current),
  );
}

class _IdentitySheet extends StatefulWidget {
  const _IdentitySheet({
    required this.title,
    required this.source,
    this.current,
    this.dialog = false,
  });

  final String title;
  final IdentitySource source;
  final IdentityRef? current;

  /// Centered dialog rather than a bottom sheet: a shorter box and its own
  /// title padding, since there is no drag handle above it.
  final bool dialog;

  @override
  State<_IdentitySheet> createState() => _IdentitySheetState();
}

class _IdentitySheetState extends State<_IdentitySheet> {
  static const _minQuery = 2;
  static const _searchDebounce = Duration(milliseconds: 300);

  final _query = TextEditingController();
  Timer? _debounce;
  List<IdentityRef> _members = const [];
  List<IdentityRef> _hits = const [];
  bool _searching = false;
  bool _resolving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final members = await widget.source.members();
      if (mounted) setState(() => _members = members);
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _onQuery(String text) {
    setState(() {});
    _debounce?.cancel();
    final query = text.trim();
    if (query.length < _minQuery) {
      setState(() {
        _hits = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(_searchDebounce, () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    try {
      final hits = await widget.source.search(query);
      if (mounted && _query.text.trim() == query) {
        setState(() => _hits = hits);
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _choose(IdentityRef person, {bool resolve = false}) async {
    var picked = person;
    if (resolve && person.id == null) {
      setState(() => _resolving = true);
      try {
        picked = await widget.source.resolve(person);
      } on AdoException {
        // The unique name form still works as a field value.
      } finally {
        if (mounted) setState(() => _resolving = false);
      }
    }
    widget.source.onPicked?.call(picked);
    if (mounted) Navigator.of(context).pop(IdentityChoice(picked));
  }

  bool _matches(IdentityRef person, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return person.displayName.toLowerCase().contains(q) ||
        (person.uniqueName ?? '').toLowerCase().contains(q);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = _query.text.trim();
    // The unique name first: a team member carries an identity id and the
    // same person from the Graph search carries only a descriptor, so
    // keying on the id would list them twice.
    String key(IdentityRef p) =>
        (p.uniqueName ?? p.id ?? p.displayName).toLowerCase();

    // "Me" is pinned above the list, so the same person must not come back
    // from the team members or the Graph hits below it.
    final me = widget.source.me;
    final seen = <String>{if (me != null) key(me)};

    final local = <IdentityRef>[
      for (final p in [...widget.source.recent, ..._members])
        if (_matches(p, query) && seen.add(key(p))) p,
    ];
    final remote = <IdentityRef>[
      for (final p in _hits)
        if (!seen.contains(key(p))) p,
    ];

    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: widget.dialog ? math.min(560, height * 0.8) : height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                Spacing.lg,
                widget.dialog ? Spacing.lg : 0,
                Spacing.lg,
                Spacing.sm,
              ),
              child: Text(widget.title, style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search people',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching || _resolving
                      ? const Padding(
                          padding: EdgeInsets.all(Spacing.md),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: _onQuery,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (_error != null)
                    ListTile(
                      leading: Icon(Icons.error_outline, color: scheme.error),
                      title: Text(_error!),
                    ),
                  if (me != null && _matches(me, query))
                    _PersonTile(
                      person: me,
                      label: 'Me',
                      selected: _same(widget.current, me),
                      onTap: () => _choose(me),
                    ),
                  ListTile(
                    leading: const Icon(Icons.person_off_outlined),
                    title: const Text('Unassigned'),
                    trailing: widget.current == null
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () =>
                        Navigator.of(context).pop(const IdentityChoice(null)),
                  ),
                  const Divider(height: 1),
                  for (final person in local)
                    _PersonTile(
                      person: person,
                      selected: _same(widget.current, person),
                      onTap: () => _choose(person),
                    ),
                  if (local.isEmpty && !(me != null && _matches(me, query)))
                    Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: Text(
                        'No team member matches.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (remote.isNotEmpty) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.lg,
                        Spacing.md,
                        Spacing.lg,
                        Spacing.xs,
                      ),
                      child: Text(
                        'In the project',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final person in remote)
                      _PersonTile(
                        person: person,
                        selected: _same(widget.current, person),
                        onTap: () => _choose(person, resolve: true),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _same(IdentityRef? a, IdentityRef? b) {
    if (a == null || b == null) return false;
    if (a.id != null && b.id != null) return a.id == b.id;
    return (a.uniqueName ?? a.displayName).toLowerCase() ==
        (b.uniqueName ?? b.displayName).toLowerCase();
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.onTap,
    this.label,
    this.selected = false,
  });

  final IdentityRef person;
  final VoidCallback onTap;
  final String? label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: IdentityAvatar(identity: person, radius: 16),
      title: Text(
        label == null ? person.displayName : '${person.displayName} ($label)',
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: person.uniqueName == null
          ? null
          : Text(
              person.uniqueName!,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}

/// An `identity` field inside a group card (a custom QA assignee, say). The
/// header's Assigned to chip opens the same sheet.
class IdentityControl extends StatelessWidget {
  const IdentityControl({
    super.key,
    required this.state,
    required this.field,
    required this.label,
    required this.source,
    this.enabled = true,
  });

  final WorkItemFormState state;
  final FieldSpec field;
  final String label;
  final IdentitySource? source;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final reference = field.referenceName;
    final raw = state.value(reference);
    final person = raw is IdentityRef ? raw : IdentityRef.fromField(raw);
    return FormFieldSlot(
      label: label,
      required: field.alwaysRequired,
      helpText: field.helpText,
      error: state.errorFor(reference),
      child: PickerTile(
        leading: IdentityAvatar(identity: person, radius: 12),
        text: person?.displayName ?? 'Unassigned',
        placeholder: person == null,
        enabled: enabled && source != null,
        hasError: state.errorFor(reference) != null,
        onTap: () async {
          final picked = await pickIdentity(
            context,
            title: label,
            source: source!,
            current: person,
          );
          if (picked == null) return;
          state.setValue(reference, picked.person);
        },
      ),
    );
  }
}
