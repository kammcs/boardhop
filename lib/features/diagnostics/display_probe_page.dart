import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/display_cutout.dart';
import '../../theme/theme.dart';

/// Phase 0's measuring tape for the iPhone Duo (research/23 §5).
///
/// Everything the layout could possibly key off, on one page, refreshed on
/// every `didChangeMetrics`: what Flutter believes about the window
/// (`MediaQuery`), and what iOS answers on the display channel (the
/// interface orientation, the reserved regions with their margins, the
/// vertical bar edge and the hinge). "Copy as JSON" puts the lot on the
/// clipboard so a pose can be recorded in one step.
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
  DisplayRegions? _regions;
  BarEdge? _barEdge;
  HingeState? _hinge;
  String? _orientation;

  /// Bumped on every metrics change, so a fold that leaves the window size
  /// alone can still be told apart from one that does not.
  int _metricsChanges = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _metricsChanges++;
    _refresh();
  }

  Future<void> _refresh() async {
    final regions = await DisplayCutout.regions();
    final barEdge = await DisplayCutout.verticalBarEdge();
    final hinge = await DisplayCutout.hinge();
    final orientation = await DisplayCutout.side();
    if (!mounted) return;
    setState(() {
      _regions = regions;
      _barEdge = barEdge;
      _hinge = hinge;
      _orientation = orientation.name;
    });
  }

  /// Everything on the page, as one JSON object.
  Map<String, Object?> _asJson(BuildContext context) {
    final media = MediaQuery.of(context);
    Map<String, Object?> insets(EdgeInsets e) => {
      'left': e.left,
      'top': e.top,
      'right': e.right,
      'bottom': e.bottom,
    };
    return {
      'metricsChanges': _metricsChanges,
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
            'bounds': {
              'left': f.bounds.left,
              'top': f.bounds.top,
              'right': f.bounds.right,
              'bottom': f.bounds.bottom,
            },
          },
      ],
      'channel': {
        'cutoutSide': _orientation,
        'supported': _regions?.supported,
        'verticalBarEdge': _barEdge?.name,
        'hinge': {
          'status': _hinge?.status.name,
          'angle': _hinge?.angle,
          'updates': _hinge?.updates,
          'view': _hinge?.view,
        },
        'reservedRegions': [
          for (final r in _regions?.regions ?? const <ReservedRegion>[])
            {
              'kind': r.kind.name,
              'active': r.active,
              'source': r.source,
              'rect': {
                'left': r.rect.left,
                'top': r.rect.top,
                'right': r.rect.right,
                'bottom': r.rect.bottom,
                'width': r.rect.width,
                'height': r.rect.height,
              },
              'margins': insets(r.margins),
            },
        ],
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final regions = _regions?.regions ?? const <ReservedRegion>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Display (Duo phase 0)'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: 'Copy as JSON',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              final json = const JsonEncoder.withIndent(
                '  ',
              ).convert(_asJson(context));
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
        child: ListView(
          padding: Spacing.page,
          children: [
            _Section(
              title: 'MediaQuery',
              rows: [
                ('size', '${_n(media.size.width)} x ${_n(media.size.height)}'),
                ('breakpoint', Breakpoint.fromWidth(media.size.width).name),
                ('orientation', media.orientation.name),
                ('devicePixelRatio', _n(media.devicePixelRatio)),
                ('padding', _insets(media.padding)),
                ('viewPadding', _insets(media.viewPadding)),
                ('viewInsets', _insets(media.viewInsets)),
                ('metrics changes', '$_metricsChanges'),
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
                ('interfaceOrientation (cutout side)', _orientation ?? '…'),
                ('supported', '${_regions?.supported ?? false}'),
                ('verticalBarEdge', _barEdge?.name ?? '…'),
                (
                  'hinge',
                  _hinge == null
                      ? '…'
                      : '${_hinge!.status.name}'
                            '${_hinge!.angle == null ? '' : ' at ${_n(_hinge!.angle!)} rad'}',
                ),
                (
                  'hinge updates / view',
                  _hinge == null
                      ? '…'
                      : '${_hinge!.updates} · ${_hinge!.view ?? '-'}',
                ),
                ('folds', '${_regions?.folds ?? false}'),
              ],
            ),
            _Section(
              title: 'reservedRegions (${regions.length})',
              rows: [
                if (regions.isEmpty) ('none', 'nothing reserved, or not asked'),
                for (final r in regions) ...[
                  (
                    '${r.kind.name}${r.active ? ' (active)' : ' (inactive)'}',
                    '${_n(r.rect.left)}, ${_n(r.rect.top)} '
                        '${_n(r.rect.width)} x ${_n(r.rect.height)}',
                  ),
                  ('  margins / source', '${_insets(r.margins)} · ${r.source}'),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _n(double v) => v.toStringAsFixed(1);

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
                      child: Text(value, style: BoardhopTheme.codeStyle(context)),
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
