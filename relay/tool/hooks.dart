/// `dart run tool/hooks.dart <command> …` — provisions the beta's service-hook
/// subscriptions (research/14 §1, §9 R2.8).
///
/// Commands:
///
/// ```
/// plan   --org <org> --project <name>
/// secret --org <org> [--out <path>]
/// create --org <org> --project <name> --secret-file <path>
/// list   --org <org> [--project <name>]
/// delete --org <org> --project <name>
/// ```
///
/// Environment: `ADO_ORG_URL`, `ADO_PAT`, `RELAY_URL` (default
/// https://boardhop.relay.kammcs.com), `RELAY_ADMIN_SECRET`, and
/// `HOOKS_ALLOW_PROJECT`, which is the write guard: `create` and `delete`
/// refuse any project but the one it names (CLAUDE.md hard rule 1).
///
/// This file is deliberately thin — argument parsing and exit codes. Everything
/// else is in `tool/src/`, where `test/tool_hooks_test.dart` can reach it.
library;

import 'dart:io';

import 'package:http/http.dart' as http;

import 'src/hooks_commands.dart';
import 'src/hooks_lib.dart';

const _usage = '''
Usage: dart run tool/hooks.dart <command> [options]

  plan   --org <org> --project <name>              print the planned subscriptions, call nothing
  secret --org <org> [--out <path>]                generate a hook secret, store its hash on the relay
  create --org <org> --project <name> --secret-file <path>
  list   --org <org> [--project <name>]            Azure DevOps and the relay registry side by side
  delete --org <org> --project <name>              remove this org's ingest subscriptions for one project

Environment: ADO_ORG_URL, ADO_PAT, RELAY_URL, RELAY_ADMIN_SECRET, HOOKS_ALLOW_PROJECT.
`create` and `delete` write to Azure DevOps and refuse any project but HOOKS_ALLOW_PROJECT.
''';

Future<void> main(List<String> arguments) async {
  final code = await run(arguments, stdout.writeln, stderr.writeln);
  if (code != 0) exitCode = code;
}

/// The whole CLI, with its sinks injected so a test can drive it.
Future<int> run(List<String> arguments, void Function(String) out, void Function(String) err) async {
  if (arguments.isEmpty || arguments.first == '--help' || arguments.first == '-h') {
    out(_usage);
    return arguments.isEmpty ? 2 : 0;
  }

  final command = arguments.first;
  final Map<String, String> options;
  try {
    options = parseOptions(arguments.skip(1));
  } on HooksFailure catch (failure) {
    err(failure.message);
    return 2;
  }

  final config = HooksConfig.fromEnvironment(Platform.environment);
  final client = http.Client();
  final runner = HooksRunner(
    config: config,
    http: HooksHttp(config: config, client: client),
    out: out,
  );

  try {
    switch (command) {
      case 'plan':
        runner.plan(org: require(options, 'org'), project: require(options, 'project'));
      case 'secret':
        final org = require(options, 'org');
        await runner.secret(org: org, outPath: options['out'] ?? '.hooks-secret-$org');
      case 'create':
        await runner.create(
          org: require(options, 'org'),
          project: require(options, 'project'),
          secretFile: require(options, 'secret-file'),
        );
      case 'list':
        await runner.list(org: require(options, 'org'), project: options['project']);
      case 'delete':
        await runner.delete(org: require(options, 'org'), project: require(options, 'project'));
      default:
        err('unknown command "$command"');
        err(_usage);
        return 2;
    }
  } on HooksFailure catch (failure) {
    err(failure.message);
    return 1;
  } on Object catch (error) {
    // Anything unexpected still goes through the redactor before it is printed.
    err(redactSecrets('$error', config.secrets));
    return 1;
  } finally {
    client.close();
  }
  return 0;
}

/// `--name value` pairs; `--name=value` works too. No positional arguments.
Map<String, String> parseOptions(Iterable<String> arguments) {
  final options = <String, String>{};
  final list = arguments.toList();
  for (var i = 0; i < list.length; i++) {
    final argument = list[i];
    if (!argument.startsWith('--')) throw HooksFailure('unexpected argument "$argument"');
    final equals = argument.indexOf('=');
    if (equals > 2) {
      options[argument.substring(2, equals)] = argument.substring(equals + 1);
      continue;
    }
    final name = argument.substring(2);
    if (i + 1 >= list.length) throw HooksFailure('--$name needs a value');
    options[name] = list[++i];
  }
  return options;
}

/// The value of a required option, or a failure naming it.
String require(Map<String, String> options, String name) {
  final value = options[name];
  if (value == null || value.isEmpty) throw HooksFailure('--$name is required');
  return value;
}
