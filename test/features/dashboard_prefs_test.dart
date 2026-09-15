import 'package:boardhop/features/dashboards/dashboard_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const org = 'puremedia';
const project = 'DevOps Mobile App';
const other = 'CloudCover 2.0';
const dashboardId = '985ff75c-bdf6-4b2d-a2b0-0ef63431e6ec';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('nothing is remembered on a fresh install', () async {
    expect(await DashboardPrefs.lastDashboard(org, project), isNull);
  });

  test('remembers the dashboard last opened in a project', () async {
    await DashboardPrefs.setLastDashboard(org, project, dashboardId);
    expect(await DashboardPrefs.lastDashboard(org, project), dashboardId);
  });

  test('the memory is per project, not per organization', () async {
    await DashboardPrefs.setLastDashboard(org, project, dashboardId);
    expect(await DashboardPrefs.lastDashboard(org, other), isNull);

    await DashboardPrefs.setLastDashboard(org, other, 'another-id');
    expect(await DashboardPrefs.lastDashboard(org, project), dashboardId);
    expect(await DashboardPrefs.lastDashboard(org, other), 'another-id');
  });

  test('an empty id is not remembered', () async {
    await DashboardPrefs.setLastDashboard(org, project, dashboardId);
    await DashboardPrefs.setLastDashboard(org, project, '');
    expect(await DashboardPrefs.lastDashboard(org, project), dashboardId);
  });

  test('the Team overview clears the memory: it has no id', () async {
    await DashboardPrefs.setLastDashboard(org, project, dashboardId);
    await DashboardPrefs.clearLastDashboard(org, project);
    expect(await DashboardPrefs.lastDashboard(org, project), isNull);
  });
}
