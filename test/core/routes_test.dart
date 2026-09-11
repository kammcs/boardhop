import 'package:boardhop/core/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('routes are account-scoped and encoded', () {
    expect(Routes.account('a.b'), '/a/a.b');
    expect(Routes.org('u1', 'my org'), '/a/u1/orgs/my%20org');
    expect(
      Routes.project('u1', 'puremedia', 'DevOps Mobile App'),
      '/a/u1/orgs/puremedia/projects/DevOps%20Mobile%20App',
    );
  });
}
