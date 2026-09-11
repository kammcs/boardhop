import 'package:boardhop/app.dart';
import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/routes.dart';
import 'package:boardhop/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _AuthService extends Mock implements AuthService {}

class _Deps extends Mock implements AppDependencies {}

void main() {
  // go_router validates the route table with asserts, which profile and
  // release builds skip; a debug build (or this test) is where a bad
  // table shows up, e.g. a tab shell branch defaulting to a parameterized
  // route.
  test('route table passes go_router debug checks', () {
    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    final router = buildRouter(auth, _Deps());
    addTearDown(router.dispose);

    final project = Routes.project('u1', 'puremedia', 'DevOps Mobile App');
    for (final tail in [
      'home',
      'work-items/15503',
      'boards',
      'repos',
      'pipelines/runs/1/logs/2',
    ]) {
      final match = router.configuration.findMatch(Uri.parse('$project/$tail'));
      expect(match.isError, isFalse, reason: tail);
      expect(match.pathParameters['org'], 'puremedia', reason: tail);
    }
    final item = router.configuration.findMatch(
      Uri.parse('$project/work-items/15503'),
    );
    expect(item.pathParameters['id'], '15503');
  });
}
