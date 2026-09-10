import 'package:equatable/equatable.dart';

/// Outcome of one branch policy evaluation or one PR status, folded into a
/// single vocabulary for the detail page's Checks section.
enum PrCheckState { succeeded, failed, pending, error, notApplicable }

class PrCheck extends Equatable {
  const PrCheck({
    required this.name,
    required this.state,
    this.detail,
    this.isBlocking = false,
    this.url,
  });

  /// One row of `_apis/policy/evaluations` for the PR's artifact id
  /// (spike s15: status is approved / rejected / queued / running / broken /
  /// notApplicable; `configuration.type.displayName` names the policy).
  factory PrCheck.fromEvaluation(Map<String, dynamic> json) {
    final config =
        (json['configuration'] as Map?)?.cast<String, dynamic>() ?? const {};
    final type = (config['type'] as Map?)?.cast<String, dynamic>() ?? const {};
    final settings =
        (config['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
    final context =
        (json['context'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = type['displayName'] as String? ?? 'Policy';
    return PrCheck(
      name: name,
      state: switch (json['status']) {
        'approved' => PrCheckState.succeeded,
        'rejected' => PrCheckState.failed,
        'queued' || 'running' => PrCheckState.pending,
        'broken' => PrCheckState.error,
        _ => PrCheckState.notApplicable,
      },
      isBlocking: config['isBlocking'] as bool? ?? false,
      detail: _describe(name, settings, context, json['status'] as String?),
      url: context['buildOutputPreview'] is Map
          ? null
          : (context['buildId'] == null ? null : null),
    );
  }

  /// One row of `pullRequests/{id}/statuses`; a missing `state` is a status
  /// that has only been queued (spike s15).
  factory PrCheck.fromStatus(Map<String, dynamic> json) {
    final context =
        (json['context'] as Map?)?.cast<String, dynamic>() ?? const {};
    final genre = context['genre'] as String?;
    final name = context['name'] as String? ?? 'Status';
    return PrCheck(
      name: genre == null || genre.isEmpty ? name : '$genre / $name',
      state: switch (json['state']) {
        'succeeded' => PrCheckState.succeeded,
        'failed' => PrCheckState.failed,
        'error' => PrCheckState.error,
        'notApplicable' => PrCheckState.notApplicable,
        _ => PrCheckState.pending,
      },
      detail: json['description'] as String?,
      url: json['targetUrl'] as String?,
    );
  }

  /// Statuses are posted per iteration and re-posted as they progress; keep
  /// the newest row per context, from the newest iteration only.
  static List<PrCheck> latestStatuses(List<Map<String, dynamic>> raw) {
    var lastIteration = 0;
    for (final s in raw) {
      final it = (s['iterationId'] as num?)?.toInt() ?? 0;
      if (it > lastIteration) lastIteration = it;
    }
    final byContext = <String, Map<String, dynamic>>{};
    for (final s in raw) {
      if (((s['iterationId'] as num?)?.toInt() ?? 0) != lastIteration) {
        continue;
      }
      final context = (s['context'] as Map?) ?? const {};
      final key = '${context['genre']}/${context['name']}';
      final prev = byContext[key];
      if (prev == null ||
          ((s['id'] as num?)?.toInt() ?? 0) >
              ((prev['id'] as num?)?.toInt() ?? 0)) {
        byContext[key] = s;
      }
    }
    return [for (final s in byContext.values) PrCheck.fromStatus(s)];
  }

  static String? _describe(
    String name,
    Map<String, dynamic> settings,
    Map<String, dynamic> context,
    String? status,
  ) {
    switch (name) {
      case 'Minimum number of reviewers':
        final n = settings['minimumApproverCount'];
        return n == null ? null : '$n approval${n == 1 ? '' : 's'} required';
      case 'Required reviewers':
        final ids = settings['requiredReviewerIds'];
        final n = ids is List ? ids.length : null;
        return n == null ? null : '$n required reviewer${n == 1 ? '' : 's'}';
      case 'Build':
        final build =
            context['buildDefinitionName'] as String? ??
            settings['displayName'] as String?;
        final expired = context['isExpired'] == true;
        return [
          if (build != null && build.isNotEmpty) build,
          if (expired) 'expired',
          if (status == 'running') 'running',
        ].join(' · ');
      case 'Work item linking':
        return status == 'rejected' ? 'No work item linked' : null;
      case 'Comment requirements':
        return status == 'rejected' ? 'Active comments remain' : null;
      case 'Require a merge strategy':
        return settings['allowSquash'] == true ? 'Squash allowed' : null;
    }
    return null;
  }

  final String name;
  final PrCheckState state;
  final String? detail;
  final bool isBlocking;
  final String? url;

  @override
  List<Object?> get props => [name, state, detail, isBlocking];
}
