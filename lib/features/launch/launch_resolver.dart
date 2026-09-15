import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:msal_auth/msal_auth.dart' show Account;

import '../../core/routes.dart';
import '../../data/last_project.dart';
import '../../data/models/organization.dart';
import '../../data/models/project.dart';
import '../../data/repositories/org_repository.dart';
import '../../data/repositories/project_repository.dart';

/// The two repositories the launch needs for one signed-in account. Handed
/// in rather than read from a `BuildContext`: the resolver runs inside
/// go_router's `redirect`, before any page of that account exists.
typedef LaunchRepositories = ({OrgRepository orgs, ProjectRepository projects});

/// Why the remembered project was not the one opened (research/21 L7).
enum LaunchFallbackReason {
  /// The account that owned the memory is no longer signed in.
  accountGone,

  /// The project itself is gone or no longer accessible.
  projectGone,
}

/// A launch that did not land where the memory said, and where it landed
/// instead — what the shell's snackbar names.
@immutable
class LaunchFallback {
  const LaunchFallback(this.reason, this.project);

  const LaunchFallback.accountGone(String project)
    : this(LaunchFallbackReason.accountGone, project);

  const LaunchFallback.projectGone(String project)
    : this(LaunchFallbackReason.projectGone, project);

  final LaunchFallbackReason reason;

  /// The project that was opened instead.
  final String project;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchFallback &&
          other.reason == reason &&
          other.project == project;

  @override
  int get hashCode => Object.hash(reason, project);

  @override
  String toString() => 'LaunchFallback(${reason.name}, $project)';
}

/// Where a signed-in cold start goes, and whether it had to settle.
@immutable
class LaunchTarget {
  const LaunchTarget(this.route, {this.fallback});

  final String route;
  final LaunchFallback? fallback;

  @override
  String toString() => 'LaunchTarget($route, fallback: $fallback)';
}

/// The fallback the resolver had to take, waiting for the shell to say so.
///
/// A notifier rather than a return value because the resolver answers
/// go_router's `redirect`, which carries a route and nothing else; the
/// `ProjectShell` the redirect ends up building [take]s it once, through
/// `context.read<LaunchResolver>().notice` — a `RepositoryProvider` refuses
/// to hold a `Listenable` of its own, so the resolver carries it.
class LaunchNotice extends ValueNotifier<LaunchFallback?> {
  LaunchNotice() : super(null);

  /// Reads the pending notice and clears it, so it is shown once.
  LaunchFallback? take() {
    final pending = value;
    if (pending != null) value = null;
    return pending;
  }
}

/// Turns the signed-in accounts into the route a launch should open
/// (research/21 §4, decisions L6–L8).
///
/// Cache first: organizations and projects come from the drift caches
/// (`watch().first`) and only reach the network (`refresh()`) when a cache
/// is empty, so a remembered launch paints without a request. Nothing here
/// ever throws — every failure degrades to the next option and finally to
/// [Routes.orgs].
class LaunchResolver {
  LaunchResolver({
    required this.repositoriesFor,
    LastProjectStore? store,
    LaunchNotice? notice,
    this.cacheTimeout = const Duration(seconds: 2),
  }) : store = store ?? LastProjectStore(),
       notice = notice ?? LaunchNotice();

  final LaunchRepositories Function(String accountId) repositoriesFor;

  /// How long a cache read may take before the launch treats it as empty.
  final Duration cacheTimeout;

  /// The device's memory of the last project; also what the shell writes
  /// through [remember].
  final LastProjectStore store;

  /// Set when a launch had to settle for something other than the memory.
  final LaunchNotice notice;

  LastProject? _remembered;

  /// The route a launch should open for [accounts].
  ///
  /// [preferAccountId] is a just-added account (L6): its first project wins
  /// over the stored memory. Otherwise the stored project is used as-is
  /// while its account is still signed in (L8, no verification), and failing
  /// that the first account's first organization and project by name.
  Future<LaunchTarget> resolve(
    List<Account> accounts, {
    String? preferAccountId,
  }) async {
    try {
      return await _resolve(accounts, preferAccountId);
    } catch (e) {
      // The launch is never the place to fail: the Accounts page always
      // works.
      debugPrint('LaunchResolver: falling back to ${Routes.orgs} ($e)');
      return const LaunchTarget(Routes.orgs);
    }
  }

  Future<LaunchTarget> _resolve(
    List<Account> accounts,
    String? preferAccountId,
  ) async {
    if (accounts.isEmpty) return const LaunchTarget(Routes.orgs);

    if (preferAccountId != null &&
        accounts.any((a) => a.id == preferAccountId)) {
      final first = await _firstProject(preferAccountId);
      if (first != null) {
        return _announce(
          LaunchTarget(Routes.home(preferAccountId, first.org, first.project)),
        );
      }
      // The new account has nothing to show; carry on down the list
      // rather than stranding the launch.
    }

    final stored = await _read();
    if (stored != null && accounts.any((a) => a.id == stored.accountId)) {
      _remembered = stored;
      return _announce(
        LaunchTarget(Routes.home(stored.accountId, stored.org, stored.project)),
      );
    }

    for (final account in accounts) {
      final first = await _firstProject(account.id);
      if (first == null) continue;
      return _announce(
        LaunchTarget(
          Routes.home(account.id, first.org, first.project),
          // Only a memory that existed and could not be used is worth a
          // word; a first launch has nothing to explain.
          fallback: stored == null
              ? null
              : LaunchFallback.accountGone(first.project),
        ),
      );
    }
    return const LaunchTarget(Routes.orgs);
  }

  LaunchTarget _announce(LaunchTarget target) {
    if (target.fallback != null) notice.value = target.fallback;
    return target;
  }

  Future<LastProject?> _read() async {
    try {
      return await store.read();
    } catch (e) {
      debugPrint('LaunchResolver: last project unreadable ($e)');
      return null;
    }
  }

  /// The first organization (by name) of [accountId] that has a project,
  /// and that organization's first project (by name).
  Future<({String org, String project})?> _firstProject(
    String accountId,
  ) async {
    final LaunchRepositories repos;
    try {
      repos = repositoriesFor(accountId);
    } catch (e) {
      debugPrint('LaunchResolver: no repositories for $accountId ($e)');
      return null;
    }
    for (final org in await _orgs(repos.orgs)) {
      final projects = await _projects(repos.projects, org);
      if (projects.isNotEmpty) {
        return (org: org.name, project: projects.first.name);
      }
    }
    return null;
  }

  /// `OrgRepository.watch()` orders by last-opened first; the launch wants
  /// them alphabetical (L7), so they are sorted again here.
  Future<List<Organization>> _orgs(OrgRepository repo) async {
    var list = await _cached(repo.watch());
    if (list == null || list.isEmpty) {
      try {
        list = await repo.refresh();
      } catch (e) {
        debugPrint('LaunchResolver: organizations unavailable ($e)');
        return const [];
      }
    }
    return [...list]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<List<Project>> _projects(
    ProjectRepository repo,
    Organization org,
  ) async {
    var list = await _cached(repo.watch(org.name));
    if (list == null || list.isEmpty) {
      try {
        list = await repo.refresh(org.name, tenantId: org.tenantId);
      } catch (e) {
        debugPrint('LaunchResolver: projects of ${org.name} unavailable ($e)');
        return const [];
      }
    }
    return [...list]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// The cache's current contents. A drift `watch()` emits straight away,
  /// so the timeout only guards a store that never answers.
  Future<List<T>?> _cached<T>(Stream<List<T>> stream) async {
    try {
      return await stream.first.timeout(cacheTimeout);
    } catch (e) {
      debugPrint('LaunchResolver: cache read failed ($e)');
      return null;
    }
  }

  /// Entering a project remembers it, and keeps the older per-account org
  /// memory (`organizations.lastOpenedAt`) in step. Called on every project
  /// route; writes only when the account, organization or project changed,
  /// so switching tabs costs nothing.
  Future<void> remember(String accountId, String org, String project) async {
    final next = LastProject(accountId: accountId, org: org, project: project);
    if (next == _remembered) return;
    _remembered = next;
    try {
      await store.write(next);
    } catch (e) {
      debugPrint('LaunchResolver: could not remember $next ($e)');
    }
    try {
      await repositoriesFor(accountId).orgs.markOpened(org);
    } catch (e) {
      debugPrint('LaunchResolver: could not mark $org opened ($e)');
    }
  }

  /// Drops the memory (the last account signing out).
  Future<void> forget() async {
    _remembered = null;
    try {
      await store.clear();
    } catch (e) {
      debugPrint('LaunchResolver: could not clear the memory ($e)');
    }
  }
}
