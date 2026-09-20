import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/http/ado_exceptions.dart';
import '../../../data/models/pull_request.dart';
import '../../../data/models/sprint.dart';
import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import '../../work_items/widgets/work_item_visuals.dart';
import 'pr_visuals.dart';

/// What a reviewer row's menu offers (R12).
enum PrReviewerAction {
  makeRequired('Make required'),
  makeOptional('Make optional'),
  resetVote('Reset vote'),
  remove('Remove'),
  flag('Flag for attention'),
  unflag('Remove flag'),
  decline('Decline'),
  undecline('Undo decline');

  const PrReviewerAction(this.label);

  final String label;
}

/// The menu for one row, as a list so the rules are testable without a
/// pump.
///
/// Reset vote is the author's (the batch `PATCH reviewers` route is the
/// only way, and it is theirs); flag and decline are the reviewer's own,
/// and the creator cannot decline their own pull request — the service
/// answers HTTP 500 (research/22 §1).
List<PrReviewerAction> reviewerActions({
  required PrReviewer reviewer,
  required PullRequest pr,
  String? meId,
}) {
  if (!pr.isActive) return const [];
  final isMe = meId != null && reviewer.id == meId;
  final isAuthor = meId != null && pr.createdBy.id == meId;
  return [
    reviewer.isRequired
        ? PrReviewerAction.makeOptional
        : PrReviewerAction.makeRequired,
    if (isAuthor && reviewer.vote != PrVote.none) PrReviewerAction.resetVote,
    if (isMe)
      reviewer.isFlagged ? PrReviewerAction.unflag : PrReviewerAction.flag,
    if (isMe && !isAuthor)
      reviewer.hasDeclined
          ? PrReviewerAction.undecline
          : PrReviewerAction.decline,
    PrReviewerAction.remove,
  ];
}

/// The Overview's reviewers, with the full R12 action set on each row and
/// an Add reviewer action in the section title.
class ReviewersSection extends StatelessWidget {
  const ReviewersSection({
    super.key,
    required this.pr,
    required this.onAction,
    required this.onAdd,
    this.meId,
    this.busy = false,
  });

  final PullRequest pr;
  final String? meId;
  final void Function(PrReviewer reviewer, PrReviewerAction action) onAction;
  final VoidCallback onAdd;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.lg,
            Spacing.sm,
            Spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Reviewers (${pr.reviewers.length})',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (pr.isActive)
                IconButton(
                  tooltip: 'Add reviewer',
                  icon: const Icon(Icons.person_add_alt),
                  onPressed: busy ? null : onAdd,
                ),
            ],
          ),
        ),
        if (pr.reviewers.isEmpty)
          Padding(
            padding: Spacing.pageHorizontal,
            child: Text(
              'No reviewers yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final r in pr.reviewers)
          _ReviewerRow(
            reviewer: r,
            pr: pr,
            meId: meId,
            busy: busy,
            onAction: (a) => onAction(r, a),
          ),
      ],
    );
  }
}

class _ReviewerRow extends StatelessWidget {
  const _ReviewerRow({
    required this.reviewer,
    required this.pr,
    required this.meId,
    required this.busy,
    required this.onAction,
  });

  final PrReviewer reviewer;
  final PullRequest pr;
  final String? meId;
  final bool busy;
  final ValueChanged<PrReviewerAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final actions = reviewerActions(reviewer: reviewer, pr: pr, meId: meId);
    final subtitle = [
      reviewer.vote.label,
      reviewer.isRequired ? 'Required' : 'Optional',
      if (reviewer.isContainer) 'team',
      if (reviewer.hasDeclined) 'declined',
    ].join(' · ');
    return ListTile(
      dense: true,
      leading: IdentityAvatar(identity: reviewer.identity, radius: 14),
      title: Row(
        children: [
          Flexible(
            child: Text(reviewer.displayName, overflow: TextOverflow.ellipsis),
          ),
          if (reviewer.isFlagged) ...[
            const SizedBox(width: Spacing.xs),
            Tooltip(
              message: 'Flagged for the author',
              child: Icon(Icons.flag, size: 14, color: colors.voteWaiting),
            ),
          ],
        ],
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            voteIcon(reviewer.vote),
            color: voteColor(context, reviewer.vote),
          ),
          if (actions.isNotEmpty)
            PopupMenuButton<PrReviewerAction>(
              tooltip: 'Reviewer actions',
              enabled: !busy,
              onSelected: onAction,
              itemBuilder: (context) => [
                for (final a in actions)
                  PopupMenuItem(value: a, child: Text(a.label)),
              ],
            ),
        ],
      ),
    );
  }
}

/// A reviewer the picker answered with: the identity id the `PUT` needs,
/// the name to report, and whether the row should be required.
typedef ReviewerPick = ({String id, String name, bool isRequired});

/// People and teams, with a Required switch (R12).
///
/// Teams are first-class reviewers (`isContainer: true`; member votes roll
/// up through `votedFor`), and they come from the project's team list
/// rather than the Graph search, which only answers for users.
Future<ReviewerPick?> pickReviewer(
  BuildContext context, {
  required Future<List<SprintTeamRef>> Function() teams,
  required Future<List<IdentityRef>> Function(String query) search,
  required Future<IdentityRef> Function(IdentityRef person) resolve,
  Set<String> existing = const {},
}) {
  if (!context.breakpoint.isCompact) {
    return showBoardhopDialog<ReviewerPick>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _ReviewerPickerSheet(
            teams: teams,
            search: search,
            resolve: resolve,
            existing: existing,
            dialog: true,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<ReviewerPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _ReviewerPickerSheet(
      teams: teams,
      search: search,
      resolve: resolve,
      existing: existing,
    ),
  );
}

class _ReviewerPickerSheet extends StatefulWidget {
  const _ReviewerPickerSheet({
    required this.teams,
    required this.search,
    required this.resolve,
    required this.existing,
    this.dialog = false,
  });

  final Future<List<SprintTeamRef>> Function() teams;
  final Future<List<IdentityRef>> Function(String query) search;
  final Future<IdentityRef> Function(IdentityRef person) resolve;
  final Set<String> existing;
  final bool dialog;

  @override
  State<_ReviewerPickerSheet> createState() => _ReviewerPickerSheetState();
}

class _ReviewerPickerSheetState extends State<_ReviewerPickerSheet> {
  static const _minQuery = 2;
  static const _debounceFor = Duration(milliseconds: 300);

  final _query = TextEditingController();
  Timer? _debounce;
  List<SprintTeamRef> _teams = const [];
  List<IdentityRef> _hits = const [];
  bool _required = false;
  bool _searching = false;
  bool _resolving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    try {
      final teams = await widget.teams();
      if (mounted) setState(() => _teams = teams);
    } on AdoException {
      // The people search still works; a missing team list is not an error
      // worth taking the sheet over.
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
    _debounce = Timer(_debounceFor, () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    try {
      final hits = await widget.search(query);
      if (mounted && _query.text.trim() == query) {
        setState(() => _hits = hits);
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _choosePerson(IdentityRef person) async {
    var picked = person;
    if (picked.id == null) {
      setState(() => _resolving = true);
      try {
        picked = await widget.resolve(person);
      } on AdoException catch (e) {
        if (mounted) setState(() => _error = e.message);
        return;
      } finally {
        if (mounted) setState(() => _resolving = false);
      }
    }
    final id = picked.id;
    if (id == null || id.isEmpty) {
      // A reviewer is addressed by GUID and nothing else; without one there
      // is no write to make.
      if (mounted) {
        setState(() => _error = 'Could not resolve ${picked.displayName}.');
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context)
        .pop((id: id, name: picked.displayName, isRequired: _required));
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
    final q = _query.text.trim().toLowerCase();
    final teams = [
      for (final t in _teams)
        if ((q.isEmpty || t.name.toLowerCase().contains(q)) &&
            !widget.existing.contains(t.id.toLowerCase()))
          t,
    ];
    final people = [
      for (final p in _hits)
        if (p.id == null || !widget.existing.contains(p.id!.toLowerCase())) p,
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
              child: Text('Add reviewer', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search people and teams',
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
            SwitchListTile(
              value: _required,
              onChanged: (v) => setState(() => _required = v),
              title: const Text('Required'),
              subtitle: Text(
                'A required reviewer must approve before the merge.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1),
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
                  if (teams.isNotEmpty) ...[
                    _PickerLabel('Teams'),
                    for (final t in teams)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.groups_outlined),
                        title: Text(t.name, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.of(
                          context,
                        ).pop((id: t.id, name: t.name, isRequired: _required)),
                      ),
                  ],
                  if (people.isNotEmpty) ...[
                    _PickerLabel('People'),
                    for (final p in people)
                      ListTile(
                        dense: true,
                        leading: IdentityAvatar(identity: p, radius: 16),
                        title: Text(
                          p.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: p.uniqueName == null
                            ? null
                            : Text(
                                p.uniqueName!,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                        onTap: () => _choosePerson(p),
                      ),
                  ],
                  if (people.isEmpty && q.length >= _minQuery && !_searching)
                    Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: Text(
                        'Nobody matches "$q".',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (q.length < _minQuery)
                    Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: Text(
                        'Type at least $_minQuery letters to search people.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
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

class _PickerLabel extends StatelessWidget {
  const _PickerLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
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
