import 'package:flutter/widgets.dart';

import '../../core/routes.dart';

/// Which signed-in account the widgets below act as. Set by the `/a/:account`
/// shell route together with that account's repositories; pages read it to
/// build routes that stay inside the same account.
class AccountScope extends InheritedWidget {
  const AccountScope({
    super.key,
    required this.accountId,
    required super.child,
  });

  final String accountId;

  static String of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AccountScope>();
    assert(scope != null, 'AccountScope missing above this widget');
    return scope!.accountId;
  }

  static String? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountScope>()?.accountId;

  @override
  bool updateShouldNotify(AccountScope old) => old.accountId != accountId;
}

/// `/a/{account}/orgs/{org}` for the account in scope.
String orgRoute(BuildContext context, String org) =>
    Routes.org(AccountScope.of(context), org);

/// `/a/{account}/orgs/{org}/projects/{project}` for the account in scope.
String projectRoute(BuildContext context, String org, String project) =>
    Routes.project(AccountScope.of(context), org, project);
