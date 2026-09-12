import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/features/work_items/form/controls/identity_picker.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = IdentityRef(
  displayName: 'Kelly Kamm',
  uniqueName: 'kelly@kammcs.com',
  id: 'aaaa-1111',
);

/// The same person as the team list carries them: an identity id and the
/// unique name, no "(Me)".
const _meFromTeam = IdentityRef(
  displayName: 'Kelly Kamm',
  uniqueName: 'kelly@kammcs.com',
  id: 'aaaa-1111',
);

const _other = IdentityRef(
  displayName: 'Karen Teran',
  uniqueName: 'karen@example.com',
  id: 'bbbb-2222',
);

/// The Graph search answers with a descriptor and no id, which is why the
/// picker keys on the unique name.
const _meFromGraph = IdentityRef(
  displayName: 'Kelly Kamm',
  uniqueName: 'kelly@kammcs.com',
  descriptor: 'aad.NjgK',
);

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(400, 800),
  List<IdentityRef> hits = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final source = IdentitySource(
    me: _me,
    members: () async => const [_meFromTeam, _other],
    search: (_) async => hits,
    resolve: (person) async => person,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: BoardhopTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                pickIdentity(context, title: 'Assigned to', source: source),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('the people picker', () {
    testWidgets('lists the signed-in user once, as the pinned Me row', (
      tester,
    ) async {
      await _open(tester);

      expect(find.text('Kelly Kamm (Me)'), findsOneWidget);
      // The same person from the team list is dropped, not shown a second
      // time under their bare name (iOS walkthrough).
      expect(find.text('Kelly Kamm'), findsNothing);
      expect(find.text('Karen Teran'), findsOneWidget);
      expect(find.text('Unassigned'), findsOneWidget);
    });

    testWidgets('keeps them deduplicated while searching', (tester) async {
      await _open(tester, hits: const [_meFromGraph]);

      await tester.enterText(find.byType(TextField), 'kelly');
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      expect(find.text('Kelly Kamm (Me)'), findsOneWidget);
      expect(find.text('Kelly Kamm'), findsNothing);
      // The pinned row is the match, so the empty-list line stays away.
      expect(find.text('No team member matches.'), findsNothing);
      expect(find.text('Karen Teran'), findsNothing);
    });
  });
}
