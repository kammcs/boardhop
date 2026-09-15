import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_service.dart';
import '../../core/config/app_config.dart';
import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/http/ado_host.dart';
import '../../core/routes.dart';
import '../../data/models/sprint.dart';
import '../../data/repositories/analytics_repository.dart';
import '../../theme/theme.dart';
import '../notifications/push_service.dart';

/// Spike F1 and F2 runner (NEXT-STEPS.md steps 2 and 3).
///
/// Runs the checklist against the signed-in account and shows a report that
/// can be copied. Tokens are never displayed or copied; only their byte size
/// and a short fingerprint so two tokens can be told apart.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _Check {
  _Check(this.name);
  final String name;
  String status = 'pending';
  String detail = '';
  Duration? elapsed;
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final List<_Check> _checks = <_Check>[];
  bool _running = false;
  final _orgController = TextEditingController(text: 'puremedia');

  /// The Analytics probe is project-scoped: the org-level OData route is
  /// 403 for everyone (spike s55).
  final _projectController = TextEditingController(text: 'DevOps Mobile App');

  /// Harmless claims request: re-states the CP1 capability MSAL already
  /// sends, so the token endpoint accepts it. Proves the `claims` plumbing
  /// reaches native MSAL and forces a network round trip.
  static const _probeClaims = '{"access_token":{"xms_cc":{"values":["CP1"]}}}';

  @override
  void dispose() {
    _orgController.dispose();
    _projectController.dispose();
    super.dispose();
  }

  static String _fingerprint(String token) =>
      base64Url.encode(utf8.encode(token)).hashCode.toRadixString(16);

  static String _describe(dynamic r) {
    final ttl = r.expiresOn.difference(DateTime.now());
    return 'accessToken=${utf8.encode(r.accessToken).length} bytes '
        'fp=${_fingerprint(r.accessToken)} '
        'expires in ${ttl.inHours}h${ttl.inMinutes % 60}m '
        'tenant=${r.tenantId}';
  }

  Future<void> _run() async {
    final auth = context.read<AuthService>();
    final client = context.read<AdoClient>();
    final org = _orgController.text.trim();
    final project = _projectController.text.trim();
    setState(() {
      _running = true;
      _checks
        ..clear()
        ..addAll([
          _Check('Configuration'),
          _Check('Cached account'),
          _Check('Silent token (home tenant)'),
          _Check('F2: silent token with forceRefresh'),
          _Check('F2: silent token with claims request'),
          _Check('Profile: app.vssps profiles/me'),
          _Check('Accounts: app.vssps accounts?memberId'),
          _Check('Projects: dev.azure.com/$org'),
          _Check('Org-scoped profile: vssps.dev.azure.com/$org'),
          _Check('Rate-limit headers seen'),
          // The S6 gate (research/18): `vso.analytics` is on the
          // registration, but `analytics.dev.azure.com` is a different host
          // from `dev.azure.com` and only the spike PAT had ever been tried
          // against it. If this fails there is no burndown and no cheap
          // fallback.
          _Check('Analytics: burndown for $org/$project'),
        ]);
    });

    Future<void> step(int i, Future<String> Function() body) async {
      final sw = Stopwatch()..start();
      try {
        final detail = await body();
        _checks[i]
          ..status = 'ok'
          ..detail = detail;
      } on AdoException catch (e) {
        _checks[i]
          ..status = 'fail'
          ..detail = e.toString();
      } catch (e) {
        _checks[i]
          ..status = 'fail'
          ..detail = '$e';
      } finally {
        _checks[i].elapsed = sw.elapsed;
        if (mounted) setState(() {});
      }
    }

    await step(0, () async {
      return 'platform=${AuthService.platformLabel} '
          'clientId=${AppConfig.isConfigured ? 'set (${AppConfig.clientId.length} chars)' : 'MISSING'} '
          'authority=${AppConfig.authority} scopes=${AppConfig.adoScopes} '
          'capabilities=${AppConfig.clientCapabilities}';
    });

    String? profileId;
    String? accountId;
    await step(1, () async {
      final accounts = await auth.accounts();
      if (accounts.isEmpty) throw const AdoAuthException('no cached account');
      final account = accounts.first;
      accountId = account.id;
      return '${accounts.length} account(s); first: id=${account.id} '
          'username=${account.username} name=${account.name}';
    });

    String? baselineFp;
    await step(2, () async {
      final r = await auth.acquireSilent(accountId: accountId!);
      baselineFp = _fingerprint(r.accessToken);
      return '${_describe(r)}, scheme=${r.authenticationScheme}, '
          'scopes=${r.scopes.map((s) => s.split('/').last).join(' ')}, '
          'idToken=${r.idToken == null ? 'none' : '${utf8.encode(r.idToken!).length} bytes'}';
    });

    await step(3, () async {
      final r = await auth.acquireSilent(
        accountId: accountId!,
        forceRefresh: true,
      );
      final fp = _fingerprint(r.accessToken);
      final changed = fp != baselineFp;
      return '${_describe(r)} '
          '${changed ? 'NEW token (cache bypassed)' : 'SAME token as cached: forceRefresh did not reach MSAL'}';
    });

    await step(4, () async {
      final r = await auth.acquireSilent(
        accountId: accountId!,
        claims: _probeClaims,
      );
      return '${_describe(r)} claims request accepted by token endpoint';
    });

    await step(5, () async {
      final json = await client.getJson(
        host: AdoHost.appVssps,
        path: '_apis/profile/profiles/me',
        apiVersion: '7.1',
      );
      profileId = json['id'] as String?;
      return 'id=$profileId displayName=${json['displayName']} email=${json['emailAddress']}';
    });

    await step(6, () async {
      if (profileId == null) throw const AdoAuthException('no profile id');
      final json = await client.getJson(
        host: AdoHost.appVssps,
        path: '_apis/accounts',
        apiVersion: '7.1',
        query: {'memberId': profileId!},
      );
      final names = (json['value'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => m['accountName'])
          .join(', ');
      return 'count=${json['count']} orgs=[$names]';
    });

    await step(7, () async {
      final json = await client.getJson(
        org: org,
        path: '_apis/projects',
        apiVersion: '7.1',
        query: {'\$top': '50'},
      );
      final names = (json['value'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => m['name'])
          .join(', ');
      return 'count=${json['count']} projects=[$names]';
    });

    await step(8, () async {
      final json = await client.getJson(
        host: AdoHost.vssps,
        org: org,
        path: '_apis/profile/profiles/me',
        apiVersion: '7.1',
      );
      return 'id=${json['id']} displayName=${json['displayName']}';
    });

    await step(9, () async {
      final log = client.rateLimits.log;
      if (log.isEmpty) return 'none (expected on a quiet org)';
      return log.map((e) => e.toString()).join('\n');
    });

    await step(10, () async {
      if (project.isEmpty) throw const AdoNotFoundException('no project set');
      final projectJson = await client.getJson(
        org: org,
        path: '_apis/projects/$project',
        apiVersion: '7.1',
      );
      final team = (projectJson['defaultTeam'] as Map?)?['id'] as String?;
      if (team == null) {
        throw AdoServerException('$project has no default team');
      }
      // `$timeframe` accepts only `current`; anything else is a 400.
      final iterations = await client.getJson(
        org: org,
        project: project,
        team: team,
        path: '_apis/work/teamsettings/iterations',
        apiVersion: '7.1',
        query: {r'$timeframe': 'current'},
      );
      final current = ((iterations['value'] as List?) ?? const [])
          .whereType<Map>()
          .firstOrNull;
      if (current == null) {
        throw const AdoNotFoundException('no current iteration for this team');
      }
      final id = current['id'] as String? ?? '';
      final attributes = (current['attributes'] as Map?) ?? const {};
      final now = DateTime.now().toUtc();
      final start =
          DateTime.tryParse(attributes['startDate'] as String? ?? '') ??
          now.subtract(const Duration(days: 14));
      final end =
          DateTime.tryParse(attributes['finishDate'] as String? ?? '') ?? now;
      final sw = Stopwatch()..start();
      final days = await AnalyticsRepository(client)
          .burndown(org, project, id, start: start, end: end, refresh: true);
      final dated = attributes['startDate'] == null ? ' (undated sprint)' : '';
      if (days.isEmpty) {
        return 'token ACCEPTED by analytics.dev.azure.com; '
            '0 rows for "${current['name']}"$dated in ${sw.elapsedMilliseconds} ms '
            '(no snapshot history for this sprint)';
      }
      final first = days.first;
      final last = days.last;
      return 'token ACCEPTED by analytics.dev.azure.com; '
          '${days.length} days for "${current['name']}"$dated '
          'in ${sw.elapsedMilliseconds} ms; '
          'first ${_dayLabel(first)} last ${_dayLabel(last)}';
    });

    if (mounted) setState(() => _running = false);
  }

  static String _dayLabel(BurndownDay d) =>
      '${d.date.toIso8601String().substring(0, 10)} '
      'remaining=${d.remaining} done=${d.done} sp=${d.points}';

  String _report() {
    final b = StringBuffer(
      'Boardhop diagnostics ${DateTime.now().toIso8601String()}\n',
    );
    for (final c in _checks) {
      b.writeln(
        '[${c.status.toUpperCase()}] ${c.name} '
        '(${c.elapsed?.inMilliseconds ?? '-'} ms)',
      );
      if (c.detail.isNotEmpty) b.writeln('    ${c.detail}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics (spikes F1, F2)'),
        actions: [
          IconButton(
            tooltip: 'Editor probe (F3)',
            icon: const Icon(Icons.edit_note),
            onPressed: () => context.push('/diagnostics/editor'),
          ),
          IconButton(
            tooltip: 'Board probe (F4)',
            icon: const Icon(Icons.view_kanban_outlined),
            onPressed: () => context.push('/diagnostics/board'),
          ),
          IconButton(
            tooltip: 'Diff probe (F5)',
            icon: const Icon(Icons.difference_outlined),
            onPressed: () => context.push('/diagnostics/diff'),
          ),
          IconButton(
            tooltip: 'Mention probe (M-B)',
            icon: const Icon(Icons.alternate_email),
            onPressed: () => context.push('/diagnostics/mention'),
          ),
          IconButton(
            tooltip: 'Sprint widgets probe (P-B)',
            icon: const Icon(Icons.timelapse),
            onPressed: () => context.push('/diagnostics/sprint'),
          ),
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy),
            onPressed: _checks.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _report()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Report copied')),
                      );
                    }
                  },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _orgController,
              decoration: const InputDecoration(
                labelText: 'Organization to probe',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _projectController,
              decoration: const InputDecoration(
                labelText: 'Project to probe (Analytics)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.play_arrow),
              label: Text(_running ? 'Running…' : 'Run checks'),
            ),
            const SizedBox(height: 16),
            if (kDebugMode) const _RouteBox(),
            if (kDebugMode) const _EnrichBox(),
            const _EnvironmentCard(),
            for (final c in _checks)
              Card(
                child: ListTile(
                  leading: Icon(switch (c.status) {
                    'ok' => Icons.check_circle,
                    'fail' => Icons.error,
                    _ => Icons.hourglass_empty,
                  }),
                  title: Text(c.name),
                  subtitle: Text(
                    '${c.detail}\n${c.elapsed?.inMilliseconds ?? '-'} ms',
                    style: BoardhopTheme.codeStyle(context),
                  ),
                  isThreeLine: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A route typed by hand, for checking a deep link on a device where no
/// notification can be tapped and no `adb` intent reaches the router
/// (research/14 §4.2 anchors). Debug builds only.
class _RouteBox extends StatefulWidget {
  const _RouteBox();

  @override
  State<_RouteBox> createState() => _RouteBoxState();
}

class _RouteBoxState extends State<_RouteBox> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A route that does not name an account gets the signed-in one's
  /// prefix, so only the interesting half has to be typed:
  /// `/orgs/puremedia/pull-requests/8334?thread=42566`.
  void _go() {
    var route = _controller.text.trim();
    if (route.isEmpty) return;
    if (!route.startsWith('/a/')) {
      final account = context.read<AuthService>().knownAccounts.firstOrNull;
      if (account == null) return;
      if (!route.startsWith('/')) route = '/$route';
      route = '${Routes.account(account.id)}$route';
    }
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear),
                  onPressed: _controller.clear,
                ),
                labelText: 'Open route (debug)',
                helperText:
                    '/orgs/{org}/... (the account is added) with '
                    '?comment=, ?thread=, ?tab=approvals&approval=',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _go(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _go,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Go'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs the **Android** enrichment path (R2.6) against a pointer typed by
/// hand, and posts whatever it produces, so the fetch, the body and the
/// lock-screen shape can be checked against real read-only artifacts without
/// waiting for a real event to fire. Debug builds only, on both sides: the
/// `debugEnrich` method refuses a non-debuggable build.
class _EnrichBox extends StatefulWidget {
  const _EnrichBox();

  @override
  State<_EnrichBox> createState() => _EnrichBoxState();
}

class _EnrichBoxState extends State<_EnrichBox> {
  /// Pointers shaped exactly like the relay's, against the read-only scratch
  /// artifacts of CLAUDE.md's "Test data in puremedia", one per §4.1 row that
  /// this project can exercise. Typing a pointer by hand on a phone is not
  /// realistic, so the presets are the interface.
  static const _samples = <String, String>{
    'Work item comment':
        '{"org":"puremedia","project":"DevOps Mobile App",'
        '"artifactType":"workItem","artifactId":"15545",'
        '"eventType":"workitem.commented","verb":"commented",'
        '"actor":"Kelly Kamm","anchor":"comment:0",'
        '"collapseKey":"puremedia.wi.15545.c",'
        '"fallbackTitle":"#15545 · Boardhop spike task",'
        '"fallbackBody":"Kelly Kamm commented on #15545",'
        '"fallbackSubtitle":"DevOps Mobile App"}',
    'Work item state':
        '{"org":"puremedia","project":"DevOps Mobile App",'
        '"artifactType":"workItem","artifactId":"15545",'
        '"eventType":"workitem.updated","verb":"stateChanged",'
        '"actor":"Kelly Kamm","detail":"Active",'
        '"collapseKey":"puremedia.wi.15545",'
        '"fallbackTitle":"#15545 · Boardhop spike task",'
        '"fallbackBody":"Kelly Kamm moved #15545 to Active",'
        '"fallbackSubtitle":"DevOps Mobile App"}',
    'PR thread':
        '{"org":"puremedia","project":"DevOps Mobile App",'
        '"artifactType":"pullRequest","artifactId":"8334",'
        '"eventType":"ms.vss-code.git-pullrequest-comment-event",'
        '"verb":"replied","actor":"Kelly Kamm","anchor":"thread:42511",'
        '"collapseKey":"puremedia.pr.8334.t42511",'
        '"fallbackTitle":"!8334 · Scratch PR for Boardhop tests",'
        '"fallbackBody":"Kelly Kamm replied on !8334",'
        '"fallbackSubtitle":"DevOps Mobile App"}',
    'PR review':
        '{"org":"puremedia","project":"DevOps Mobile App",'
        '"artifactType":"pullRequest","artifactId":"8334",'
        '"eventType":"git.pullrequest.updated","verb":"reviewRequested",'
        '"actor":"Kelly Kamm","collapseKey":"puremedia.pr.8334",'
        '"fallbackTitle":"!8334 · Scratch PR for Boardhop tests",'
        '"fallbackBody":"Kelly Kamm asked you to review !8334",'
        '"fallbackSubtitle":"DevOps Mobile App"}',
    'Build':
        '{"org":"puremedia","project":"DevOps Mobile App",'
        '"artifactType":"build","artifactId":"20163",'
        '"eventType":"build.complete","verb":"buildSucceeded",'
        '"detail":"succeeded","collapseKey":"puremedia.build.20163",'
        '"fallbackTitle":"boardhop-scratch · 20260913.1",'
        '"fallbackBody":"Build succeeded",'
        '"fallbackSubtitle":"DevOps Mobile App"}',
    'Approval':
        '{"org":"puremedia","project":"DevOps Mobile App",'
        '"artifactType":"approval",'
        '"artifactId":"53d82215-e7d6-444d-8763-abd96b5df8fb",'
        '"eventType":"ms.vss-pipelinechecks-events.approval-completed",'
        '"verb":"approvalCompleted","detail":"approved",'
        '"collapseKey":"puremedia.approval.53d82215",'
        '"fallbackTitle":"boardhop-scratch → Deploy",'
        '"fallbackBody":"Kelly Kamm approved the approval",'
        '"fallbackSubtitle":"DevOps Mobile App"}',
  };

  final _controller = TextEditingController(text: _samples.values.first);
  String? _outcome;
  bool _running = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _outcome = null;
    });
    String outcome;
    try {
      final decoded = jsonDecode(_controller.text.trim());
      if (decoded is! Map) throw const FormatException('not a JSON object');
      final data = <String, String>{
        for (final entry in decoded.entries)
          if (entry.value != null) '${entry.key}': '${entry.value}',
      };
      // `sentAt` is what keeps a pointer out of the stale branch; fill it in
      // when the typed pointer has none, so the fetch actually runs.
      data['sentAt'] ??= DateTime.now().toUtc().toIso8601String();
      outcome =
          await PushService.channel.invokeMethod<String>('debugEnrich', data) ??
          'no answer';
    } on PlatformException catch (e) {
      outcome = '${e.code}: ${e.message}';
    } catch (e) {
      outcome = '$e';
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autocorrect: false,
              maxLines: 6,
              minLines: 3,
              style: BoardhopTheme.codeStyle(context),
              decoration: const InputDecoration(
                labelText: 'Enrich a pointer (debug, Android)',
                helperText:
                    'The FCM data map as JSON; posts the notification it '
                    'would have posted',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in _samples.entries)
                  ActionChip(
                    label: Text(entry.key),
                    onPressed: () => _controller.text = entry.value,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.notifications_active_outlined),
              label: Text(_running ? 'Enriching…' : 'Run enrichment'),
            ),
            if (_outcome != null) ...[
              const SizedBox(height: 12),
              Text(_outcome!, style: BoardhopTheme.codeStyle(context)),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the platform tells Flutter about this session: the layout class,
/// text scale and accessibility flags that change behaviour (for one,
/// `accessibleNavigation` keeps snackbars with an action open until they
/// are dismissed). DESIGN.md section 8 checks dynamic type and screen
/// readers here before each milestone.
class _EnvironmentCard extends StatelessWidget {
  const _EnvironmentCard();

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final lines = <String>[
      'platform: ${Theme.of(context).platform.name}',
      'size: ${mq.size.width.round()} x ${mq.size.height.round()} dp, '
          'breakpoint: ${context.breakpoint.name}',
      'textScale: ${mq.textScaler.scale(16) / 16}',
      'accessibleNavigation: ${mq.accessibleNavigation}',
      'boldText: ${mq.boldText}, highContrast: ${mq.highContrast}',
      'disableAnimations: ${mq.disableAnimations}, '
          'invertColors: ${mq.invertColors}',
    ];
    return Card(
      child: ListTile(
        leading: const Icon(Icons.phone_iphone),
        title: const Text('Environment'),
        subtitle: Text(
          lines.join('\n'),
          style: BoardhopTheme.codeStyle(context),
        ),
        isThreeLine: true,
      ),
    );
  }
}
