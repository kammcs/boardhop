import 'package:equatable/equatable.dart';

import '../../core/text/plain_text.dart';
import 'pull_request.dart';
import 'work_item.dart';

/// How a work item search orders its results (research/15 §2: the default is
/// relevance; `$orderBy` on `system.changeddate` is the only other order the
/// app offers).
enum SearchOrder { relevance, changedDate }

/// One run of text inside a highlighted fragment: [isHit] is the part the
/// service wrapped in `<highlighthit>`, which the row draws in bold.
class SearchSpan extends Equatable {
  const SearchSpan(this.text, {this.isHit = false});

  factory SearchSpan.fromJson(Map<String, dynamic> json) => SearchSpan(
    json['text'] as String? ?? '',
    isHit: json['hit'] as bool? ?? false,
  );

  final String text;
  final bool isHit;

  Map<String, dynamic> toJson() => {'text': text, if (isHit) 'hit': true};

  @override
  List<Object?> get props => [text, isHit];
}

/// One highlighted fragment from a search result's `hits[]`.
///
/// The service answers with the matched field's text marked up as
/// `…<highlighthit>term</highlighthit>…`, and for description and history
/// that text is the stored HTML. Parsing splits on the markers first and
/// strips each piece with [PlainText] afterwards, so a tag that straddles a
/// marker cannot swallow the match, and collapses every whitespace run: a
/// search row shows one line, never a paragraph.
class SearchHighlight extends Equatable {
  const SearchHighlight({
    required this.fieldReferenceName,
    required this.spans,
  });

  /// Reads back what [toJson] wrote (the same shape the service sends).
  factory SearchHighlight.fromJson(Map<String, dynamic> json) {
    final fragments = (json['highlights'] as List?) ?? const [];
    return SearchHighlight.parse(
      json['fieldReferenceName'] as String? ?? '',
      fragments.isEmpty ? '' : fragments.first.toString(),
    );
  }

  factory SearchHighlight.parse(String fieldReferenceName, String fragment) =>
      SearchHighlight(
        fieldReferenceName: fieldReferenceName,
        spans: _spansOf(fragment),
      );

  /// Every fragment of every entry of a result's `hits[]`, flattened: one
  /// entry may carry several fragments of the same field.
  static List<SearchHighlight> fromHits(Object? hits) {
    if (hits is! List) return const [];
    final out = <SearchHighlight>[];
    for (final hit in hits) {
      if (hit is! Map) continue;
      final field = hit['fieldReferenceName'] as String? ?? '';
      final fragments = (hit['highlights'] as List?) ?? const [];
      for (final fragment in fragments) {
        out.add(SearchHighlight.parse(field, fragment.toString()));
      }
    }
    return out;
  }

  static final _marker = RegExp(r'</?highlighthit>', caseSensitive: false);
  static final _whitespace = RegExp(r'\s+');

  static List<SearchSpan> _spansOf(String fragment) {
    final raw = <SearchSpan>[];
    var inHit = false;
    var index = 0;
    for (final match in _marker.allMatches(fragment)) {
      raw.add(SearchSpan(fragment.substring(index, match.start), isHit: inHit));
      inHit = !match.group(0)!.startsWith('</');
      index = match.end;
    }
    raw.add(SearchSpan(fragment.substring(index), isHit: inHit));

    final out = <SearchSpan>[];
    for (final span in raw) {
      final text = PlainText.strip(
        span.text,
        trim: false,
      ).replaceAll(_whitespace, ' ');
      if (text.isEmpty) continue;
      if (out.isNotEmpty && out.last.isHit == span.isHit) {
        out[out.length - 1] = SearchSpan(
          '${out.last.text}$text',
          isHit: span.isHit,
        );
      } else {
        out.add(SearchSpan(text, isHit: span.isHit));
      }
    }
    if (out.isNotEmpty) {
      out[0] = SearchSpan(out.first.text.trimLeft(), isHit: out.first.isHit);
      final last = out.length - 1;
      out[last] = SearchSpan(
        out[last].text.trimRight(),
        isHit: out[last].isHit,
      );
    }
    out.removeWhere((s) => s.text.isEmpty);
    return out;
  }

  final String fieldReferenceName;
  final List<SearchSpan> spans;

  /// The fragment without the markup.
  String get plain => spans.map((s) => s.text).join();

  /// False for a field the service returned without a marked term.
  bool get hasHit => spans.any((s) => s.isHit);

  bool get isEmpty => spans.isEmpty;

  /// The fragment back as `<highlighthit>` markup. The text is escaped, so
  /// a `<` that came out of `&lt;` survives another parse unchanged and the
  /// cached copy equals the one that was stored.
  String toMarkup() => [
    for (final span in spans)
      span.isHit
          ? '<highlighthit>${PlainText.escape(span.text)}</highlighthit>'
          : PlainText.escape(span.text),
  ].join();

  Map<String, dynamic> toJson() => {
    'fieldReferenceName': fieldReferenceName,
    'highlights': [toMarkup()],
  };

  @override
  List<Object?> get props => [fieldReferenceName, spans];
}

/// One value of a facet with how many results carry it (`{name,
/// resultCount}` on the wire).
class SearchFacet extends Equatable {
  const SearchFacet({required this.name, required this.count});

  factory SearchFacet.fromJson(Map<String, dynamic> json) => SearchFacet(
    name: json['name'] as String? ?? '',
    count:
        (json['resultCount'] as num?)?.toInt() ??
        (json['count'] as num?)?.toInt() ??
        0,
  );

  final String name;
  final int count;

  Map<String, dynamic> toJson() => {'name': name, 'resultCount': count};

  @override
  List<Object?> get props => [name, count];
}

/// The four facets work item search answers with when `includeFacets` is on
/// (spike s44). Each list is ordered by count, biggest first, so the chips
/// the user is most likely to want come first; ties break on the name so the
/// order does not wobble between two reads of the same query.
class SearchFacets extends Equatable {
  const SearchFacets({
    this.projects = const [],
    this.types = const [],
    this.states = const [],
    this.assignees = const [],
  });

  static const empty = SearchFacets();

  /// The `facets` object of a search response. Code search names its project
  /// facet `Project`, work item search `System.TeamProject`; both land in
  /// [projects]. Keys are matched case-insensitively.
  factory SearchFacets.fromJson(Object? json) {
    if (json is! Map) return empty;
    final byKey = <String, List<SearchFacet>>{};
    for (final entry in json.entries) {
      final values = entry.value;
      if (values is! List) continue;
      byKey[entry.key.toString().toLowerCase()] =
          [
            for (final v in values)
              if (v is Map) SearchFacet.fromJson(v.cast<String, dynamic>()),
          ]..sort((a, b) {
            final byCount = b.count.compareTo(a.count);
            return byCount != 0 ? byCount : a.name.compareTo(b.name);
          });
    }
    List<SearchFacet> pick(List<String> keys) {
      for (final key in keys) {
        final found = byKey[key.toLowerCase()];
        if (found != null) return found;
      }
      return const [];
    }

    return SearchFacets(
      projects: pick(['System.TeamProject', 'Project']),
      types: pick(['System.WorkItemType']),
      states: pick(['System.State']),
      assignees: pick(['System.AssignedTo']),
    );
  }

  final List<SearchFacet> projects;
  final List<SearchFacet> types;
  final List<SearchFacet> states;
  final List<SearchFacet> assignees;

  bool get isEmpty =>
      projects.isEmpty && types.isEmpty && states.isEmpty && assignees.isEmpty;

  Map<String, dynamic> toJson() => {
    if (projects.isNotEmpty)
      'System.TeamProject': [for (final f in projects) f.toJson()],
    if (types.isNotEmpty)
      'System.WorkItemType': [for (final f in types) f.toJson()],
    if (states.isNotEmpty) 'System.State': [for (final f in states) f.toJson()],
    if (assignees.isNotEmpty)
      'System.AssignedTo': [for (final f in assignees) f.toJson()],
  };

  @override
  List<Object?> get props => [projects, types, states, assignees];
}

/// One page of results of any kind: what came back, how many there are in
/// total, the facets and the offset this page started at.
class SearchResults<T> extends Equatable {
  const SearchResults({
    this.items = const [],
    this.total = 0,
    this.facets = SearchFacets.empty,
    this.skip = 0,
    this.infoCode = 0,
  });

  factory SearchResults.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse, {
    int skip = 0,
  }) => SearchResults<T>(
    items: [
      for (final r in (json['results'] as List?) ?? const [])
        if (r is Map) parse(r.cast<String, dynamic>()),
    ],
    total: (json['count'] as num?)?.toInt() ?? 0,
    facets: SearchFacets.fromJson(json['facets']),
    skip: (json[r'$skip'] as num?)?.toInt() ?? skip,
    infoCode: (json['infoCode'] as num?)?.toInt() ?? 0,
  );

  final List<T> items;

  /// How many results the query has in total, not how many are in [items].
  final int total;
  final SearchFacets facets;

  /// The offset [items] starts at, so a See-all page knows what to ask for
  /// next.
  final int skip;

  /// The service's status: 0 is fine, anything else is a reason it could not
  /// run the query (`CodeSearchResults.problem` spells the code ones out).
  final int infoCode;

  bool get isEmpty => items.isEmpty;
  bool get hasMore => skip + items.length < total;

  Map<String, dynamic> toJson(Map<String, dynamic> Function(T) encode) => {
    'count': total,
    'results': [for (final item in items) encode(item)],
    if (!facets.isEmpty) 'facets': facets.toJson(),
    r'$skip': skip,
    'infoCode': infoCode,
  };

  @override
  List<Object?> get props => [items, total, facets, skip, infoCode];
}

/// One work item from `search/workitemsearchresults`.
///
/// The field map uses **lower-case** reference names (spike s44), unlike
/// every other work item read in the app, and `system.assignedto` is the
/// `Name <email>` string rather than an identity object.
class WorkItemSearchHit extends Equatable {
  const WorkItemSearchHit({
    required this.id,
    required this.workItemType,
    required this.title,
    required this.state,
    required this.projectName,
    required this.projectId,
    this.assignedTo,
    this.tags = const [],
    this.changedDate,
    this.highlights = const [],
  });

  factory WorkItemSearchHit.fromJson(Map<String, dynamic> json) {
    final fields = <String, Object?>{};
    final raw = json['fields'];
    if (raw is Map) {
      for (final e in raw.entries) {
        fields[e.key.toString().toLowerCase()] = e.value;
      }
    }
    String text(String name) => fields[name]?.toString() ?? '';
    final project = (json['project'] as Map?)?.cast<String, dynamic>();
    return WorkItemSearchHit(
      id: int.tryParse(text('system.id')) ?? 0,
      workItemType: text('system.workitemtype'),
      title: text('system.title'),
      state: text('system.state'),
      assignedTo: IdentityRef.fromField(fields['system.assignedto']),
      tags: [
        for (final t in text('system.tags').split(';'))
          if (t.trim().isNotEmpty) t.trim(),
      ],
      changedDate: DateTime.tryParse(text('system.changeddate')),
      projectName: project?['name'] as String? ?? text('system.teamproject'),
      projectId: project?['id'] as String? ?? '',
      highlights: SearchHighlight.fromHits(json['hits']),
    );
  }

  final int id;
  final String workItemType;
  final String title;
  final String state;
  final IdentityRef? assignedTo;
  final List<String> tags;
  final DateTime? changedDate;
  final String projectName;

  /// The project's GUID, so an All-projects hit opens in its own project
  /// without another lookup.
  final String projectId;
  final List<SearchHighlight> highlights;

  /// The one line the row shows under the title (decision D6).
  ///
  /// The title is already drawn above, so a match anywhere else says more;
  /// only when the term appears nowhere but the title does the title
  /// fragment win.
  SearchHighlight? get highlight {
    SearchHighlight? titleHit;
    for (final h in highlights) {
      if (!h.hasHit || h.isEmpty) continue;
      if (h.fieldReferenceName.toLowerCase() == 'system.title') {
        titleHit ??= h;
        continue;
      }
      return h;
    }
    return titleHit;
  }

  Map<String, dynamic> toJson() => {
    'fields': {
      'system.id': '$id',
      'system.workitemtype': workItemType,
      'system.title': title,
      'system.state': state,
      if (assignedTo != null) 'system.assignedto': _identityText(assignedTo!),
      if (tags.isNotEmpty) 'system.tags': tags.join('; '),
      if (changedDate != null)
        'system.changeddate': changedDate!.toIso8601String(),
    },
    'project': {'id': projectId, 'name': projectName},
    'hits': [for (final h in highlights) h.toJson()],
  };

  static String _identityText(IdentityRef person) =>
      person.uniqueName == null || person.uniqueName!.isEmpty
      ? person.displayName
      : '${person.displayName} <${person.uniqueName}>';

  @override
  List<Object?> get props => [id, projectId, title, state, highlights];
}

/// Which part of a pull request the query matched. The order is the order the
/// results are shown in: a title match is what the user meant far more often
/// than a branch or an author match.
enum PrMatchField { title, branch, author }

/// One active pull request the local matcher kept (decision D7: there is no
/// pull request search API, so the org's active list is matched on the
/// device).
class PullRequestSearchHit extends Equatable {
  const PullRequestSearchHit({required this.pullRequest, required this.match});

  factory PullRequestSearchHit.fromJson(Map<String, dynamic> json) =>
      PullRequestSearchHit(
        pullRequest: PullRequest.fromJson(
          (json['pullRequest'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        match: PrMatchField.values.firstWhere(
          (f) => f.name == json['match'],
          orElse: () => PrMatchField.title,
        ),
      );

  final PullRequest pullRequest;

  /// The field that matched, so the row can say why it is here.
  final PrMatchField match;

  Map<String, dynamic> toJson() => {
    'pullRequest': pullRequest.toJson(),
    'match': match.name,
  };

  @override
  List<Object?> get props => [pullRequest, match];
}
