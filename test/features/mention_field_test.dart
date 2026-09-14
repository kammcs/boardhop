import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/features/shared/mention/mention_controller.dart';
import 'package:boardhop/features/shared/mention/mention_field.dart';
import 'package:boardhop/features/shared/mention/mention_hint.dart';
import 'package:boardhop/features/shared/mention/mention_source.dart';
import 'package:boardhop/core/text/mention.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The widget half: when the list opens, what it shows, and every way it
/// closes. Fakes are closures, so there is no mock anywhere here.
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
  const radia = IdentityRef(
    displayName: 'Radia Perlman',
    uniqueName: 'radia@contoso.com',
    descriptor: 'aad.radia',
  );

  const task = ArtifactSuggestion(
    MentionKind.workItem,
    '15545',
    'Mentions: the composer picker',
    typeName: 'Task',
    state: 'Active',
  );
  const unknownType = ArtifactSuggestion(
    MentionKind.workItem,
    '15548',
    'An unknown type draws the neutral tile',
    typeName: 'Widget',
  );
  const pullRequest = ArtifactSuggestion(
    MentionKind.pullRequest,
    '8334',
    'Mentions in the discussion',
    state: 'Active',
  );

  late List<IdentityRef> picked;
  late List<String> searched;

  setUp(() {
    picked = [];
    searched = [];
  });

  MentionSource source({
    List<IdentityRef> participants = const [ada],
    List<IdentityRef> members = const [grace, kelly],
    List<IdentityRef> hits = const [radia],
    bool searchFails = false,
    bool resolveFails = false,
    IdentityRef? resolved,
    bool artifacts = true,
  }) => MentionSource(
    participants: () async => participants,
    participantReason: 'On this item',
    recents: () async => const [],
    members: () async => members,
    search: (query) async {
      searched.add(query);
      if (searchFails) {
        throw const AdoNetworkException('No connection to dev.azure.com.');
      }
      return hits;
    },
    resolve: (person) async {
      if (resolveFails) {
        throw const AdoNotFoundException('Not a member of this project.');
      }
      return resolved ??
          IdentityRef(
            displayName: person.displayName,
            uniqueName: person.uniqueName,
            id: 'id-resolved',
          );
    },
    workItems: artifacts ? (query) async => const [task, unknownType] : null,
    pullRequests: artifacts ? (query) async => const [pullRequest] : null,
    onPicked: picked.add,
  );

  /// A 400 dp phone by default; `width: 900` is the expanded breakpoint.
  Future<void> pump(
    WidgetTester tester,
    MentionController controller, {
    MentionSource? mentions,
    double width = 400,
    double height = 800,
    double textScale = 1,
    bool atBottom = false,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: Padding(
                // The field sits near the top, so the list opens downward and
                // the rows are on screen for a tap; `atBottom` puts it where a
                // real composer lives, which flips the list above it.
                padding: EdgeInsets.only(
                  top: atBottom ? 0 : 40,
                  bottom: atBottom ? 8 : 0,
                ),
                child: Align(
                  alignment: atBottom
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
                  child: MentionField(
                    controller: controller,
                    source: mentions,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment (Markdown)',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  }

  testWidgets('it is still a real TextField, so old finders keep working', (
    tester,
  ) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'plain comment');
    await tester.pump();
    expect(controller.text, 'plain comment');
    expect(find.byKey(const Key('mentionOptions')), findsNothing);
  });

  testWidgets('a bare @ opens the list, participants first', (tester) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source());
    await type(tester, '@');
    expect(find.byKey(const Key('mentionOptions')), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('On this item'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsOneWidget);
    // Nothing was searched: the bare trigger is cache only (M5).
    expect(searched, isEmpty);
  });

  testWidgets('nothing opens inside an e-mail address', (tester) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source());
    await type(tester, 'write to kelly@kammcs.com');
    expect(find.byKey(const Key('mentionOptions')), findsNothing);
  });

  testWidgets('the directory is searched from two characters, debounced', (
    tester,
  ) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source());
    // One character is below the minimum, so nothing is asked for at all.
    await tester.enterText(find.byType(TextField), '@r');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(searched, isEmpty);

    await tester.enterText(find.byType(TextField), '@ra');
    await tester.pump(const Duration(milliseconds: 100));
    expect(searched, isEmpty, reason: 'still inside the 300 ms debounce');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(searched, ['ra']);
    expect(find.text('Radia Perlman'), findsOneWidget);
  });

  testWidgets('tapping a row inserts the token and one space', (tester) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source());
    await type(tester, '@ada');
    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
    expect(controller.text, '@Ada Lovelace ');
    expect(controller.tokens.single.id, 'id-ada');
    expect(controller.toWire(MentionWire.markdown), '@<id-ada> ');
    expect(picked, [ada]);
    expect(find.byKey(const Key('mentionOptions')), findsNothing);
  });

  testWidgets('arrows move the highlight and Enter picks it', (tester) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source());
    await type(tester, '@');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // Row 0 is the participant, row 1 the first team member.
    expect(controller.text, '@Grace Hopper ');
    expect(controller.tokens.single.id, 'id-grace');
  });

  testWidgets('Escape closes the list and leaves the text alone', (
    tester,
  ) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source());
    await type(tester, '@ada');
    expect(find.byKey(const Key('mentionOptions')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mentionOptions')), findsNothing);
    expect(controller.text, '@ada');
    // It stays dismissed while the same trigger is being typed.
    await type(tester, '@adam');
    expect(find.byKey(const Key('mentionOptions')), findsNothing);
  });

  testWidgets('with the list closed the arrow keys still move the caret', (
    tester,
  ) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source());
    await tester.enterText(find.byType(TextField), 'first\nsecond');
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    expect(find.byKey(const Key('mentionOptions')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(controller.selection.baseOffset, 7, reason: 'moved down one line');
  });

  testWidgets('deleting the trigger closes the list', (tester) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source());
    await type(tester, '@ada');
    expect(find.byKey(const Key('mentionOptions')), findsOneWidget);
    await type(tester, 'ada');
    expect(find.byKey(const Key('mentionOptions')), findsNothing);
  });

  testWidgets('a query nobody matches says so, quietly', (tester) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source(hits: const []));
    await type(tester, '@zzz');
    expect(find.text('No one matches'), findsOneWidget);
  });

  testWidgets('offline keeps the cached bands and shows one quiet line', (
    tester,
  ) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source(searchFails: true));
    await type(tester, '@gr');
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('No connection to dev.azure.com.'), findsOneWidget);
  });

  testWidgets('a directory hit is resolved when picked (M15)', (tester) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source());
    await type(tester, '@ra');
    await tester.tap(find.text('Radia Perlman'));
    await tester.pumpAndSettle();
    expect(controller.tokens.single.id, 'id-resolved');
    expect(picked.single.id, 'id-resolved');
  });

  testWidgets('a hit that cannot be resolved says why and is not inserted', (
    tester,
  ) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source(resolveFails: true));
    await type(tester, '@ra');
    await tester.tap(find.text('Radia Perlman'));
    await tester.pumpAndSettle();
    expect(find.text('Not a member of this project.'), findsOneWidget);
    expect(controller.tokens, isEmpty);
    expect(controller.text, '@ra');
    expect(picked, isEmpty);
  });

  testWidgets('# lists work items and inserts the plain id', (tester) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source());
    await type(tester, 'see #155');
    expect(find.text('Task #15545 · Active'), findsOneWidget);
    // An unknown type still draws a tile rather than throwing.
    expect(find.text('Widget #15548'), findsOneWidget);
    await tester.tap(find.text('Mentions: the composer picker'));
    await tester.pumpAndSettle();
    expect(controller.text, 'see #15545 ');
    expect(controller.toWire(MentionWire.markdown), 'see #15545 ');
  });

  testWidgets('! lists pull requests', (tester) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source());
    await type(tester, 'see !83');
    expect(find.text('Pull request !8334 · Active'), findsOneWidget);
    await tester.tap(find.text('Mentions in the discussion'));
    await tester.pumpAndSettle();
    expect(controller.text, 'see !8334 ');
  });

  testWidgets('a host with no artifact closures never opens on # or !', (
    tester,
  ) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source(artifacts: false));
    await type(tester, 'see #155');
    expect(find.byKey(const Key('mentionOptions')), findsNothing);
  });

  testWidgets(
    'the panel is capped at 480 on a tablet, field width on a phone',
    (tester) async {
      final phone = MentionController();
      addTearDown(phone.dispose);
      await pump(tester, phone, mentions: source(), width: 400);
      await type(tester, '@');
      final phoneWidth = tester
          .getSize(find.byKey(const Key('mentionOptions')))
          .width;
      expect(phoneWidth, closeTo(400, 1));

      final tablet = MentionController();
      addTearDown(tablet.dispose);
      await pump(tester, tablet, mentions: source(), width: 900, height: 1200);
      await type(tester, '@');
      final tabletWidth = tester
          .getSize(find.byKey(const Key('mentionOptions')))
          .width;
      expect(tabletWidth, lessThanOrEqualTo(480));
    },
  );

  testWidgets('no overflow at 1.0, 1.6 and 3.1 text on both breakpoints', (
    tester,
  ) async {
    for (final width in [400.0, 900.0]) {
      for (final scale in [1.0, 1.6, 3.1]) {
        final controller = MentionController();
        await pump(
          tester,
          controller,
          mentions: source(),
          width: width,
          height: 1200,
          textScale: scale,
        );
        await type(tester, '@a');
        expect(
          find.byKey(const Key('mentionOptions')),
          findsOneWidget,
          reason: 'width $width, scale $scale',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'width $width, scale $scale',
        );
        controller.dispose();
      }
    }
  });

  testWidgets('losing focus closes the list', (tester) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source());
    await type(tester, '@');
    expect(find.byKey(const Key('mentionOptions')), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mentionOptions')), findsNothing);
  });

  testWidgets('a composer at the bottom opens its list above the field', (
    tester,
  ) async {
    final controller = MentionController();
    addTearDown(controller.dispose);
    await pump(tester, controller, mentions: source(), atBottom: true);
    await type(tester, '@');
    final field = tester.getRect(find.byType(TextField));
    final options = tester.getRect(find.byKey(const Key('mentionOptions')));
    expect(
      options.bottom,
      lessThanOrEqualTo(field.top),
      reason: 'mostSpace: there is more room above a bottom-anchored composer',
    );
  });

  group('MentionHint', () {
    Future<void> pumpHint(
      WidgetTester tester,
      MentionController controller,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(body: MentionHint(controller: controller)),
        ),
      );
    }

    testWidgets('says nothing while every @word is a picked mention', (
      tester,
    ) async {
      final controller = MentionController(text: 'nothing to see');
      addTearDown(controller.dispose);
      await pumpHint(tester, controller);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('names the hand-typed word, and clears when it is picked', (
      tester,
    ) async {
      final controller = MentionController();
      addTearDown(controller.dispose);
      await pumpHint(tester, controller);

      controller.value = const TextEditingValue(
        text: 'hi @kelly',
        selection: TextSelection.collapsed(offset: 9),
      );
      await tester.pump();
      expect(
        find.text(
          '@kelly is not a mention. Pick from the list to notify someone.',
        ),
        findsOneWidget,
      );

      controller.insertToken(
        MentionKind.person,
        'id-kelly',
        '@Kelly Kamm',
        replacing: const TextRange(start: 3, end: 9),
      );
      await tester.pump();
      expect(find.byType(Text), findsNothing);
    });
  });
}
