import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

/// The value meaning "only the signed-in user". Not an identity id, so it
/// can never collide with one.
const String kMePersonFilter = '@me';

/// One row of the person filter: a team member and how many tasks in this
/// sprint are theirs.
class SprintPerson {
  const SprintPerson({
    required this.id,
    required this.displayName,
    this.count = 0,
  });

  /// `IdentityRef.id`, or the unique name when there is no id.
  final String id;
  final String displayName;
  final int count;
}

/// The app bar's person filter (S10): Everyone, Me, and each member with a
/// task count. Group-by-people is deliberately not built — the filter
/// covers the daily-scrum case without a second layout (r2 §8.7).
///
/// [selected] is null for Everyone, [kMePersonFilter] for Me, otherwise a
/// member's id.
class PersonFilterMenu extends StatelessWidget {
  const PersonFilterMenu({
    super.key,
    required this.people,
    required this.selected,
    required this.onSelected,
    this.meCount,
  });

  final List<SprintPerson> people;
  final String? selected;
  final ValueChanged<String?> onSelected;

  /// Tasks assigned to the signed-in user, when the page knows who that is.
  final int? meCount;

  @override
  Widget build(BuildContext context) {
    final active = selected != null;
    return PopupMenuButton<String>(
      tooltip: 'Filter by person',
      // The floating glass rail sits just outside the page's trailing edge
      // on Apple tablets, so a menu aligned to its own button opens hard
      // against it (DESIGN.md §7).
      offset: kTrailingMenuOffset,
      icon: Icon(active ? Icons.person : Icons.person_outline),
      onSelected: (value) => onSelected(value == _everyone ? null : value),
      itemBuilder: (context) => [
        CheckedPopupMenuItem<String>(
          value: _everyone,
          checked: selected == null,
          child: const Text('Everyone'),
        ),
        CheckedPopupMenuItem<String>(
          value: kMePersonFilter,
          checked: selected == kMePersonFilter,
          child: Text(meCount == null ? 'Me' : 'Me · $meCount'),
        ),
        if (people.isNotEmpty) const PopupMenuDivider(),
        for (final person in people)
          CheckedPopupMenuItem<String>(
            value: person.id,
            checked: selected == person.id,
            child: Text('${person.displayName} · ${person.count}'),
          ),
      ],
    );
  }

  static const _everyone = '@everyone';
}
