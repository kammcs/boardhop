import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:msal_auth/msal_auth.dart' show Account;

import '../../launch/launch_resolver.dart';

/// Where to land after the set of signed-in accounts changed: phase LA's
/// [LaunchResolver] answers it, the picker only calls it.
typedef ResolveLanding = Future<String?> Function(
  List<Account> accounts, {
  String? preferAccountId,
});

/// The picker's default landing resolver, bound to [context].
///
/// This file is the only place that knows about the resolver, so the picker
/// stays testable with a plain function and the two phases meet here.
ResolveLanding landingResolverFor(BuildContext context) {
  final resolver = context.read<LaunchResolver>();
  return (accounts, {preferAccountId}) async => (await resolver.resolve(
    accounts,
    preferAccountId: preferAccountId,
  )).route;
}
