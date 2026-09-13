import 'package:boardhop/data/models/push_prefs.dart';
import 'package:boardhop/data/repositories/push_prefs_repository.dart';
import 'package:boardhop/features/notifications/push_registrar.dart';
import 'package:boardhop/features/settings/push_prefs_section.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const org = 'contoso';

/// Serves one document and records what was written.
class FakeRelay {
  FakeRelay({PushPrefs? stored}) : document = stored ?? PushPrefs.fromDefaults();

  PushPrefs document;
  final List<Map<String, Object?>> writes = [];

  /// When set, every PUT answers with this status instead of 200.
  int? refuseWith;

  /// Answered by GET when set (404 is "this relay has no /v1/prefs").
  int? getStatus;

  RelayCall get call =>
      (method, url, {String? bearer, Map<String, Object?>? body}) async {
        if (method == 'GET') {
          final status = getStatus;
          if (status != null) return RelayResponse(status);
          return RelayResponse(200, document.toJson());
        }
        writes.add(body ?? const {});
        final refused = refuseWith;
        if (refused != null) return RelayResponse(refused);
        document = PushPrefs.fromJson(body ?? const {});
        return RelayResponse(200, document.toJson());
      };
}

PushPrefsRepository repositoryFor(FakeRelay relay) => PushPrefsRepository(
  accountId: 'account-1',
  accessToken: () async => 'ado-access-token',
  call: relay.call,
  relayUrl: (_) => 'https://relay.test',
);

Widget harness(FakeRelay relay, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light
          ? BoardhopTheme.light()
          : BoardhopTheme.dark(),
      home: Scaffold(
        body: ListView(
          children: [
            PushPrefsSection(org: org, repository: repositoryFor(relay)),
          ],
        ),
      ),
    );

Future<void> setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows a row for every preference of research/14 §6', (
    tester,
  ) async {
    await setSize(tester, const Size(400, 2400));
    final relay = FakeRelay();
    await tester.pumpWidget(harness(relay));
    await tester.pumpAndSettle();

    expect(find.text('Push · contoso'), findsOneWidget);
    for (final title in [
      'Push notifications',
      'Assigned to me',
      'State changes',
      'Any change to mine',
      'Review requested',
      'Votes on mine',
      'Completed or abandoned',
      'New pushes',
      'Builds',
      'Approvals waiting for me',
      'Quiet hours',
      'Nothing muted',
      'You are never notified about your own changes',
    ]) {
      expect(find.text(title), findsWidgets, reason: title);
    }
    // The closed vocabularies, as chips.
    expect(find.widgetWithText(ChoiceChip, 'Mentions only'), findsWidgets);
    expect(find.widgetWithText(ChoiceChip, 'My threads only'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Failures and fixes'), findsOneWidget);

    // notActor is reported, never editable.
    final fixed = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('You are never notified about your own changes'),
        matching: find.byType(ListTile),
      ),
    );
    expect(fixed.enabled, isFalse);
    expect(fixed.onTap, isNull);
  });

  testWidgets('a switch writes at once and keeps the new value', (
    tester,
  ) async {
    await setSize(tester, const Size(400, 2400));
    final relay = FakeRelay();
    await tester.pumpWidget(harness(relay));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Assigned to me'));
    await tester.pumpAndSettle();

    expect(relay.writes.single['workItems'], containsPair('assigned', false));
    expect(relay.writes.single.containsKey('notActor'), isFalse);
    final row = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Assigned to me'),
    );
    expect(row.value, isFalse);
  });

  testWidgets('a chip writes the enum the relay expects', (tester) async {
    await setSize(tester, const Size(400, 2400));
    final relay = FakeRelay();
    await tester.pumpWidget(harness(relay));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'My threads only'));
    await tester.pumpAndSettle();

    expect(
      relay.writes.single['pullRequests'],
      containsPair('comments', 'myThreadsOnly'),
    );
  });

  testWidgets('a refused write puts the row back and says so', (tester) async {
    await setSize(tester, const Size(400, 2400));
    final relay = FakeRelay()..refuseWith = 500;
    await tester.pumpWidget(harness(relay));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Approvals waiting for me'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Could not save the change for contoso.'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
    final row = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Approvals waiting for me'),
    );
    expect(row.value, isTrue);
  });

  testWidgets('the master switch disables the rest without hiding it', (
    tester,
  ) async {
    await setSize(tester, const Size(400, 2400));
    final relay = FakeRelay(
      stored: PushPrefs.fromDefaults().copyWith(enabled: false),
    );
    await tester.pumpWidget(harness(relay));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Assigned to me'),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Push notifications'),
          )
          .onChanged,
      isNotNull,
    );
  });

  testWidgets('quiet hours reveal their window, and a mute can be removed', (
    tester,
  ) async {
    await setSize(tester, const Size(400, 2600));
    final relay = FakeRelay(
      stored: PushPrefs.fromDefaults().copyWith(
        quietHours: const QuietHours(enabled: true, start: '23:00'),
        mutedArtifacts: [const MutedArtifact(type: 'pr', id: '8336')],
      ),
    );
    await tester.pumpWidget(harness(relay));
    await tester.pumpAndSettle();

    expect(find.text('From'), findsOneWidget);
    expect(find.text('23:00'), findsOneWidget);
    expect(find.text('Except approvals'), findsOneWidget);

    expect(find.text('!8336'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pumpAndSettle();
    expect(relay.writes.single['mutedArtifacts'], isEmpty);
    expect(find.text('Nothing muted'), findsOneWidget);
  });

  testWidgets('a relay without /v1/prefs says so instead of showing defaults', (
    tester,
  ) async {
    await setSize(tester, const Size(400, 900));
    final relay = FakeRelay()..getStatus = 404;
    await tester.pumpWidget(harness(relay));
    await tester.pumpAndSettle();

    expect(find.text('Preferences unavailable'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('renders at expanded width and in dark, with no overflow', (
    tester,
  ) async {
    await setSize(tester, const Size(1280, 2400));
    final relay = FakeRelay();
    await tester.pumpWidget(harness(relay, brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(find.text('Push · contoso'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Assigned to me'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
