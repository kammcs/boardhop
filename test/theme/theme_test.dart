import 'package:boardhop/core/notifications/notification_service.dart';
import 'package:boardhop/features/settings/settings_page.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoardhopTheme', () {
    test('light and dark both carry the domain palette', () {
      final light = BoardhopTheme.light();
      final dark = BoardhopTheme.dark();
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.extension<BoardhopColors>(), BoardhopColors.light);
      expect(dark.extension<BoardhopColors>(), BoardhopColors.dark);
      expect(light.useMaterial3, isTrue);
    });

    test('domain palette differs between modes', () {
      expect(BoardhopColors.light.bug, isNot(BoardhopColors.dark.bug));
      expect(
        BoardhopColors.light.codeBackground,
        isNot(BoardhopColors.dark.codeBackground),
      );
    });

    test('work item type and state lookups are case-insensitive', () {
      const c = BoardhopColors.light;
      expect(c.workItemType('Bug'), c.bug);
      expect(c.workItemType('product backlog item'), c.userStory);
      expect(c.workItemType('Something Custom'), c.stateProposed);
      expect(c.stateCategory('InProgress'), c.stateInProgress);
      expect(c.stateCategory('completed'), c.stateCompleted);
    });

    testWidgets('context.boardhopColors follows the active theme', (
      tester,
    ) async {
      late BoardhopColors seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          darkTheme: BoardhopTheme.dark(),
          themeMode: ThemeMode.dark,
          home: Builder(
            builder: (context) {
              seen = context.boardhopColors;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, BoardhopColors.dark);
    });
  });

  group('Breakpoint', () {
    test('maps widths to window size classes', () {
      expect(Breakpoint.fromWidth(400), Breakpoint.compact);
      expect(Breakpoint.fromWidth(599), Breakpoint.compact);
      expect(Breakpoint.fromWidth(600), Breakpoint.medium);
      expect(Breakpoint.fromWidth(839), Breakpoint.medium);
      expect(Breakpoint.fromWidth(840), Breakpoint.expanded);
    });
  });

  group('ThemeController', () {
    test('defaults to system and notifies on change', () async {
      final controller = ThemeController.inMemory();
      expect(controller.mode, ThemeMode.system);
      var notified = 0;
      controller.addListener(() => notified++);
      await controller.setMode(ThemeMode.dark);
      expect(controller.mode, ThemeMode.dark);
      expect(notified, 1);
      await controller.setMode(ThemeMode.dark);
      expect(notified, 1, reason: 'no notification when unchanged');
    });
  });

  group('SettingsPage', () {
    test(
      'rail side defaults to right, persists in memory and notifies',
      () async {
        final controller = ThemeController.inMemory();
        expect(controller.railSide, RailSide.right);
        var notified = 0;
        controller.addListener(() => notified++);
        await controller.setRailSide(RailSide.left);
        expect(controller.railSide, RailSide.left);
        expect(notified, 1);
        await controller.setRailSide(RailSide.left);
        expect(notified, 1, reason: 'no notification without a change');
      },
    );

    testWidgets('renders under ThemeScope and switches the mode', (
      tester,
    ) async {
      final controller = ThemeController.inMemory();
      await tester.pumpWidget(
        RepositoryProvider<NotificationService>.value(
          value: NotificationService.fake(),
          child: ThemeScope(
            controller: controller,
            child: Builder(
              builder: (context) => MaterialApp(
                theme: BoardhopTheme.light(),
                darkTheme: BoardhopTheme.dark(),
                themeMode: ThemeScope.of(context).mode,
                home: const SettingsPage(),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Appearance'), findsOneWidget);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(controller.mode, ThemeMode.dark);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
    });
  });
}
