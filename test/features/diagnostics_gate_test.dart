import 'package:boardhop/app.dart';
import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/config/app_config.dart';
import 'package:boardhop/features/diagnostics/diagnostics_page.dart';
import 'package:boardhop/features/orgs/org_picker_page.dart';
import 'package:boardhop/router.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _AuthService extends Mock implements AuthService {}

class _Deps extends Mock implements AppDependencies {}

/// The Diagnostics page is for local testing only (Kelly, 2026-09-14): store
/// builds carry neither the bug icon nor the routes behind it.
void main() {
  Widget picker({required bool showDiagnostics}) => BlocProvider(
    create: (_) => AuthBloc(_AuthService()),
    child: MaterialApp(home: OrgPickerPage(showDiagnostics: showDiagnostics)),
  );

  testWidgets('a local build shows the bug icon', (tester) async {
    await tester.pumpWidget(picker(showDiagnostics: true));
    expect(find.byIcon(Icons.bug_report_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('a store build has no bug icon', (tester) async {
    await tester.pumpWidget(picker(showDiagnostics: false));
    expect(find.byIcon(Icons.bug_report_outlined), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  test('tests run in debug, where diagnostics are on and routed', () {
    expect(AppConfig.diagnosticsEnabled, isTrue);
    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    final router = buildRouter(auth, _Deps());
    addTearDown(router.dispose);
    for (final path in [
      '/diagnostics',
      '/diagnostics/diff',
      '/diagnostics/wiki',
    ]) {
      expect(
        router.configuration.findMatch(Uri.parse(path)).isError,
        isFalse,
        reason: path,
      );
    }
  });

  /// The Diagnostics index's app bar overflowed by 52 pt on the iPhone
  /// Duo's cover — 379.7 pt of bar for a back arrow, eight probe icons and
  /// Copy report (research/23 §9.13). On a compact width the probes fold
  /// into one menu; the Display probe, the one a pose check needs, stays an
  /// icon at every width.
  Widget diagnostics() =>
      MaterialApp(theme: BoardhopTheme.light(), home: const DiagnosticsPage());

  testWidgets('a compact app bar folds the probes into a menu', (tester) async {
    tester.view.physicalSize = const Size(1398, 2034);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(right: 252);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(diagnostics());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.science_outlined), findsOneWidget);
    expect(find.byIcon(Icons.phonelink_outlined), findsOneWidget);
    expect(find.byIcon(Icons.view_kanban_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.science_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Board probe (F4)'), findsOneWidget);
    expect(find.text('Wiki probe (W-B)'), findsOneWidget);
  });

  testWidgets('a wide app bar keeps every probe an icon', (tester) async {
    tester.view.physicalSize = const Size(2853, 2007);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(diagnostics());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.science_outlined), findsNothing);
    expect(find.byIcon(Icons.view_kanban_outlined), findsOneWidget);
    expect(find.byIcon(Icons.phonelink_outlined), findsOneWidget);
  });
}
