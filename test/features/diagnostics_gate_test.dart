import 'package:boardhop/app.dart';
import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/config/app_config.dart';
import 'package:boardhop/features/orgs/org_picker_page.dart';
import 'package:boardhop/router.dart';
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
}
