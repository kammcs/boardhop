import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/features/shared/mention/mention_source.dart';
import 'package:boardhop/core/text/mention.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pure half of the picker: which band a person comes from decides where
/// they sit, and a stranger never floats above a participant (research/16 M2,
/// M14, M15).
void main() {
  const ada = IdentityRef(
    displayName: 'Ada Lovelace',
    uniqueName: 'ada@example.com',
    id: 'id-ada',
  );
  const grace = IdentityRef(
    displayName: 'Grace Hopper',
    uniqueName: 'grace@example.com',
    id: 'id-grace',
  );
  const kelly = IdentityRef(
    displayName: 'Kelly Kamm',
    uniqueName: 'kelly@example.com',
    id: 'id-kelly',
  );
  const katherine = IdentityRef(
    displayName: 'Katherine Johnson',
    uniqueName: 'katherine@example.com',
    id: 'id-katherine',
  );

  /// How `graph/subjectquery` answers: a descriptor and no identity id.
  const radia = IdentityRef(
    displayName: 'Radia Perlman',
    uniqueName: 'radia@contoso.com',
    descriptor: 'aad.radia',
  );

  List<String> namesOf(List<PersonSuggestion> list) => [
    for (final s in list) s.person.displayName,
  ];

  group('order and dedup', () {
    test('participants, then recents, then members, then directory hits', () {
      final list = MentionSuggestions.people(
        query: '',
        participants: const [ada],
        recents: const [grace],
        members: const [kelly, katherine],
        hits: const [radia],
      );
      expect(namesOf(list), [
        'Ada Lovelace',
        'Grace Hopper',
        'Kelly Kamm',
        'Katherine Johnson',
        'Radia Perlman',
      ]);
    });

    test('the same person in two bands is listed once, in the higher one', () {
      final list = MentionSuggestions.people(
        query: '',
        participants: const [ada],
        recents: const [ada],
        members: const [ada, grace],
      );
      expect(namesOf(list), ['Ada Lovelace', 'Grace Hopper']);
    });

    test('dedup keys on the unique name, as the assignee sheet does', () {
      // A team member carries an id; the same person from the Graph search
      // carries only a descriptor. Keying on the id would list them twice.
      const fromGraph = IdentityRef(
        displayName: 'Ada Lovelace',
        uniqueName: 'ada@example.com',
        descriptor: 'aad.ada',
      );
      final list = MentionSuggestions.people(
        query: '',
        members: const [ada],
        hits: const [fromGraph],
      );
      expect(list, hasLength(1));
      expect(list.single.resolved, isTrue);
    });

    test('me is offered last, and never twice', () {
      final withoutBand = MentionSuggestions.people(
        query: '',
        members: const [ada],
        me: kelly,
      );
      expect(namesOf(withoutBand), ['Ada Lovelace', 'Kelly Kamm']);

      final alreadyThere = MentionSuggestions.people(
        query: '',
        members: const [ada, kelly],
        me: kelly,
      );
      expect(namesOf(alreadyThere), ['Ada Lovelace', 'Kelly Kamm']);
    });

    test('the participants band carries the reason the host worded', () {
      final list = MentionSuggestions.people(
        query: '',
        participants: const [ada],
        participantReason: 'On this item',
        members: const [grace],
      );
      expect(list.first.reason, 'On this item');
      expect(list.first.secondary, 'On this item');
      expect(list.last.secondary, isNull);
    });
  });

  group('matching (M14)', () {
    test('case-insensitive contains on the name or the e-mail', () {
      expect(MentionSuggestions.matches(ada, 'ADA'), isTrue);
      expect(MentionSuggestions.matches(ada, 'love'), isTrue);
      expect(MentionSuggestions.matches(ada, 'example.com'), isTrue);
      expect(MentionSuggestions.matches(ada, 'turing'), isFalse);
    });

    test(
      'every word of the query has to appear: "kel ka" finds Kelly Kamm',
      () {
        expect(MentionSuggestions.matches(kelly, 'kel ka'), isTrue);
        expect(MentionSuggestions.matches(kelly, 'kel zz'), isFalse);
        expect(MentionSuggestions.matches(katherine, 'kel ka'), isFalse);
      },
    );

    test('an empty query matches everyone, so a bare @ lists the bands', () {
      expect(MentionSuggestions.matches(ada, ''), isTrue);
      expect(MentionSuggestions.matches(ada, '   '), isTrue);
    });

    test('the list is filtered by the query', () {
      final list = MentionSuggestions.people(
        query: 'ka',
        members: const [ada, grace, kelly, katherine],
      );
      expect(namesOf(list), ['Kelly Kamm', 'Katherine Johnson']);
    });
  });

  group('match ranges', () {
    test('one range per hit, in order', () {
      final ranges = MentionSuggestions.matchRanges('Kelly Kamm', 'kel');
      expect(ranges, [const TextRange(start: 0, end: 3)]);
    });

    test('two query words give two ranges', () {
      final ranges = MentionSuggestions.matchRanges('Kelly Kamm', 'kel ka');
      expect(ranges, [
        const TextRange(start: 0, end: 3),
        const TextRange(start: 6, end: 8),
      ]);
    });

    test('overlapping hits are merged', () {
      final ranges = MentionSuggestions.matchRanges('Kelly Kamm', 'kel ell');
      expect(ranges, [const TextRange(start: 0, end: 4)]);
    });

    test('a word that is not there contributes nothing', () {
      expect(MentionSuggestions.matchRanges('Kelly Kamm', 'zz'), isEmpty);
      expect(MentionSuggestions.matchRanges('Kelly Kamm', ''), isEmpty);
    });

    test('the suggestion carries the ranges for its display name', () {
      final list = MentionSuggestions.people(
        query: 'ka',
        members: const [kelly],
      );
      expect(list.single.matches, [const TextRange(start: 6, end: 8)]);
    });
  });

  group('collisions and resolution', () {
    test('two rows reading alike fall back to the e-mail', () {
      const one = IdentityRef(
        displayName: 'Ada Lovelace',
        uniqueName: 'ada@example.com',
        id: 'id-one',
      );
      const two = IdentityRef(
        displayName: 'Ada Lovelace',
        uniqueName: 'ada.l@contoso.com',
        id: 'id-two',
      );
      final list = MentionSuggestions.people(
        query: '',
        members: const [one, two],
      );
      expect(list.map((s) => s.secondary), [
        'ada@example.com',
        'ada.l@contoso.com',
      ]);
    });

    test('a single name needs no second line', () {
      final list = MentionSuggestions.people(query: '', members: const [ada]);
      expect(list.single.secondary, isNull);
    });

    test('a directory hit is unresolved until it is picked (M15)', () {
      final list = MentionSuggestions.people(query: '', hits: const [radia]);
      expect(list.single.resolved, isFalse);
    });

    test('everyone who carries a GUID is resolved and can go offline', () {
      final list = MentionSuggestions.people(
        query: '',
        participants: const [ada],
        members: const [grace],
      );
      expect(list.every((s) => s.resolved), isTrue);
    });

    test('an empty identity is dropped rather than drawn blank', () {
      final list = MentionSuggestions.people(
        query: '',
        members: const [
          IdentityRef(displayName: ''),
          ada,
        ],
      );
      expect(namesOf(list), ['Ada Lovelace']);
    });
  });

  group('artifacts', () {
    const task = ArtifactSuggestion(
      MentionKind.workItem,
      '15545',
      'Mentions: the composer picker',
      typeName: 'Task',
      state: 'Active',
    );
    const pr = ArtifactSuggestion(
      MentionKind.pullRequest,
      '8334',
      'Mentions in the discussion',
      state: 'Active',
    );

    test('the inserted label is the plain reference the service links', () {
      expect(task.label, '#15545');
      expect(pr.label, '!8334');
    });

    test('the same id is listed once, keeping the cached row', () {
      const fromSearch = ArtifactSuggestion(
        MentionKind.workItem,
        '15545',
        'Mentions: the composer picker',
        typeName: 'Task',
      );
      final list = MentionSuggestions.artifacts(const [task, fromSearch]);
      expect(list, hasLength(1));
      expect(list.single.state, 'Active');
    });

    test('a work item and a pull request with the same number both stay', () {
      const sameNumber = ArtifactSuggestion(
        MentionKind.pullRequest,
        '15545',
        'Something else',
      );
      final list = MentionSuggestions.artifacts(const [task, sameNumber]);
      expect(list, hasLength(2));
    });

    test('the title carries the matched letters', () {
      final list = MentionSuggestions.artifacts(const [
        task,
      ], query: 'composer');
      expect(list.single.matches, [const TextRange(start: 14, end: 22)]);
    });
  });
}
