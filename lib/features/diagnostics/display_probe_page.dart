import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/display_environment.dart';
import '../../theme/theme.dart';

/// The measuring tape for the iPhone Duo (research/23).
///
/// Everything the layout could possibly key off, on one page: what Flutter
/// believes about the window (`MediaQuery`) and what iOS says on the
/// display channel (the interface orientation, the reserved regions with
/// their margins, the vertical bar edge and the hinge), plus what
/// [DisplayEnvironment] derives from them.
///
/// It reads [DisplayScope] rather than the channel, so it updates **by
/// itself** when the Runner pushes: folding the device with the page open
/// and nothing touched raises the push counter and flips the division
/// region to active. That is the phase 1 check (§9.2: a fold is invisible
/// to `MediaQuery`, so the counter next to it stays put). Pull down to
/// re-poll; "Copy as JSON" puts the lot on the clipboard so a pose can be
/// recorded in one step.
///
/// Diagnostics only (`AppConfig.diagnosticsEnabled`), like every other
/// probe, and it changes no layout: it only reports.
class DisplayProbePage extends StatefulWidget {
  const DisplayProbePage({super.key});

  @override
  State<DisplayProbePage> createState() => _DisplayProbePageState();
}

class _DisplayProbePageState extends State<DisplayProbePage>
    with WidgetsBindingObserver {
  /// Bumped on every metrics change, so a fold — which produces none — can
  /// be told apart from a rotation or a resize, which do.
  int _metricsChanges = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => setState(() => _metricsChanges++);

  /// Everything on the page, as one JSON object.
  Map<String, Object?> _asJson(BuildContext context) {
    final media = MediaQuery.of(context);
    final display = DisplayScope.of(context);
    Map<String, Object?> insets(EdgeInsets e) => {
      'left': e.left,
      'top': e.top,
      'right': e.right,
      'bottom': e.bottom,
    };
    Map<String, Object?>? rect(Rect? r) => r == null
        ? null
        : {
            'left': r.left,
            'top': r.top,
            'right': r.right,
            'bottom': r.bottom,
            'width': r.width,
            'height': r.height,
          };
    return {
      'metricsChanges': _metricsChanges,
      'pushes': display.pushes,
      'lastPush': display.lastPush?.toIso8601String(),
      'size': {'width': media.size.width, 'height': media.size.height},
      'devicePixelRatio': media.devicePixelRatio,
      'orientation': media.orientation.name,
      'breakpoint': Breakpoint.fromWidth(media.size.width).name,
      'padding': insets(media.padding),
      'viewPadding': insets(media.viewPadding),
      'viewInsets': insets(media.viewInsets),
      'textScale': media.textScaler.scale(14) / 14,
      'displayFeatures': [
        for (final f in media.displayFeatures)
          {
            'type': f.type.name,
            'state': f.state.name,
            'bounds': rect(f.bounds),
          },
      ],
      'derived': {
        'folds': display.folds,
        'crease': rect(display.crease),
        'creaseBand': rect(display.creaseBand),
        'creaseAxis': display.creaseAxis?.name,
        'halves': [for (final h in display.halves(media.size)) rect(h)],
        'railSide': display.railSide(Directionality.of(context))?.name,
        'compactPane': display.compactPane,
      },
      'channel': {
        'cutoutSide': display.cutoutSide.name,
        'supported': display.supported,
        'verticalBarEdge': display.barEdge.name,
        'hinge': {
          'status': display.hinge.status.name,
          'angle': display.hinge.angle,
          'updates': display.hinge.updates,
          'view': display.hinge.view,
        },
        'reservedRegions': [
          for (final r in display.regions.regions)
            {
              'kind': r.kind.name,
              'active': r.active,
              'source': r.source,
              'rect': rect(r.rect),
              'margins': insets(r.margins),
            },
        ],
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final display = DisplayScope.of(context);
    final regions = display.regions.regions;
    final halves = display.halves(media.size);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Display'),
        actions: [
          IconButton(
            tooltip: 'Copy as JSON',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              final json = const JsonEncoder.withIndent('  ')
                  .convert(_asJson(context));
              await Clipboard.setData(ClipboardData(text: json));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Display report copied')),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        // No refresh button (DESIGN): pull down to re-poll. Nothing here
        // needs it while the Runner is pushing, which is the point.
        child: RefreshIndicator(
          onRefresh: display.refresh,
          child: ListView(
            padding: Spacing.page,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _Section(
                title: 'Pushed from the Runner',
                rows: [
                  ('pushes received', '${display.pushes}'),
                  (
                    'last push',
                    display.lastPush == null
                        ? 'none yet'
                        : _time(display.lastPush!),
                  ),
                  ('metrics changes', '$_metricsChanges'),
                ],
              ),
              _Section(
                title: 'MediaQuery',
                rows: [
                  (
                    'size',
                    '${_n(media.size.width)} x ${_n(media.size.height)}',
                  ),
                  ('breakpoint', Breakpoint.fromWidth(media.size.width).name),
                  ('orientation', media.orientation.name),
                  ('devicePixelRatio', _n(media.devicePixelRatio)),
                  ('padding', _insets(media.padding)),
                  ('viewPadding', _insets(media.viewPadding)),
                  ('viewInsets', _insets(media.viewInsets)),
                ],
              ),
              _Section(
                title: 'displayFeatures (${media.displayFeatures.length})',
                rows: [
                  if (media.displayFeatures.isEmpty)
                    ('none', 'empty on iOS until flutter/flutter#192515 lands'),
                  for (final f in media.displayFeatures)
                    (
                      '${f.type.name} / ${f.state.name}',
                      '${_n(f.bounds.left)}, ${_n(f.bounds.top)} '
                          '${_n(f.bounds.width)} x ${_n(f.bounds.height)}',
                    ),
                ],
              ),
              _Section(
                title: 'Display channel',
                rows: [
                  (
                    'interfaceOrientation (cutout side)',
                    display.cutoutSide.name,
                  ),
                  ('supported', '${display.supported}'),
                  ('verticalBarEdge', display.barEdge.name),
                  (
                    'hinge',
                    '${display.hinge.status.name}'
                        '${display.hinge.angle == null ? '' : ' at ${_n(display.hinge.angle!)} rad'}',
                  ),
                  (
                    'hinge updates / view',
                    '${display.hinge.updates} · ${display.hinge.view ?? '-'}',
                  ),
                  ('folds', '${display.folds}'),
                ],
              ),
              _Section(
                title: 'Derived (DisplayEnvironment)',
                rows: [
                  ('crease', _rect(display.crease)),
                  ('creaseBand', _rect(display.creaseBand)),
                  ('creaseAxis', display.creaseAxis?.name ?? '-'),
                  (
                    'halves',
                    halves.isEmpty ? '-' : halves.map(_rect).join('   /   '),
                  ),
                  (
                    'railSide',
                    display.railSide(Directionality.of(context))?.name ?? '-',
                  ),
                  ('compactPane', '${display.compactPane}'),
                ],
              ),
              _Section(
                title: 'reservedRegions (${regions.length})',
                rows: [
                  if (regions.isEmpty)
                    ('none', 'nothing reserved, or not asked'),
                  for (final r in regions) ...[
                    (
                      '${r.kind.name}${r.active ? ' (active)' : ' (inactive)'}',
                      '${_n(r.rect.left)}, ${_n(r.rect.top)} '
                          '${_n(r.rect.width)} x ${_n(r.rect.height)}',
                    ),
                    (
                      '  margins / source',
                      '${_insets(r.margins)} · ${r.source}',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _n(double v) => v.toStringAsFixed(1);

  static String _rect(Rect? r) => r == null
      ? '-'
      : '${_n(r.left)}, ${_n(r.top)} ${_n(r.width)} x ${_n(r.height)}';

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.'
      '${t.millisecond.toString().padLeft(3, '0')}';

  static String _insets(EdgeInsets e) =>
      'l ${_n(e.left)}  t ${_n(e.top)}  r ${_n(e.right)}  b ${_n(e.bottom)}';
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        value,
                        style: BoardhopTheme.codeStyle(context),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
