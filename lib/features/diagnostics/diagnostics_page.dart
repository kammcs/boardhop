import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_service.dart';
import '../../core/config/app_config.dart';
import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/http/ado_host.dart';
import '../../theme/theme.dart';

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

  /// Harmless claims request: re-states the CP1 capability MSAL already
  /// sends, so the token endpoint accepts it. Proves the `claims` plumbing
  /// reaches native MSAL and forces a network round trip.
  static const _probeClaims = '{"access_token":{"xms_cc":{"values":["CP1"]}}}';

  @override
  void dispose() {
    _orgController.dispose();
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
    await step(1, () async {
      final account = await auth.currentAccount();
      if (account == null) throw const AdoAuthException('no cached account');
      return 'id=${account.id} username=${account.username} name=${account.name}';
    });

    String? baselineFp;
    await step(2, () async {
      final r = await auth.acquireSilent();
      baselineFp = _fingerprint(r.accessToken);
      return '${_describe(r)}, scheme=${r.authenticationScheme}, '
          'scopes=${r.scopes.map((s) => s.split('/').last).join(' ')}, '
          'idToken=${r.idToken == null ? 'none' : '${utf8.encode(r.idToken!).length} bytes'}';
    });

    await step(3, () async {
      final r = await auth.acquireSilent(forceRefresh: true);
      final fp = _fingerprint(r.accessToken);
      final changed = fp != baselineFp;
      return '${_describe(r)} '
          '${changed ? 'NEW token (cache bypassed)' : 'SAME token as cached: forceRefresh did not reach MSAL'}';
    });

    await step(4, () async {
      final r = await auth.acquireSilent(claims: _probeClaims);
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

    if (mounted) setState(() => _running = false);
  }

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
      body: ListView(
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
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.play_arrow),
            label: Text(_running ? 'Running…' : 'Run checks'),
          ),
          const SizedBox(height: 16),
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
    );
  }
}
