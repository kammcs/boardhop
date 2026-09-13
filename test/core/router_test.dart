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

  // research/14 §4.2: a pushed pointer's anchor rides along as a query
  // string. The pages read it from R2.5 on; until then the router has to
  // tolerate a parameter no page asks for, or every anchored tap is an error
  // page.
  test('the pushed anchors resolve to the same pages', () {
    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    final router = buildRouter(auth, _Deps());
    addTearDown(router.dispose);

    final org = Routes.org('u1', 'contoso');
    final project = Routes.project('u1', 'contoso', 'DevOps Mobile App');
    final anchored = {
      '$project/work-items/15545?comment=1998234':
          '$project/work-items/15545',
      '$org/pull-requests/8336?thread=4821': '$org/pull-requests/8336',
      '$org/pull-requests/8336?tab=files': '$org/pull-requests/8336',
      '$project/pipelines?tab=approvals&approval=18': '$project/pipelines',
    };
    anchored.forEach((withAnchor, plain) {
      final match = router.configuration.findMatch(Uri.parse(withAnchor));
      expect(match.isError, isFalse, reason: withAnchor);
      final bare = router.configuration.findMatch(Uri.parse(plain));
      expect(
        match.matches.last.route,
        same(bare.matches.last.route),
        reason: withAnchor,
      );
    });

    final approval = router.configuration.findMatch(
      Uri.parse('$project/pipelines?tab=approvals&approval=18'),
    );
    expect(approval.uri.queryParameters['tab'], 'approvals');
    expect(approval.uri.queryParameters['approval'], '18');
  });
}
