import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/wiki.dart';
import '../../data/repositories/wiki_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import 'widgets/wiki_page_view.dart';
import 'widgets/wiki_tree_view.dart';

/// One wiki page as a page of its own, outside the project tab shell
/// (research/20 §4.3).
///
/// All this adds to [WikiPageView] is the wiki: the route can only carry the
/// wiki's id or name, and the reader needs the whole [Wiki] — a code wiki's
/// branch and mapped path decide where its attachments are read from (K8).
/// The list is cached for a day, so this is normally free and works offline.
class WikiPagePage extends StatefulWidget {
  const WikiPagePage({
    super.key,
    required this.org,
    required this.project,
    required this.wikiIdOrName,
    this.path,
    this.id,
    this.version,
    this.anchor,
  });

  final String org;
  final String project;

  /// `:wiki` — a GUID or a wiki name; both work on every wiki route.
  final String wikiIdOrName;

  final String? path;
  final int? id;
  final String? version;
  final String? anchor;

  @override
  State<WikiPagePage> createState() => _WikiPagePageState();
}

class _WikiPagePageState extends State<WikiPagePage> {
  Wiki? _wiki;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final repo = context.read<WikiRepository>();
    final cached = await repo.cachedWikis(widget.org, widget.project);
    if (!mounted) return;
    final fromCache = _match(cached);
    if (fromCache != null) {
      setState(() {
        _wiki = fromCache;
        _loading = false;
      });
      return;
    }
    try {
      final wikis = await repo.wikis(widget.org, widget.project);
      if (!mounted) return;
      final found = _match(wikis);
      setState(() {
        _wiki = found;
        _loading = false;
        _error = found == null
            ? 'This wiki is not in ${widget.project} any more.'
            : null;
      });
    } on WikiUnavailable catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } on AdoAuthException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      context.read<AuthBloc>().add(
        AuthInteractionRequired(
          e.message,
          accountId: AccountScope.maybeOf(context),
        ),
      );
    } on AdoException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  /// By GUID first, then by name — the route carries whichever the link
  /// that built it knew.
  Wiki? _match(List<Wiki>? wikis) {
    if (wikis == null || wikis.isEmpty) return null;
    final wanted = widget.wikiIdOrName.toLowerCase();
    for (final wiki in wikis) {
      if (wiki.id.toLowerCase() == wanted) return wiki;
    }
    for (final wiki in wikis) {
      if (wiki.name.toLowerCase() == wanted) return wiki;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final wiki = _wiki;
    if (wiki != null) {
      return WikiPageView(
        org: widget.org,
        project: widget.project,
        wiki: wiki,
        path: widget.path,
        id: widget.id,
        version: widget.version,
        anchor: widget.anchor,
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Wiki'),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ContentColumn(
          child: ListView(
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) WikiNotice(message: _error!),
            ],
          ),
        ),
      ),
    );
  }
}
