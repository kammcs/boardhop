import '../../demo_world.dart';
import 'pipeline_plans.dart';
import 'pipeline_test_names.dart';

/// Log lines for one task or job of a demo run, in the service's format:
/// every line starts with a `2026-09-16T14:02:11.1234567Z ` timestamp, and
/// the body sits between `##[section]Starting:` and `##[section]Finishing:`.
List<String> demoLogLines(DemoRun run, DemoLog log) {
  final w = _LogWriter(log.start, log.finish, seed: run.id * 31 + log.id);
  final body = switch (log.kind) {
    'test' => _flutterTest,
    'goldens' => _goldens,
    'ipa' => _flutterBuildIpa,
    'aab' => _flutterBuildAab,
    'analyze' => _flutterAnalyze,
    'pubget' => _pubGet,
    'build_runner' => _buildRunner,
    'testflight' => _testFlight,
    'dart_test' => _dartTest,
    'health' => _health,
    'health_failed' => _healthFailed,
    'tfx' => _tfx,
    'lint' => _lint,
    'lint_failed' => _lintFailed,
    'job' => null,
    _ => null,
  };
  if (log.kind == 'job') {
    _jobLog(w, run, log);
    return w.lines;
  }
  w.line('##[section]Starting: ${log.name}');
  if (body == null) {
    _generic(w, run, log);
  } else {
    _commandHeader(w, log.name);
    body(w, run);
    if (log.failed) {
      w.at(1);
      w.line("##[error]Bash exited with code '1'.");
    }
  }
  w.at(1);
  w.line('##[section]Finishing: ${log.name}');
  return w.lines;
}

class _LogWriter {
  _LogWriter(this.start, this.finish, {required this.seed});

  final DateTime start;
  final DateTime finish;
  final List<String> lines = [];
  double _fraction = 0;
  int seed;
  int _lastMicros = 0;

  /// Lines that follow happen at [fraction] of the task's duration.
  void at(double fraction) => _fraction = fraction.clamp(0, 1).toDouble();

  void line(String text) {
    final span = finish.difference(start).inMicroseconds;
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    var micros = (span * _fraction).round();
    // A few milliseconds between consecutive lines, never backwards.
    final floor = _lastMicros + 300 + seed % 4200;
    if (micros < floor) micros = floor;
    if (micros > span) micros = span;
    _lastMicros = micros;
    final t = start.add(Duration(microseconds: micros));
    final whole = DemoWorld.iso(t).split('.').first;
    final subsecond = (t.millisecond * 1000 + t.microsecond) * 10 + seed % 10;
    lines.add('$whole.${subsecond.toString().padLeft(7, '0')}Z $text');
  }

  void all(Iterable<String> texts) => texts.forEach(line);
}

void _commandHeader(_LogWriter w, String name) {
  w.all([
    '==============================================================================',
    'Task         : Command line',
    'Description  : Run a command line script using Bash on Linux and macOS and cmd.exe on Windows',
    'Version      : 2.250.1',
    'Author       : Microsoft Corporation',
    'Help         : https://docs.microsoft.com/azure/devops/pipelines/tasks/utility/command-line',
    '==============================================================================',
    'Generating script.',
    'Script contents:',
    name,
    '========================== Starting Command Output ===========================',
    '/bin/bash --noprofile --norc /Users/runner/work/_temp/${demoGuid('script:$name')}.sh',
  ]);
}

void _generic(_LogWriter w, DemoRun run, DemoLog log) {
  if (log.name == 'Initialize job') {
    w.all([
      'Agent name: \'Azure Pipelines 4\'',
      'Agent machine name: \'Mac-1726493\'',
      'Current agent version: \'4.260.0\'',
      '##[group]Operating System',
      'macOS',
      '15.6.1',
      '24G90',
      '##[endgroup]',
      '##[group]Runner Image',
      'Image: macos-15-arm64',
      'Version: 20260908.1492',
      '##[endgroup]',
      'Download all required tasks.',
      'Downloading task: CmdLine (2.250.1)',
      'Downloading task: PublishTestResults (2.250.0)',
      'Downloading task: PublishPipelineArtifact (1.242.0)',
      'Checking job knob settings.',
      'Finished checking job knob settings.',
      'Start tracking orphan processes.',
    ]);
    return;
  }
  if (log.name.startsWith('Checkout')) {
    final repo = run.definition.repo;
    w.all([
      'Syncing repository: ${repo.name} (TfsGit)',
      'git version',
      'git version 2.51.0',
      'git init "/Users/runner/work/1/s"',
      'git remote add origin ${repo.url}',
      'git config gc.auto 0',
      'git -c http.extraheader="AUTHORIZATION: bearer ***" fetch --force --tags --prune --prune-tags --progress --no-recurse-submodules origin --depth=1 +${run.sha}:refs/remotes/origin/${run.sha}',
      'remote: Azure Repos',
      'remote: Found 1284 objects to send. (38 ms)',
      'Receiving objects: 100% (1284/1284), 4.12 MiB | 21.40 MiB/s, done.',
      'git checkout --progress --force refs/remotes/origin/${run.sha}',
      'HEAD is now at ${run.sha.substring(0, 7)} ${run.message ?? 'Update'}',
    ]);
    return;
  }
  if (log.name.startsWith('Install Flutter')) {
    w.all([
      'Downloading https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.47.2-stable.zip',
      'Extracting to /Users/runner/work/_tool/Flutter/3.47.2-stable/arm64',
      'Prepending PATH environment variable with directory: /Users/runner/work/_tool/Flutter/3.47.2-stable/arm64/flutter/bin',
      'Flutter 3.47.2 • channel stable • https://github.com/flutter/flutter.git',
      'Framework • revision 9f455d2486 • 2026-08-27 11:02:31 -0700',
      'Engine • hash 1ee3ad6f3f • 2026-08-26 19:44:10 +0000',
      'Tools • Dart 3.13.3 • DevTools 2.53.0',
    ]);
    return;
  }
  if (log.name == 'Finalize Job') {
    w.all([
      'Cleaning up task key',
      'Start cleaning up orphan processes.',
      'Terminate orphan process: pid (4127) (dart)',
    ]);
    return;
  }
  w.all(['Running ${log.name}', 'Done.']);
}

void _jobLog(_LogWriter w, DemoRun run, DemoLog log) {
  w.all([
    '##[section]Starting: ${log.name}',
    '##[section]Starting: Initialize job',
    'Agent name: \'Azure Pipelines 4\'',
    'Current agent version: \'4.260.0\'',
    '##[section]Finishing: Initialize job',
  ]);
  w.at(0.5);
  w.line('Job is running on ${run.definition.name}, build ${run.id}.');
  w.at(1);
  w.all([
    '##[section]Starting: Finalize Job',
    '##[section]Finishing: Finalize Job',
    log.failed
        ? '##[section]Finishing: ${log.name} (failed)'
        : '##[section]Finishing: ${log.name}',
  ]);
}

void _pubGet(_LogWriter w, DemoRun run) {
  w.all(['Resolving dependencies...', 'Downloading packages...']);
  w.at(0.8);
  w.all([
    '  _fe_analyzer_shared 92.0.0 (93.0.0 available)',
    '  analyzer 9.0.0 (9.1.0 available)',
    '  win32 5.15.0 (5.16.1 available)',
    'Got dependencies!',
    '3 packages have newer versions incompatible with dependency constraints.',
    'Try `flutter pub outdated` for more information.',
  ]);
}

void _buildRunner(_LogWriter w, DemoRun run) {
  w.all([
    '[INFO] Generating build script completed, took 612ms',
    '[INFO] Reading cached asset graph completed, took 188ms',
    '[INFO] Checking for updates since last build completed, took 941ms',
  ]);
  w.at(0.7);
  w.all([
    '[INFO] Running build completed, took 21.4s',
    '[INFO] Caching finalized dependency graph completed, took 97ms',
    '[INFO] Succeeded after 21.5s with 4 outputs (212 actions)',
  ]);
}

void _flutterAnalyze(_LogWriter w, DemoRun run) {
  w.line('Analyzing boardhop...');
  w.at(0.95);
  w.line('No issues found! (ran in 21.8s)');
}

void _flutterTest(_LogWriter w, DemoRun run) {
  w.all([
    'flutter test --reporter expanded --file-reporter json:test-results.json',
  ]);
  const total = 1774;
  final names = demoTestNames;
  var passed = 0;
  for (var i = 0; i < names.length; i++) {
    final (file, name) = names[i];
    final f = 0.04 + 0.92 * i / names.length;
    w.at(f);
    passed = (total * (i + 1) / (names.length + 1)).round();
    final secs = (f * 73).round();
    final clock =
        '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';
    w.line('$clock +$passed: $file: $name');
  }
  w.at(0.97);
  w.line('01:13 +$total: All tests passed!');
}

void _goldens(_LogWriter w, DemoRun run) {
  const goldens = [
    'board lanes at compact width, light',
    'board lanes at compact width, dark',
    'split column drop targets on iPad',
    'sprint taskboard capacity bars',
    'side-by-side diff with comment gutter',
    'pipeline run page, waiting for approval',
    'dashboard burndown tile',
    'work item form, rich text description',
  ];
  w.line('flutter test --tags golden --reporter expanded');
  for (final (i, g) in goldens.indexed) {
    w.at(0.1 + 0.8 * i / goldens.length);
    w.line(
      '00:${(8 + i * 6).toString().padLeft(2, '0')} +${i + 1}: test/goldens/goldens_test.dart: $g',
    );
  }
  w.at(0.95);
  w.line('00:58 +${goldens.length}: All tests passed!');
}

void _flutterBuildIpa(_LogWriter w, DemoRun run) {
  w.all([
    'flutter build ipa --release --build-name=1.4.0 --build-number=18 --export-options-plist=ios/ExportOptions.plist --dart-define-from-file=.env',
    '',
    'Resolving dependencies...',
    'Downloading packages...',
    'Got dependencies!',
    'Archiving com.kammcs.boardhop...',
    'Using manual signing: iPhone Distribution (App Store)',
    'Running pod install...',
  ]);
  w.at(0.02);
  const pods = [
    ('DKImagePickerController', '4.3.9'),
    ('DKPhotoGallery', '0.0.19'),
    ('Firebase', '12.2.0'),
    ('FirebaseCore', '12.2.0'),
    ('FirebaseCoreInternal', '12.2.0'),
    ('FirebaseInstallations', '12.2.0'),
    ('FirebaseMessaging', '12.2.0'),
    ('GoogleDataTransport', '10.1.0'),
    ('GoogleUtilities', '8.1.0'),
    ('MSAL', '2.14.1'),
    ('PromisesObjC', '2.4.0'),
    ('SDWebImage', '5.21.1'),
    ('SwiftyGif', '5.4.5'),
    ('file_picker', '0.0.1'),
    ('firebase_core', '4.14.0'),
    ('firebase_messaging', '16.6.0'),
    ('flutter_inappwebview_ios', '0.0.1'),
    ('flutter_local_notifications', '0.0.1'),
    ('image_picker_ios', '0.0.1'),
    ('msal_auth', '3.5.3'),
    ('nanopb', '3.30910.0'),
    ('path_provider_foundation', '0.0.1'),
    ('share_plus', '0.0.1'),
    ('shared_preferences_foundation', '0.0.1'),
    ('sqlite3', '3.50.4'),
    ('sqlite3_flutter_libs', '0.0.1'),
    ('url_launcher_ios', '0.0.1'),
  ];
  w.all([
    'Analyzing dependencies',
    'Downloading dependencies',
    for (final (name, version) in pods) 'Installing $name ($version)',
    'Generating Pods project',
    'Integrating client project',
    'Pod installation complete! There are 22 dependencies from the Podfile and 27 total pods installed.',
    'Running pod install...                                             14.2s',
  ]);
  w.at(0.04);
  w.all([
    'Running Xcode build...',
    'Resolving Swift Package Manager dependencies...',
    '  Fetching https://github.com/AzureAD/microsoft-authentication-library-for-objc (2.14.1)',
    '  Fetching https://github.com/firebase/firebase-ios-sdk (12.2.0)',
    '  Resolved source packages: msal, firebase-ios-sdk, GoogleUtilities, nanopb, promises',
  ]);
  w.at(0.12);
  w.line(' ├─Building Dart code...                                    48.6s');
  w.at(0.17);
  w.line(' ├─Assembling Flutter resources...                           3.1s');
  w.at(0.18);
  const targets = [
    'Pods-Runner',
    'GoogleUtilities',
    'FirebaseCoreInternal',
    'FirebaseCore',
    'FirebaseInstallations',
    'FirebaseMessaging',
    'MSAL',
    'msal_auth',
    'SDWebImage',
    'DKImagePickerController',
    'file_picker',
    'flutter_inappwebview_ios',
    'flutter_local_notifications',
    'sqlite3',
    'sqlite3_flutter_libs',
    'share_plus',
    'url_launcher_ios',
    'NotificationService',
    'Runner',
  ];
  for (final (i, t) in targets.indexed) {
    w.at(0.18 + 0.52 * i / targets.length);
    w.line('    Compiling target $t (arm64, Release)');
  }
  w.at(0.72);
  w.all([
    '    Linking Runner.app/Runner',
    '    Embedding NotificationService.appex',
    '    Signing Runner.app with "iPhone Distribution: KammCS" (profile "BoardHop App Store")',
    ' └─Compiling, linking and signing...                        212.4s',
    'Xcode archive done.                                         421.7s',
    'Built build/ios/archive/Runner.xcarchive (212.8MB)',
    '',
    '[✓] App Settings Validation',
    '    • Version Number: 1.4.0',
    '    • Build Number: 18',
    '    • Display Name: BoardHop',
    '    • Deployment Target: 15.0',
    '    • Bundle Identifier: com.kammcs.boardhop',
    '[✓] App Icon and Launch Image Assets Validation',
    '    • App icon is set to the correct size (1024x1024).',
    '    • Launch image is set to the default placeholder icon.',
    '',
    'To update the settings, please refer to https://flutter.dev/to/ios-deploy',
    '',
    'Building App Store IPA...',
  ]);
  w.at(0.8);
  w.all([
    '    Exporting archive with ExportOptions.plist (method: app-store-connect)',
    '    Processing symbols for Runner.app.dSYM',
    '    Processing symbols for NotificationService.appex.dSYM',
    '    Processing symbols for Flutter.framework.dSYM',
    '    Stripping Swift symbols',
    '    Re-signing Runner.app for App Store Connect',
    '    Packaging Runner.ipa',
  ]);
  w.at(0.96);
  w.all([
    'Building App Store IPA...                                          61.3s',
    'Built IPA to build/ios/ipa (38.4MB).',
    'To upload to the App Store either:',
    '    1. Drag and drop the "build/ios/ipa/*.ipa" bundle into the Apple Transporter macOS app https://apps.apple.com/us/app/transporter/id1450874784',
    '    2. Run "xcrun altool --upload-app --type ios -f build/ios/ipa/*.ipa --apiKey your_api_key --apiIssuer your_issuer_id".',
    '       See "man altool" for details about how to authenticate with the App Store Connect API key.',
    '',
  ]);
}

void _flutterBuildAab(_LogWriter w, DemoRun run) {
  w.all([
    'flutter build appbundle --release --build-name=1.4.0 --build-number=18 --dart-define-from-file=.env',
    'Resolving dependencies...',
    'Got dependencies!',
  ]);
  w.at(0.05);
  w.all([
    'Running Gradle task \'bundleRelease\'...',
    'Downloading https://services.gradle.org/distributions/gradle-8.14-all.zip',
    'Unzipping gradle-8.14-all.zip',
    'Welcome to Gradle 8.14!',
  ]);
  w.at(0.3);
  w.all([
    '> Task :app:processReleaseGoogleServices',
    '> Task :app:compileFlutterBuildRelease',
  ]);
  w.at(0.75);
  w.all([
    '> Task :app:minifyReleaseWithR8',
    '> Task :app:signReleaseBundle',
    '> Task :app:bundleRelease',
    'BUILD SUCCESSFUL in 6m 12s',
    '412 actionable tasks: 412 executed',
  ]);
  w.at(0.97);
  w.all([
    'Font asset "MaterialIcons-Regular.otf" was tree-shaken, reducing it from 1645184 to 18724 bytes (98.9% reduction).',
    'Running Gradle task \'bundleRelease\'...                           372.9s',
    '✓ Built build/app/outputs/bundle/release/app-release.aab (41.2MB)',
  ]);
}

void _testFlight(_LogWriter w, DemoRun run) {
  w.all([
    'xcrun altool --upload-app --type ios -f Runner.ipa --apiKey *** --apiIssuer ***',
    'Running altool at path \'/Applications/Xcode.app/Contents/SharedFrameworks/ContentDeliveryServices.framework/Frameworks/AppStoreService.framework/Support/altool\'...',
  ]);
  w.at(0.1);
  w.all([
    'UPLOAD STARTED: BoardHop 1.4.0 (18)',
    'Uploading package: 25% of 38.4 MB',
  ]);
  w.at(0.35);
  w.line('Uploading package: 50% of 38.4 MB');
  w.at(0.55);
  w.line('Uploading package: 75% of 38.4 MB');
  w.at(0.7);
  w.line('Uploading package: 100% of 38.4 MB');
  w.at(0.97);
  w.all([
    'UPLOAD SUCCEEDED with no errors',
    'Delivery UUID: ${demoGuid('delivery:${run.id}')}',
    'Transferred 40263118 bytes in 172.41 seconds (233.5KB/s)',
    'No errors uploading \'Runner.ipa\'',
  ]);
}

void _dartTest(_LogWriter w, DemoRun run) {
  const tests = [
    'hooks: approval-pending maps to the approval push',
    'hooks: run-state-changed keeps the requester per run',
    'apns: rotates the JWT before it expires',
    'apns: a 410 unregisters the device',
    'fcm: sends the data-only message for Android',
    'store: devices are namespaced per tenant',
    'healthz: reports apns and fcm readiness',
  ];
  w.line('dart test --reporter expanded');
  for (final (i, t) in tests.indexed) {
    w.at(0.1 + 0.8 * i / tests.length);
    w.line('00:0${1 + i} +${(i + 1) * 12}: test/relay_test.dart: $t');
  }
  w.at(0.95);
  w.line('00:09 +96: All tests passed!');
}

void _health(_LogWriter w, DemoRun run) {
  w.all([
    'curl --fail --retry 6 --retry-delay 10 https://boardhop.relay.kammcs.com/healthz',
    '{"status":"ready","apns":"ok","fcm":"ok","hooks":14}',
  ]);
}

void _healthFailed(_LogWriter w, DemoRun run) {
  w.line(
    'curl --fail --retry 6 --retry-delay 10 https://boardhop.relay.kammcs.com/healthz',
  );
  for (var i = 1; i <= 6; i++) {
    w.at(i / 7);
    w.all([
      'curl: (22) The requested URL returned error: 503',
      if (i < 6)
        'Warning: Problem : HTTP error. Will retry in 10 seconds. ${6 - i} retries left.',
    ]);
  }
  w.at(0.97);
  w.all([
    '{"status":"degraded","apns":"signing key not loaded","fcm":"ok","hooks":14}',
    '##[error]Health check failed: https://boardhop.relay.kammcs.com/healthz answered 503 six times in 60 s (apns: signing key not loaded).',
    'Rolling back to the previous image: boardhop-relay:2026.09.16-1',
    'docker compose up -d relay',
  ]);
}

void _tfx(_LogWriter w, DemoRun run) {
  w.all([
    'npx tfx-cli extension publish --manifest-globs vss-extension.json --share-with kammcs --token ***',
    'TFS Cross Platform Command Line Interface v0.21.1',
    'Copyright Microsoft Corporation',
  ]);
  w.at(0.4);
  w.line('Checking if this extension is already published');
  w.at(0.6);
  w.line('It is, update the extension');
  w.at(0.9);
  w.all([
    'Waiting for server to validate extension package...',
    'Sharing with kammcs.',
    '=== Completed operation: publish extension ===',
    ' - Packaging: /Users/runner/work/1/s/KammCS.boardhop-hooks-0.4.2.vsix',
    ' - Publishing: success',
    ' - Sharing: shared with kammcs',
  ]);
}

void _lint(_LogWriter w, DemoRun run) {
  w.all(['cd android && ./gradlew lint', 'Welcome to Gradle 8.14!']);
  w.at(0.4);
  w.line('> Task :app:lintAnalyzeRelease');
  w.at(0.9);
  w.all([
    '> Task :app:lintReportRelease',
    'Wrote HTML report to file:///Users/runner/work/1/s/build/app/reports/lint-results-release.html',
    'No issues found.',
    'BUILD SUCCESSFUL in 1m 31s',
  ]);
}

void _lintFailed(_LogWriter w, DemoRun run) {
  w.all(['cd android && ./gradlew lint', 'Welcome to Gradle 8.14!']);
  w.at(0.4);
  w.line('> Task :app:lintAnalyzeRelease');
  w.at(0.85);
  w.all([
    '> Task :app:lintReportRelease FAILED',
    '/Users/runner/work/1/s/android/app/src/main/AndroidManifest.xml:14: Error: POST_NOTIFICATIONS must be requested at runtime on API 33 and up [NotificationPermission]',
    '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
    '     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
    '',
    '##[error]Lint found 1 error, 0 warnings.',
    'FAILURE: Build failed with an exception.',
    'BUILD FAILED in 1m 23s',
  ]);
}
