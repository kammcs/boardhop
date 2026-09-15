import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/http/ado_exceptions.dart';
import '../../data/models/wiki.dart';
import '../../data/repositories/wiki_repository.dart';

/// One picked page, as the composer inserts it (K12).
@immutable
class WikiPageLink {
  const WikiPageLink({required this.title, required this.url});

  /// The page title, which is the Markdown link's text.
  final String title;

  /// The web URL: the id form when the node carried an id, the path form
  /// when it did not (both open the reader, research/20 §1).
  final String url;

  /// What goes into the field at the caret. Plain Markdown, so
  /// `MentionController` leaves it alone.
  String get markdown => '[$title]($url)';
}

/// Everything the composers' wiki-page picker needs from its host (K12),
/// as closures — the shape `MentionSource` and `AttachmentSource` already
/// use, so the sheet is testable without a repository or a network.
///
/// Null anywhere a composer takes one means the host has no wiki to offer
/// and no book button is drawn.
class WikiPageSource {
  const WikiPageSource({
    required this.org,
    required this.project,
    required this.wikis,
    required this.tree,
  });

  /// The source for [project], reading through [repository].
  ///
  /// Neither closure throws: the picker is a nicety on top of a comment
  /// box, so a refusal or an offline phone falls back to the cached copy
  /// and then to nothing at all.
  factory WikiPageSource.of(
    WikiRepository repository, {
    required String org,
    required String project,
  }) => WikiPageSource(
    org: org,
    project: project,
    wikis: () async {
      try {
        return await repository.wikis(org, project);
      } on AdoException {
        return await repository.cachedWikis(org, project) ?? const <Wiki>[];
      }
    },
    tree: (wiki) async {
      try {
        return await repository.tree(
          org,
          project,
          wiki.id,
          version: wiki.version,
        );
      } on AdoException {
        return repository.cachedTree(
          org,
          project,
          wiki.id,
          version: wiki.version,
        );
      }
    },
  );

  /// The source for the project on screen, or null when no [WikiRepository]
  /// is in scope — which is what a widget test that provides only the
  /// repositories it needs looks like.
  static WikiPageSource? maybeOf(
    BuildContext context, {
    required String org,
    required String project,
  }) {
    try {
      return WikiPageSource.of(
        context.read<WikiRepository>(),
        org: org,
        project: project,
      );
    } on Object {
      return null;
    }
  }

  final String org;

  /// The project name the URLs are written with, and the project every read
  /// is made against.
  final String project;

  /// The project's wikis, project wiki first. Empty where there is none.
  final Future<List<Wiki>> Function() wikis;

  /// One wiki's page tree (the root node), or null when it cannot be read.
  final Future<WikiPageNode?> Function(Wiki wiki) tree;
}
