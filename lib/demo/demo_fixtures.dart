import 'package:flutter/foundation.dart';

import 'demo_backend.dart';
import 'fixtures/activity_fixtures.dart';
import 'fixtures/core_fixtures.dart';
import 'fixtures/dashboard_fixtures.dart';
import 'fixtures/pipeline_fixtures.dart';
import 'fixtures/pull_request_fixtures.dart';
import 'fixtures/work_fixtures.dart';

/// The demo mode's backend with every area's fixtures registered.
/// [projectPicture] is the Boardhop project's avatar (the app icon).
DemoBackend buildDemoBackend({Uint8List? projectPicture}) {
  final backend = DemoBackend();
  registerCoreFixtures(backend, projectPicture: projectPicture);
  // Dashboards first: their saved-query routes name exact ids, while the
  // work area's match any GUID.
  registerDashboardFixtures(backend);
  registerWorkFixtures(backend);
  registerPullRequestFixtures(backend);
  registerPipelineFixtures(backend);
  registerActivityFixtures(backend);
  return backend;
}
