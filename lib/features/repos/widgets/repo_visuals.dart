import 'package:flutter/material.dart';

import '../../../data/models/git_repository.dart';

// `formatBytes` moved to `core/util/format.dart` in phase 5 (the work item
// attachments page needs it too); re-exported so the repo screens that
// import this file keep working.
export '../../../core/util/format.dart' show formatBytes;

/// Language dot colors, the ones GitHub and GitLab use so the cue reads
/// the same as on the web. Anything unlisted gets a neutral dot.
const _languageColors = <String, Color>{
  'TypeScript': Color(0xFF3178C6),
  'JavaScript': Color(0xFFF1E05A),
  'C#': Color(0xFF178600),
  'Dart': Color(0xFF00B4AB),
  'Java': Color(0xFFB07219),
  'Kotlin': Color(0xFFA97BFF),
  'Swift': Color(0xFFF05138),
  'Objective-C': Color(0xFF438EFF),
  'Python': Color(0xFF3572A5),
  'Go': Color(0xFF00ADD8),
  'Rust': Color(0xFFDEA584),
  'Ruby': Color(0xFF701516),
  'PHP': Color(0xFF4F5D95),
  'C++': Color(0xFFF34B7D),
  'C': Color(0xFF555555),
  'HTML': Color(0xFFE34C26),
  'CSS': Color(0xFF563D7C),
  'SCSS': Color(0xFFC6538C),
  'Vue': Color(0xFF41B883),
  'SQL': Color(0xFFE38C00),
  'Shell': Color(0xFF89E051),
  'PowerShell': Color(0xFF012456),
  'Markdown': Color(0xFF083FA1),
  'YAML': Color(0xFFCB171E),
  'JSON': Color(0xFF292929),
  'Bicep': Color(0xFF519ABA),
  'HCL': Color(0xFF844FBA),
  'Dockerfile': Color(0xFF384D54),
};

Color languageColor(BuildContext context, String? name) =>
    _languageColors[name] ?? Theme.of(context).colorScheme.outline;

/// Small colored dot for a language, sized to the text next to it.
class LanguageDot extends StatelessWidget {
  const LanguageDot({super.key, required this.language, this.size = 10});

  final String? language;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: languageColor(context, language),
      shape: BoxShape.circle,
    ),
  );
}

/// Ordered sections of the repository list: favorites, recents, the rest,
/// then disabled or in-maintenance repositories.
class RepoSections {
  const RepoSections({
    required this.favorites,
    required this.recents,
    required this.all,
    required this.inactive,
  });

  factory RepoSections.build(
    List<GitRepository> repos, {
    required Set<String> favoriteIds,
    required List<String> recentIds,
    String query = '',
  }) {
    final q = query.trim().toLowerCase();
    final visible = q.isEmpty
        ? repos
        : repos.where((r) => r.name.toLowerCase().contains(q)).toList();
    final byId = {for (final r in visible) r.id: r};
    final favorites = [
      for (final r in visible)
        if (favoriteIds.contains(r.id) && r.isActive) r,
    ];
    final recents = [
      for (final id in recentIds)
        if (byId[id] case final r? when r.isActive && !favoriteIds.contains(id))
          r,
    ];
    final placed = {...favorites.map((r) => r.id), ...recents.map((r) => r.id)};
    return RepoSections(
      favorites: favorites,
      recents: recents,
      all: [
        for (final r in visible)
          if (r.isActive && !placed.contains(r.id)) r,
      ],
      inactive: [
        for (final r in visible)
          if (!r.isActive) r,
      ],
    );
  }

  final List<GitRepository> favorites;
  final List<GitRepository> recents;
  final List<GitRepository> all;
  final List<GitRepository> inactive;

  bool get isEmpty =>
      favorites.isEmpty && recents.isEmpty && all.isEmpty && inactive.isEmpty;
}
