import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/db/json_cache.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/people_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const account = 'kelly@kammcs.com-home';
const org = 'contoso';
const projectId = 'p-1111';
const teamId = 't-2222';

/// Synthetic identities only.
const adaId = '2f1b1a70-6d24-4c0a-9f0b-6b6d2f9a1c33';
const bayId = '8c4d5e6f-1122-4333-8444-55556666aaaa';

/// Canned-response adapter: the repository is exercised through the real
/// `AdoClient`, so the URL and the body it builds are what the tests read.
class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, Object> answers = <String, Object>{};
  final Map<String, int> statuses = <String, int>{};
  int status = 200;

  RequestOptions get last => requests.last;
  Map<String, dynamic> get lastBody =>
      (last.data as Map).cast<String, dynamic>();
  int get calls => requests.length;
  Iterable<Uri> get uris => requests.map((r) => r.uri);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final key = answers.keys.firstWhere(
      (k) => options.uri.path.contains(k),
      orElse: () => '',
    );
    return ResponseBody.fromString(
      jsonEncode(answers[key] ?? const <String, dynamic>{}),
      statuses[key] ?? status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _members() => {
  'count': 2,
  'value': [
    {
      'identity': {
        'displayName': 'Ada Example',
        'uniqueName': 'ada@example.test',
        'id': adaId,
      },
    },
    {
      'identity': {
        'displayName': 'Bay Wilkins',
        'uniqueName': 'bay@example.test',
        'id': bayId,
      },
    },
  ],
};

Map<String, dynamic> _graphUsers() => {
  'value': [
    {
      'displayName': 'Ada Example',
      'mailAddress': 'ada@example.test',
      'principalName': 'ada@example.test',
      'descriptor': 'aad.QWRh',
      '_links': {
        'avatar': {
          'href':
              'https://dev.azure.com/contoso/_apis/GraphProfile/'
              'MemberAvatars/aad.QWRh',
        },
      },
    },
  ],
};

Map<String, dynamic> _identities(List<String> ids) => {
  'count': ids.length,
  'value': [
    for (final id in ids)
      {
        'id': id,
        'providerDisplayName': id == adaId ? 'Ada Example' : 'Bay Wilkins',
        'subjectDescriptor': id == adaId ? 'aad.QWRh' : 'aad.QmF5',
        'properties': {
          'Mail': {
            r'$type': 'System.String',
            r'$value': id == adaId ? 'ada@example.test' : 'bay@example.test',
          },
        },
      },
  ],
};

void main() {
  late _FakeAdapter adapter;
  late AppDatabase db;
  late PeopleRepository people;

  PeopleRepository build() => PeopleRepository(
    AdoClient(
      tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
      dio: Dio()..httpClientAdapter = adapter,
    ),
    db,
    account,
  );

  setUp(() {
    adapter = _FakeAdapter()
      ..answers['members'] = _members()
      ..answers['graph/descriptors'] = {'value': 'scp.UHJvag'}
      ..answers['subjectquery'] = _graphUsers()
      ..answers['storagekeys'] = {'value': adaId}
      ..answers['identities'] = _identities([adaId]);
    db = AppDatabase(NativeDatabase.memory());
    people = build();
  });

  tearDown(() => db.close());

  group('the calls moved out of the form repository', () {
    test('teamMembers reads the team and caches under the old key', () async {
      final members = await people.teamMembers(org, projectId, teamId);

      expect(
        adapter.last.uri.toString(),
        'https://dev.azure.com/contoso/_apis/projects/p-1111/teams/t-2222/'
        'members?api-version=7.1',
      );
      expect(members.map((m) => m.displayName), ['Ada Example', 'Bay Wilkins']);
      expect(
        PeopleRepository.membersKey(org, projectId, teamId),
        'form:members:contoso:p-1111:t-2222',
      );
      // The cached copy answers the second call.
      await build().teamMembers(org, projectId, teamId);
      expect(adapter.calls, 1);
      expect(
        await JsonCache(
          db,
          namespace: account,
        ).get(PeopleRepository.membersKey(org, projectId, teamId)),
        isNotNull,
      );
    });

    test('projectDescriptor asks vssps for the project id', () async {
      expect(await people.projectDescriptor(org, projectId), 'scp.UHJvag');
      expect(
        adapter.last.uri.toString(),
        'https://vssps.dev.azure.com/contoso/_apis/graph/descriptors/p-1111'
        '?api-version=7.1-preview.1',
      );
      expect(
        PeopleRepository.descriptorKey(org, projectId),
        'form:descriptor:contoso:p-1111',
      );
    });

    test('searchPeople posts a project-scoped subject query', () async {
      final hits = await people.searchPeople(org, projectId, ' ada ');

      expect(
        adapter.last.uri.toString(),
        'https://vssps.dev.azure.com/contoso/_apis/graph/subjectquery'
        '?api-version=7.1-preview.1',
      );
      expect(adapter.last.method, 'POST');
      expect(adapter.lastBody, {
        'query': 'ada',
        'subjectKind': ['User'],
        'scopeDescriptor': 'scp.UHJvag',
      });
      // A Graph user has no identity id, only a descriptor (spike s25).
      expect(hits.single.id, isNull);
      expect(hits.single.descriptor, 'aad.QWRh');
      expect(hits.single.uniqueName, 'ada@example.test');
    });

    test('an empty query is answered without a call', () async {
      expect(await people.searchPeople(org, projectId, '   '), isEmpty);
      expect(adapter.calls, 0);
    });

    test('resolveIdentityId turns a descriptor into the GUID', () async {
      const hit = IdentityRef(
        displayName: 'Ada Example',
        uniqueName: 'ada@example.test',
        descriptor: 'aad.QWRh',
      );
      final resolved = await people.resolveIdentityId(org, hit);

      expect(
        adapter.last.uri.toString(),
        'https://vssps.dev.azure.com/contoso/_apis/graph/storagekeys/aad.QWRh'
        '?api-version=7.1-preview.1',
      );
      expect(resolved.id, adaId);
      expect(resolved.displayName, 'Ada Example');
      expect(resolved.descriptor, 'aad.QWRh');
      // Resolving seeds the identity cache, so the name is free afterwards.
      expect(
        (await people.identityById(org, adaId))?.displayName,
        'Ada Example',
      );
      expect(adapter.uris.where((u) => u.path.endsWith('identities')), isEmpty);
    });

    test('a person who already has an id is not looked up', () async {
      const known = IdentityRef(displayName: 'Ada Example', id: adaId);
      expect(await people.resolveIdentityId(org, known), known);
      expect(adapter.calls, 0);
    });

    test('identityFromGraphUser keeps its old behaviour', () {
      final person = PeopleRepository.identityFromGraphUser(
        _graphUsers()['value'].first as Map<String, dynamic>,
      );
      expect(person.id, isNull);
      expect(person.descriptor, 'aad.QWRh');
      expect(person.avatarSource()?.isGraph, isTrue);
    });
  });

  group('identityById', () {
    test('reads vssps identities and caches the answer', () async {
      final ada = await people.identityById(org, adaId);

      expect(
        adapter.last.uri.toString(),
        'https://vssps.dev.azure.com/contoso/_apis/identities'
        '?identityIds=$adaId&api-version=7.1-preview.1',
      );
      expect(ada?.displayName, 'Ada Example');
      expect(ada?.uniqueName, 'ada@example.test');
      expect(ada?.id, adaId);
      expect(ada?.descriptor, 'aad.QWRh');

      // Memory answers the second ask, and the disk cache a fresh repository.
      await people.identityById(org, adaId);
      expect(adapter.calls, 1);
      expect(
        (await build().identityById(org, adaId))?.displayName,
        'Ada Example',
      );
      expect(adapter.calls, 1);
    });

    test('an upper-case GUID is the same person', () async {
      await people.identityById(org, adaId);
      expect((await people.identityById(org, adaId.toUpperCase()))?.id, adaId);
      expect(adapter.calls, 1);
    });

    test('concurrent asks for one GUID make one call', () async {
      final both = await Future.wait([
        people.identityById(org, adaId),
        people.identityById(org, adaId),
      ]);
      expect(both.map((p) => p?.displayName), ['Ada Example', 'Ada Example']);
      expect(adapter.calls, 1);
    });

    test('a GUID nobody answers for is null, and is not asked twice', () async {
      adapter.answers['identities'] = {'count': 0, 'value': []};
      expect(await people.identityById(org, bayId), isNull);
      expect(await people.identityById(org, bayId), isNull);
      expect(adapter.calls, 1);
    });

    test('a failed read is remembered for the session', () async {
      adapter.statuses['identities'] = 403;
      expect(await people.identityById(org, bayId), isNull);
      expect(await people.identityById(org, bayId), isNull);
      expect(adapter.calls, 1);
      // …until the memory is dropped.
      people.clearIdentityMemory();
      expect(await people.identityById(org, bayId), isNull);
      expect(adapter.calls, 2);
    });

    test('sign-in and offline failures are not remembered', () async {
      adapter.statuses['identities'] = 401;
      expect(await people.identityById(org, bayId), isNull);
      adapter.statuses.remove('identities');
      adapter.answers['identities'] = _identities([bayId]);
      expect(
        (await people.identityById(org, bayId))?.displayName,
        'Bay Wilkins',
      );
    });

    test('an empty GUID never reaches the network', () async {
      expect(await people.identityById(org, '  '), isNull);
      expect(adapter.calls, 0);
    });

    test('identitiesByIds batches the unknown ones only', () async {
      adapter.answers['identities'] = _identities([adaId, bayId]);
      await people.rememberIdentity(
        org,
        const IdentityRef(displayName: 'Ada Example', id: adaId),
      );

      final found = await people.identitiesByIds(org, [
        adaId,
        bayId,
        adaId.toUpperCase(),
        '',
      ]);

      expect(found.keys, {adaId, bayId});
      expect(adapter.calls, 1);
      expect(adapter.last.uri.queryParameters['identityIds'], bayId);
    });
  });

  group('rememberIdentity', () {
    test('seeds the cache so a later name costs nothing', () async {
      await people.rememberIdentity(
        org,
        const IdentityRef(
          displayName: 'Bay Wilkins',
          uniqueName: 'bay@example.test',
          id: bayId,
        ),
      );
      expect(
        (await people.identityById(org, bayId))?.displayName,
        'Bay Wilkins',
      );
      expect(adapter.calls, 0);
      // And it survives into a new repository through the JSON cache.
      expect(
        (await build().identityById(org, bayId))?.uniqueName,
        'bay@example.test',
      );
      expect(adapter.calls, 0);
    });

    test('a ref with no id or no name is ignored', () async {
      await people.rememberIdentity(
        org,
        const IdentityRef(displayName: 'Nameless'),
      );
      await people.rememberIdentity(
        org,
        const IdentityRef(displayName: '', id: bayId),
      );
      await people.rememberIdentity(org, null);
      adapter.answers['identities'] = {'count': 0, 'value': []};
      expect(await people.identityById(org, bayId), isNull);
      expect(adapter.calls, 1);
    });

    test('team members seed the memory for free', () async {
      await people.teamMembers(org, projectId, teamId);
      expect(
        (await people.identityById(org, bayId))?.displayName,
        'Bay Wilkins',
      );
      expect(adapter.calls, 1);
    });
  });

  test('identityFromIdentity reads the Identities API shape', () {
    final row = PeopleRepository.identityFromIdentity({
      'id': adaId,
      'providerDisplayName': 'Ada Example',
      'customDisplayName': 'Ada E.',
      'subjectDescriptor': 'aad.QWRh',
      'properties': {
        'Account': {r'$value': 'ada@example.test'},
      },
    });
    // The custom name is what Azure DevOps shows when a person set one.
    expect(row.displayName, 'Ada E.');
    expect(row.uniqueName, 'ada@example.test');
    expect(row.id, adaId);
    expect(row.descriptor, 'aad.QWRh');
  });
}
