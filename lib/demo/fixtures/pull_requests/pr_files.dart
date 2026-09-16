/// The files each demo pull request changes, as the base (merge base with
/// `main`) and the source branch tip. Real-looking Boardhop code, so the
/// diff page has something worth reading in a screenshot.
library;

/// One changed file: its path, `edit` / `add` / `delete`, and both sides.
class DemoFileChange {
  const DemoFileChange(
    this.path, {
    this.changeType = 'edit',
    this.oldText = '',
    this.newText = '',
  });

  final String path;
  final String changeType;
  final String oldText;
  final String newText;
}

// ---------------------------------------------------------------------------
// !412 Side-by-side diff on iPad — the main screenshot.

/// The file the store screenshot opens.
const kSplitDiffPath = '/lib/features/pull_requests/diff/split_diff_view.dart';

/// The line of the new side the review thread hangs on.
const kSplitDiffThreadLine = 'bool _syncing = false;';

const _splitDiffOld = r'''import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'diff_model.dart';
import 'highlighter.dart';

/// The base and the change next to each other, one row per line pair.
class SplitDiffView extends StatefulWidget {
  const SplitDiffView({
    super.key,
    required this.rows,
    required this.oldRuns,
    required this.newRuns,
    this.minPaneWidth = 360,
  });

  final List<SplitRow> rows;
  final List<List<CodeRun>> oldRuns;
  final List<List<CodeRun>> newRuns;
  final double minPaneWidth;

  @override
  State<SplitDiffView> createState() => _SplitDiffViewState();
}

class _SplitDiffViewState extends State<SplitDiffView> {
  final _left = ScrollController();
  final _right = ScrollController();

  // TODO(marcus): keep both panes in step (#1266).

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.boardhopColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pane = constraints.maxWidth / 2;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: pane,
              child: _Pane(
                controller: _left,
                rows: widget.rows,
                side: DiffSide.left,
                runs: widget.oldRuns,
                tint: colors.diffRemoved,
              ),
            ),
            VerticalDivider(width: 1, color: colors.divider),
            Expanded(
              child: _Pane(
                controller: _right,
                rows: widget.rows,
                side: DiffSide.right,
                runs: widget.newRuns,
                tint: colors.diffAdded,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({
    required this.controller,
    required this.rows,
    required this.side,
    required this.runs,
    required this.tint,
  });

  final ScrollController controller;
  final List<SplitRow> rows;
  final DiffSide side;
  final List<List<CodeRun>> runs;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final code = BoardhopTheme.codeStyle(context);
    return ListView.builder(
      controller: controller,
      itemCount: rows.length,
      itemExtent: DiffMetrics.lineHeight,
      itemBuilder: (context, i) {
        final line = rows[i].lineOn(side);
        return ColoredBox(
          color: rows[i].isChangedOn(side) ? tint : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: DiffMetrics.gutterWidth,
                child: Text(
                  line == null ? '' : '$line',
                  textAlign: TextAlign.end,
                  style: code.copyWith(color: context.boardhopColors.muted),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: line == null
                    ? const SizedBox.shrink()
                    : Text.rich(CodeHighlighter.span(runs[line - 1], code)),
              ),
            ],
          ),
        );
      },
    );
  }
}
''';

const _splitDiffNew = r'''import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'diff_model.dart';
import 'highlighter.dart';

/// The base and the change next to each other, one row per line pair, for
/// iPad and other wide windows (#1238).
class SplitDiffView extends StatefulWidget {
  const SplitDiffView({
    super.key,
    required this.rows,
    required this.oldRuns,
    required this.newRuns,
    this.minPaneWidth = 320,
    this.onTapLine,
  });

  final List<SplitRow> rows;
  final List<List<CodeRun>> oldRuns;
  final List<List<CodeRun>> newRuns;
  final double minPaneWidth;
  final void Function(DiffSide side, int line)? onTapLine;

  @override
  State<SplitDiffView> createState() => _SplitDiffViewState();
}

class _SplitDiffViewState extends State<SplitDiffView> {
  final _left = ScrollController();
  final _right = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _left.addListener(() => _follow(_left, _right));
    _right.addListener(() => _follow(_right, _left));
  }

  /// Moves [follower] to where [leader] is, ignoring its echo.
  void _follow(ScrollController leader, ScrollController follower) {
    if (_syncing || !follower.hasClients) return;
    _syncing = true;
    follower.jumpTo(
      leader.offset.clamp(0.0, follower.position.maxScrollExtent),
    );
    _syncing = false;
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.boardhopColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final pane = (constraints.maxWidth / 2).clamp(
          widget.minPaneWidth,
          double.infinity,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: pane,
              child: _Pane(
                controller: _left,
                rows: widget.rows,
                side: DiffSide.left,
                runs: widget.oldRuns,
                tint: colors.diffRemoved,
                onTapLine: widget.onTapLine,
              ),
            ),
            VerticalDivider(width: 1, color: colors.divider),
            Expanded(
              child: _Pane(
                controller: _right,
                rows: widget.rows,
                side: DiffSide.right,
                runs: widget.newRuns,
                tint: colors.diffAdded,
                onTapLine: widget.onTapLine,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({
    required this.controller,
    required this.rows,
    required this.side,
    required this.runs,
    required this.tint,
    this.onTapLine,
  });

  final ScrollController controller;
  final List<SplitRow> rows;
  final DiffSide side;
  final List<List<CodeRun>> runs;
  final Color tint;
  final void Function(DiffSide side, int line)? onTapLine;

  @override
  Widget build(BuildContext context) {
    final code = BoardhopTheme.codeStyle(context);
    return ListView.builder(
      controller: controller,
      itemCount: rows.length,
      itemExtent: DiffMetrics.lineHeight,
      itemBuilder: (context, i) {
        final line = rows[i].lineOn(side);
        return ColoredBox(
          color: rows[i].isChangedOn(side) ? tint : Colors.transparent,
          child: Row(
            children: [
              InkWell(
                onTap: line == null ? null : () => onTapLine?.call(side, line),
                child: SizedBox(
                  width: DiffMetrics.gutterWidth,
                  child: Text(
                    line == null ? '' : '$line',
                    textAlign: TextAlign.end,
                    style: code.copyWith(color: context.boardhopColors.muted),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: line == null
                    ? const SizedBox.shrink()
                    : Text.rich(CodeHighlighter.span(runs[line - 1], code)),
              ),
            ],
          ),
        );
      },
    );
  }
}
''';

const _diffPageOld = r'''  /// Side by side from the expanded breakpoint, unless the reader chose.
  bool get _sideBySideNow => _sideBySide ?? false;

  Widget _diff(BuildContext context, LineDiffResult diff) {
    return DiffView(
      diff: diff,
      oldRuns: _oldRuns,
      newRuns: _newRuns,
      threads: _threads,
      controller: _nav,
      onTapLine: _openComposer,
    );
  }
''';

const _diffPageNew = r'''  /// Side by side from the expanded breakpoint, unless the reader chose.
  bool get _sideBySideNow =>
      _sideBySide ?? (context.breakpoint == Breakpoint.expanded);

  Widget _diff(BuildContext context, LineDiffResult diff) {
    if (_sideBySideNow) {
      return SplitDiffView(
        rows: SplitRow.align(diff),
        oldRuns: _oldRuns,
        newRuns: _newRuns,
        onTapLine: (side, line) => _openComposer(
          DiffAnchor(line: line, leftSide: side == DiffSide.left),
        ),
      );
    }
    return DiffView(
      diff: diff,
      oldRuns: _oldRuns,
      newRuns: _newRuns,
      threads: _threads,
      controller: _nav,
      onTapLine: _openComposer,
    );
  }
''';

const _diffPrefsOld =
    r'''import 'package:shared_preferences/shared_preferences.dart';

/// The diff page's remembered layout choices, per account.
abstract final class DiffPrefs {
  static const _wrapKey = 'diff.wrap';

  static Future<bool> wrap(String account) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_wrapKey.$account') ?? false;
  }

  static Future<void> setWrap(String account, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_wrapKey.$account', value);
  }
}
''';

const _diffPrefsNew =
    r'''import 'package:shared_preferences/shared_preferences.dart';

/// The diff page's remembered layout choices, per account.
abstract final class DiffPrefs {
  static const _wrapKey = 'diff.wrap';
  static const _sideBySideKey = 'diff.sideBySide';

  static Future<bool> wrap(String account) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_wrapKey.$account') ?? false;
  }

  static Future<void> setWrap(String account, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_wrapKey.$account', value);
  }

  /// Null until the reader picks a layout: the window decides until then.
  static Future<bool?> sideBySide(String account) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_sideBySideKey.$account');
  }

  static Future<void> setSideBySide(String account, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_sideBySideKey.$account', value);
  }
}
''';

const _breakpointsOld = r'''import 'package:flutter/widgets.dart';

/// Window size classes, from the shortest side a layout has to fit.
enum Breakpoint {
  compact,
  medium,
  expanded;

  static Breakpoint of(double width) {
    if (width >= 840) return expanded;
    if (width >= 600) return medium;
    return compact;
  }
}

extension BreakpointContext on BuildContext {
  Breakpoint get breakpoint => Breakpoint.of(MediaQuery.sizeOf(this).width);
}
''';

const _breakpointsNew = r'''import 'package:flutter/widgets.dart';

/// Window size classes, from the shortest side a layout has to fit.
enum Breakpoint {
  compact,
  medium,
  expanded;

  /// iPad Pro 11" in portrait is 834 pt wide and should get two panes.
  static const expandedMinWidth = 820.0;

  static Breakpoint of(double width) {
    if (width >= expandedMinWidth) return expanded;
    if (width >= 600) return medium;
    return compact;
  }
}

extension BreakpointContext on BuildContext {
  Breakpoint get breakpoint => Breakpoint.of(MediaQuery.sizeOf(this).width);
}
''';

const _splitTestNew =
    r'''import 'package:boardhop/features/pull_requests/diff/diff_model.dart';
import 'package:boardhop/features/pull_requests/diff/split_diff_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump.dart';

void main() {
  testWidgets('both panes scroll together', (tester) async {
    final diff = LineDiff.compute(longFile(400), longFile(400, edit: 120));
    await pumpThemed(
      tester,
      SplitDiffView(
        rows: SplitRow.align(diff),
        oldRuns: plainRuns(diff.oldLines),
        newRuns: plainRuns(diff.newLines),
      ),
      size: const Size(1366, 1024),
    );

    await tester.fling(find.byType(ListView).first, const Offset(0, -900), 2400);
    await tester.pumpAndSettle();

    final lists = tester.widgetList<ListView>(find.byType(ListView)).toList();
    expect(
      lists[1].controller!.offset,
      moreOrLessEquals(lists[0].controller!.offset),
    );
  });

  testWidgets('a tap on the left gutter anchors the original side', (
    tester,
  ) async {
    DiffSide? tapped;
    final diff = LineDiff.compute('a\nb\nc\n', 'a\nB\nc\n');
    await pumpThemed(
      tester,
      SplitDiffView(
        rows: SplitRow.align(diff),
        oldRuns: plainRuns(diff.oldLines),
        newRuns: plainRuns(diff.newLines),
        onTapLine: (side, _) => tapped = side,
      ),
    );

    await tester.tap(find.text('2').first);
    expect(tapped, DiffSide.left);
  });
}
''';

/// !412's five files, the main one first.
const splitDiffFiles = [
  DemoFileChange(
    kSplitDiffPath,
    oldText: _splitDiffOld,
    newText: _splitDiffNew,
  ),
  DemoFileChange(
    '/lib/features/pull_requests/pr_file_diff_page.dart',
    oldText: _diffPageOld,
    newText: _diffPageNew,
  ),
  DemoFileChange(
    '/lib/features/pull_requests/diff/diff_prefs.dart',
    oldText: _diffPrefsOld,
    newText: _diffPrefsNew,
  ),
  DemoFileChange(
    '/lib/core/layout/breakpoints.dart',
    oldText: _breakpointsOld,
    newText: _breakpointsNew,
  ),
  DemoFileChange(
    '/test/features/split_diff_view_test.dart',
    changeType: 'add',
    newText: _splitTestNew,
  ),
];

// ---------------------------------------------------------------------------
// !415 Re-register the device when the APNs token rotates (boardhop-relay).

const _apnsOld = r'''import 'package:shelf/shelf.dart';

import '../store/device_store.dart';
import 'apns_client.dart';

/// Sends one notification to every device registered for the user.
class ApnsSender {
  ApnsSender(this._client, this._devices);

  final ApnsClient _client;
  final DeviceStore _devices;

  Future<void> send(String userId, Map<String, Object?> payload) async {
    for (final device in await _devices.forUser(userId)) {
      final result = await _client.push(device.token, payload);
      if (result.status == 410) {
        await _devices.remove(device.token);
      }
    }
  }
}
''';

const _apnsNew = r'''import 'package:shelf/shelf.dart';

import '../store/device_store.dart';
import 'apns_client.dart';

/// Sends one notification to every device registered for the user.
class ApnsSender {
  ApnsSender(this._client, this._devices);

  final ApnsClient _client;
  final DeviceStore _devices;

  Future<void> send(String userId, Map<String, Object?> payload) async {
    for (final device in await _devices.forUser(userId)) {
      final result = await _client.push(device.token, payload);
      switch (result.status) {
        case 410:
          // Unregistered: the app sends its new token on next launch.
          await _devices.markStale(device.token, since: result.timestamp);
        case 400 when result.reason == 'BadDeviceToken':
          await _devices.remove(device.token);
        case 200:
          await _devices.touch(device.token);
      }
    }
  }
}
''';

const _registerOld = r'''  Future<Response> register(Request request) async {
    final body = await readJson(request);
    final token = body['token'] as String;
    await devices.add(userId(request), token, platform: body['platform']);
    return Response.ok('registered');
  }
''';

const _registerNew = r'''  Future<Response> register(Request request) async {
    final body = await readJson(request);
    final token = body['token'] as String;
    final previous = body['previousToken'] as String?;
    if (previous != null && previous != token) {
      await devices.replace(previous, token);
    } else {
      await devices.add(userId(request), token, platform: body['platform']);
    }
    return Response.ok('registered');
  }
''';

const apnsRotationFiles = [
  DemoFileChange(
    '/lib/src/push/apns_sender.dart',
    oldText: _apnsOld,
    newText: _apnsNew,
  ),
  DemoFileChange(
    '/lib/src/routes/devices.dart',
    oldText: _registerOld,
    newText: _registerNew,
  ),
];

// ---------------------------------------------------------------------------
// !409 Include the last working day in the burndown.

const _burndownOld = r'''/// Working days from the sprint's start up to, not including, its finish.
List<DateTime> workingDays(DateTime start, DateTime finish) {
  final days = <DateTime>[];
  for (var d = start; d.isBefore(finish); d = d.add(const Duration(days: 1))) {
    if (d.weekday <= DateTime.friday) days.add(d);
  }
  return days;
}
''';

const _burndownNew = r'''/// Working days from the sprint's start through its finish, inclusive: the
/// finish date is the last working day, not the day after it (#1252).
List<DateTime> workingDays(DateTime start, DateTime finish) {
  final days = <DateTime>[];
  for (var d = start; !d.isAfter(finish); d = d.add(const Duration(days: 1))) {
    if (d.weekday <= DateTime.friday) days.add(d);
  }
  return days;
}
''';

const _burndownTestNew =
    r'''import 'package:boardhop/features/dashboards/burndown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the finish date is a working day of the sprint', () {
    final days = workingDays(DateTime(2026, 9, 7), DateTime(2026, 9, 18));
    expect(days, hasLength(10));
    expect(days.last, DateTime(2026, 9, 18));
  });
}
''';

const burndownFiles = [
  DemoFileChange(
    '/lib/features/dashboards/burndown.dart',
    oldText: _burndownOld,
    newText: _burndownNew,
  ),
  DemoFileChange(
    '/test/features/dashboards/burndown_test.dart',
    changeType: 'add',
    newText: _burndownTestNew,
  ),
];

// ---------------------------------------------------------------------------
// !417 Floating liquid glass rail on iPad (draft).

const _railNew = r'''import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// The iPad navigation rail as a floating glass capsule over the content.
class GlassRail extends StatelessWidget {
  const GlassRail({super.key, required this.destinations, required this.index});

  final List<NavigationRailDestination> destinations;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: ClipRRect(
        borderRadius: Radii.capsule,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: NavigationRail(
            backgroundColor: context.boardhopColors.glass,
            destinations: destinations,
            selectedIndex: index,
          ),
        ),
      ),
    );
  }
}
''';

const glassRailFiles = [
  DemoFileChange(
    '/lib/features/shell/glass_rail.dart',
    changeType: 'add',
    newText: _railNew,
  ),
];

// ---------------------------------------------------------------------------
// !411 Hub provisions relay hooks per project (boardhop-extension).

const _planOld = r'''export const HOOK_KINDS = [
  'git.pullrequest.created',
  'git.pullrequest.updated',
  'ms.vss-code.git-pullrequest-comment-event',
] as const;
''';

const _planNew = r'''export const HOOK_KINDS = [
  'git.pullrequest.created',
  'git.pullrequest.updated',
  'ms.vss-code.git-pullrequest-comment-event',
  'ms.vss-pipelines.run-state-changed-event',
  'ms.vss-pipelinechecks-events.approval-pending',
] as const;

/// Subscriptions the hub creates for one project, one per hook kind.
export function planFor(projectId: string, relayUrl: string) {
  return HOOK_KINDS.map((eventType) => ({
    eventType,
    publisherInputs: { projectId },
    consumerInputs: { url: `${relayUrl}/hooks/${eventType}` },
  }));
}
''';

const hubFiles = [
  DemoFileChange('/src/plan.ts', oldText: _planOld, newText: _planNew),
];

// ---------------------------------------------------------------------------
// !414 Approve a waiting stage from the notification.

const _approveOld = r'''  Future<void> onAction(String actionId, Map<String, String> data) async {
    switch (actionId) {
      case 'open':
        await router.push(data['route']!);
    }
  }
''';

const _approveNew = r'''  Future<void> onAction(String actionId, Map<String, String> data) async {
    switch (actionId) {
      case 'open':
        await router.push(data['route']!);
      case 'approve':
        await pipelines.approve(
          data['org']!,
          data['project']!,
          data['approvalId']!,
          comment: 'Approved from a notification',
        );
    }
  }
''';

const approveFiles = [
  DemoFileChange(
    '/lib/features/notifications/push_actions.dart',
    oldText: _approveOld,
    newText: _approveNew,
  ),
];

// ---------------------------------------------------------------------------
// !406 @mention autocomplete ranks recent people first.

const _mentionOld = r'''  Future<List<IdentityRef>> people(String query) async {
    final members = await this.members();
    return [for (final m in members) if (_matches(m, query)) m];
  }
''';

const _mentionNew = r'''  Future<List<IdentityRef>> people(String query) async {
    final recent = await recents.list(org, project);
    final members = await this.members();
    final seen = <String>{};
    return [
      for (final m in [...recent, ...members])
        if (_matches(m, query) && seen.add(m.id ?? m.displayName)) m,
    ];
  }
''';

const mentionFiles = [
  DemoFileChange(
    '/lib/features/shared/mention/mention_sources.dart',
    oldText: _mentionOld,
    newText: _mentionNew,
  ),
];

// ---------------------------------------------------------------------------
// !418 Retry failed jobs from the run page (draft).

const _retryOld = r'''  List<Widget> actions(PipelineRun run) => [
    if (run.canCancel) CancelRunButton(run: run),
  ];
''';

const _retryNew = r'''  List<Widget> actions(PipelineRun run) => [
    if (run.canCancel) CancelRunButton(run: run),
    if (run.result == RunResult.failed)
      RetryStageButton(run: run, stages: run.failedStages),
  ];
''';

const retryFiles = [
  DemoFileChange(
    '/lib/features/pipelines/run_page.dart',
    oldText: _retryOld,
    newText: _retryNew,
  ),
];
