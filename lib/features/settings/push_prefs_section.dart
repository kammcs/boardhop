import 'package:flutter/material.dart';

import '../../data/models/push_prefs.dart';
import '../../data/repositories/push_prefs_repository.dart';
import '../../theme/theme.dart';

/// Settings → Notifications → **Push**, one section per organization this
/// account is registered with (research/14 §6, decision D5).
///
/// The document lives on the relay per `(org, userId)`, so this reads it when
/// the section opens and writes on every change. Writes are **optimistic**: the
/// row moves at once, the PUT follows, and a refusal puts the row back and says
/// so. A relay too old to know `/v1/prefs` answers 404 and the section says
/// "Preferences unavailable" rather than showing defaults that are not in
/// force.
class PushPrefsSection extends StatefulWidget {
  const PushPrefsSection({
    super.key,
    required this.org,
    required this.repository,
  });

  final String org;
  final PushPrefsRepository repository;

  @override
  State<PushPrefsSection> createState() => _PushPrefsSectionState();
}

class _PushPrefsSectionState extends State<PushPrefsSection> {
  PushPrefs? _prefs;
  PushPrefsStatus? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // The cached copy first, so the section opens offline with what it last
    // saw, then whatever the relay says.
    final cached = await widget.repository.cached(widget.org);
    if (!mounted) return;
    if (cached != null) setState(() => _prefs = cached);
    final result = await widget.repository.fetch(widget.org);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _status = result.status;
      if (result.prefs != null) _prefs = result.prefs;
      if (result.status == PushPrefsStatus.unavailable) _prefs = null;
    });
  }

  /// Moves the UI, writes, and puts it back if the relay refused.
  Future<void> _update(PushPrefs next) async {
    final previous = _prefs;
    setState(() => _prefs = next);
    final result = await widget.repository.save(widget.org, next);
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _status = PushPrefsStatus.ok;
        if (result.prefs != null) _prefs = result.prefs;
      });
      return;
    }
    setState(() => _prefs = previous);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.status == PushPrefsStatus.unavailable
              ? 'This relay cannot store notification preferences yet.'
              : 'Could not save the change for ${widget.org}.',
        ),
        action: SnackBarAction(label: 'Retry', onPressed: () => _update(next)),
        duration: const Duration(seconds: 6),
        // Flutter 3.47 keeps a snackbar with an action open until it is
        // dismissed, and every later one queues behind it.
        persist: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final prefs = _prefs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.xl,
            Spacing.lg,
            Spacing.sm,
          ),
          child: Text(
            'Push · ${widget.org}',
            style: textTheme.titleSmall?.copyWith(color: scheme.primary),
          ),
        ),
        if (prefs == null)
          ListTile(
            leading: Icon(
              _loading ? Icons.cloud_queue : Icons.cloud_off_outlined,
              color: scheme.onSurfaceVariant,
            ),
            title: Text(_loading ? 'Loading…' : 'Preferences unavailable'),
            subtitle: Text(
              _loading
                  ? 'Reading what the relay has for ${widget.org}.'
                  : _status == PushPrefsStatus.unavailable
                  ? 'The relay for ${widget.org} is older than this app and '
                        'cannot store notification preferences yet.'
                  : 'The relay could not be reached. Pull down to try again.',
            ),
          )
        else
          ..._rows(context, prefs),
      ],
    );
  }

  List<Widget> _rows(BuildContext context, PushPrefs prefs) {
    final on = prefs.enabled;
    return [
      SwitchListTile(
        value: prefs.enabled,
        onChanged: (v) => _update(prefs.copyWith(enabled: v)),
        title: const Text('Push notifications'),
        subtitle: Text(
          'Wake Boardhop for changes in ${widget.org}, even when it is closed.',
        ),
        secondary: const Icon(Icons.podcasts_outlined),
      ),
      _GroupLabel('Work items', enabled: on),
      SwitchListTile(
        value: prefs.workItemsAssigned,
        onChanged: on
            ? (v) => _update(prefs.copyWith(workItemsAssigned: v))
            : null,
        title: const Text('Assigned to me'),
      ),
      SwitchListTile(
        value: prefs.workItemsStateChanged,
        onChanged: on
            ? (v) => _update(prefs.copyWith(workItemsStateChanged: v))
            : null,
        title: const Text('State changes'),
      ),
      _ChoiceRow<CommentPref>(
        title: 'Comments',
        options: CommentPref.values,
        selected: prefs.workItemsComments,
        labelOf: (v) => v.label,
        onChanged: on
            ? (v) => _update(prefs.copyWith(workItemsComments: v))
            : null,
      ),
      SwitchListTile(
        value: prefs.workItemsAnyChangeOnMine,
        onChanged: on
            ? (v) => _update(prefs.copyWith(workItemsAnyChangeOnMine: v))
            : null,
        title: const Text('Any change to mine'),
        subtitle: const Text(
          'Other field edits, not only assignment and state.',
        ),
      ),
      _GroupLabel('Pull requests', enabled: on),
      SwitchListTile(
        value: prefs.pullRequestsReviewRequested,
        onChanged: on
            ? (v) => _update(prefs.copyWith(pullRequestsReviewRequested: v))
            : null,
        title: const Text('Review requested'),
      ),
      _ChoiceRow<VotePref>(
        title: 'Votes on mine',
        options: VotePref.values,
        selected: prefs.pullRequestsVotes,
        labelOf: (v) => v.label,
        onChanged: on
            ? (v) => _update(prefs.copyWith(pullRequestsVotes: v))
            : null,
      ),
      _ChoiceRow<PrCommentPref>(
        title: 'Comments',
        options: PrCommentPref.values,
        selected: prefs.pullRequestsComments,
        labelOf: (v) => v.label,
        onChanged: on
            ? (v) => _update(prefs.copyWith(pullRequestsComments: v))
            : null,
      ),
      SwitchListTile(
        value: prefs.pullRequestsCompletedAbandoned,
        onChanged: on
            ? (v) => _update(prefs.copyWith(pullRequestsCompletedAbandoned: v))
            : null,
        title: const Text('Completed or abandoned'),
      ),
      SwitchListTile(
        value: prefs.pullRequestsPushes,
        onChanged: on
            ? (v) => _update(prefs.copyWith(pullRequestsPushes: v))
            : null,
        title: const Text('New pushes'),
        subtitle: const Text('Every new iteration on a review of yours.'),
      ),
      _GroupLabel('Builds and approvals', enabled: on),
      _ChoiceRow<BuildPref>(
        title: 'Builds',
        options: BuildPref.values,
        selected: prefs.builds,
        labelOf: (v) => v.label,
        onChanged: on ? (v) => _update(prefs.copyWith(builds: v)) : null,
      ),
      SwitchListTile(
        value: prefs.approvals,
        onChanged: on ? (v) => _update(prefs.copyWith(approvals: v)) : null,
        title: const Text('Approvals waiting for me'),
      ),
      _GroupLabel('Quiet hours', enabled: on),
      SwitchListTile(
        value: prefs.quietHours.enabled,
        onChanged: on
            ? (v) => _update(
                prefs.copyWith(quietHours: prefs.quietHours.copyWith(enabled: v)),
              )
            : null,
        title: const Text('Quiet hours'),
        subtitle: const Text(
          'Notifications in the window are dropped, not delayed; they still '
          'appear in the feed.',
        ),
        secondary: const Icon(Icons.bedtime_outlined),
      ),
      if (prefs.quietHours.enabled) ...[
        _TimeRow(
          title: 'From',
          value: prefs.quietHours.start,
          onChanged: on
              ? (v) => _update(
                  prefs.copyWith(
                    quietHours: prefs.quietHours.copyWith(start: v),
                  ),
                )
              : null,
        ),
        _TimeRow(
          title: 'Until',
          value: prefs.quietHours.end,
          onChanged: on
              ? (v) => _update(
                  prefs.copyWith(quietHours: prefs.quietHours.copyWith(end: v)),
                )
              : null,
        ),
        SwitchListTile(
          value: prefs.quietHours.exceptApprovals,
          onChanged: on
              ? (v) => _update(
                  prefs.copyWith(
                    quietHours: prefs.quietHours.copyWith(exceptApprovals: v),
                  ),
                )
              : null,
          title: const Text('Except approvals'),
        ),
      ],
      _GroupLabel('Muted', enabled: on),
      if (prefs.mutedArtifacts.isEmpty)
        const ListTile(
          title: Text('Nothing muted'),
          subtitle: Text(
            'Mute a pull request or a work item from its own menu.',
          ),
        )
      else
        for (final muted in prefs.mutedArtifacts)
          ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: Text(muted.label),
            subtitle: Text(
              muted.until == null
                  ? 'Until you unmute it'
                  : 'Until ${muted.until!.toLocal()}',
            ),
            trailing: IconButton(
              tooltip: 'Unmute ${muted.label}',
              icon: const Icon(Icons.close),
              onPressed: on
                  ? () => _update(
                      prefs.copyWith(
                        mutedArtifacts: [
                          for (final other in prefs.mutedArtifacts)
                            if (other.key != muted.key) other,
                        ],
                      ),
                    )
                  : null,
            ),
          ),
      // research/14 §6: reported by the relay, never editable, and shown so
      // people know why they do not hear about their own edits.
      const ListTile(
        enabled: false,
        leading: Icon(Icons.person_outline),
        title: Text('You are never notified about your own changes'),
      ),
    ];
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, {required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.xs,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: enabled ? scheme.onSurfaceVariant : scheme.outline,
        ),
      ),
    );
  }
}

/// One closed-vocabulary preference. Chips rather than a segmented button:
/// four options do not fit one row at compact width, and a `Wrap` of chips
/// reads the same on a phone and on a tablet.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String title;
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: enabled ? scheme.onSurface : scheme.outline,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(labelOf(option)),
                  selected: option == selected,
                  onSelected: enabled
                      ? (chosen) {
                          if (chosen) onChanged!(option);
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One end of the quiet window. `HH:mm` in and out, the platform picker in
/// between.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final parsed = QuietHours.parse(value);
    return ListTile(
      enabled: onChanged != null,
      title: Text(title),
      trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
      onTap: onChanged == null
          ? null
          : () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: parsed?.$1 ?? 22,
                  minute: parsed?.$2 ?? 0,
                ),
              );
              if (picked == null) return;
              onChanged!(QuietHours.format(picked.hour, picked.minute));
            },
    );
  }
}
