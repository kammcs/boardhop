/// What the diff's ▲▼ control steps through (R5) and where the reader is in
/// that list (R6), with the file-boundary behaviour of R7.
///
/// Pure model: no widgets, no scrolling. [DiffView] publishes the stops it
/// rebuilt with its rows, the page decides the mode and the position, and
/// [DiffNavPill] draws whatever this says.
library;

import 'package:flutter/material.dart';

/// The three things ▲▼ can walk. Chosen on the control itself (R5).
enum DiffNavMode {
  /// Hunks: the first row of every run of changed lines.
  changes,

  /// Comment threads, unresolved ones first.
  comments,

  /// The pull request's changed files, in the order the Files tab lists
  /// them.
  files;

  String get label => switch (this) {
    DiffNavMode.changes => 'Changes',
    DiffNavMode.comments => 'Comments',
    DiffNavMode.files => 'Files',
  };

  IconData get icon => switch (this) {
    DiffNavMode.changes => Icons.difference_outlined,
    DiffNavMode.comments => Icons.chat_bubble_outline,
    DiffNavMode.files => Icons.description_outlined,
  };
}

/// What one press of an arrow does from where the cursor stands.
enum DiffNavEdge {
  /// Another stop inside this file.
  stop,

  /// No stop left this way: the arrow becomes "Next file: name" (R7).
  file,

  /// Not even a file that way: the arrow becomes "Back to files".
  back,
}

/// Where the reader is among the stops of one mode.
///
/// [stops] are row indices into the diff's rows for [DiffNavMode.changes]
/// and [DiffNavMode.comments], and indices into the pull request's file list
/// for [DiffNavMode.files]. They are in **visit order**, which is ascending
/// for changes and files but unresolved-first for comments (R5), so the
/// list is the order ▼ walks and nothing else may re-sort it.
@immutable
class DiffCursor {
  const DiffCursor({
    required this.mode,
    this.stops = const [],
    this.position,
    this.nextFile,
    this.previousFile,
  });

  final DiffNavMode mode;
  final List<int> stops;

  /// Index into [stops] of the stop the reader is on, or null when nothing
  /// has been jumped to and no stop is on screen.
  final int? position;

  /// Name of the file after this one, null at the last file.
  final String? nextFile;

  /// Name of the file before this one, null at the first file.
  final String? previousFile;

  int get count => stops.length;
  bool get isEmpty => stops.isEmpty;

  /// "3 / 12", or "– / 12" when the reader is between stops.
  String get indicator => '${position == null ? '–' : position! + 1} / $count';

  DiffCursor at(int? position) => DiffCursor(
    mode: mode,
    stops: stops,
    position: position,
    nextFile: nextFile,
    previousFile: previousFile,
  );

  DiffCursor withStops(List<int> stops) => DiffCursor(
    mode: mode,
    stops: stops,
    // A rebuilt row list moves every index: the old position means nothing.
    position: null,
    nextFile: nextFile,
    previousFile: previousFile,
  );

  /// The position implied by rows [first]…[last] being on screen, used when
  /// nothing has been jumped to or the reader has scrolled since (R6).
  /// The lowest stop inside the range wins, so the indicator names the one
  /// nearest the top of the viewport.
  DiffCursor resolvedFrom(int first, int last) {
    if (position != null || stops.isEmpty) return this;
    int? best;
    for (var i = 0; i < stops.length; i++) {
      final row = stops[i];
      if (row < first || row > last) continue;
      if (best == null || row < stops[best]) best = i;
    }
    return best == null ? this : at(best);
  }

  /// Index into [stops] that ▼ moves to, or null at the end.
  int? get nextPosition {
    if (stops.isEmpty) return null;
    final p = position;
    if (p == null) return 0;
    return p + 1 < stops.length ? p + 1 : null;
  }

  /// Index into [stops] that ▲ moves to, or null at the start.
  int? get previousPosition {
    if (stops.isEmpty) return null;
    final p = position;
    if (p == null) return stops.length - 1;
    return p > 0 ? p - 1 : null;
  }

  /// In Files mode the stops *are* the files, so stepping off the last one
  /// is the end of the pull request, not the end of a file.
  DiffNavEdge get downEdge {
    if (nextPosition != null) return DiffNavEdge.stop;
    if (mode != DiffNavMode.files && nextFile != null) return DiffNavEdge.file;
    return DiffNavEdge.back;
  }

  DiffNavEdge get upEdge {
    if (previousPosition != null) return DiffNavEdge.stop;
    if (mode != DiffNavMode.files && previousFile != null) {
      return DiffNavEdge.file;
    }
    return DiffNavEdge.back;
  }

  /// What the ▼ control says when it is not a plain arrow (R7).
  String? get downLabel => switch (downEdge) {
    DiffNavEdge.stop => null,
    DiffNavEdge.file => 'Next file: $nextFile',
    DiffNavEdge.back => 'Back to files',
  };

  String? get upLabel => switch (upEdge) {
    DiffNavEdge.stop => null,
    DiffNavEdge.file => 'Previous file: $previousFile',
    DiffNavEdge.back => 'Back to files',
  };
}
