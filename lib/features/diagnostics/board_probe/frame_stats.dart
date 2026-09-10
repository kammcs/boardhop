import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// One window of frame timings (all frames, or only frames during a drag).
class FrameWindow {
  final List<int> _build = <int>[];
  final List<int> _raster = <int>[];

  int get frames => _build.length;

  void add(FrameTiming t) {
    _build.add(t.buildDuration.inMicroseconds);
    _raster.add(t.rasterDuration.inMicroseconds);
  }

  void clear() {
    _build.clear();
    _raster.clear();
  }

  /// Frames where the UI thread or the raster thread blew the budget, the
  /// same rule DevTools uses to flag a frame as janky.
  int janky(Duration budget) {
    final b = budget.inMicroseconds;
    var n = 0;
    for (var i = 0; i < _build.length; i++) {
      if (_build[i] > b || _raster[i] > b) n++;
    }
    return n;
  }

  static double _percentile(List<int> xs, double q) {
    if (xs.isEmpty) return 0;
    final sorted = List<int>.of(xs)..sort();
    final k = ((sorted.length - 1) * q).round();
    return sorted[k] / 1000;
  }

  static double _max(List<int> xs) =>
      xs.isEmpty ? 0 : xs.reduce((a, b) => a > b ? a : b) / 1000;

  double get buildP90 => _percentile(_build, 0.9);
  double get rasterP90 => _percentile(_raster, 0.9);
  double get buildMax => _max(_build);
  double get rasterMax => _max(_raster);

  String summary(Duration budget) {
    if (frames == 0) return 'no frames';
    final j = janky(budget);
    final severe = janky(budget * 2);
    return 'frames $frames, janky $j (${(100 * j / frames).toStringAsFixed(1)}%), '
        'severe $severe, '
        'build p90 ${buildP90.toStringAsFixed(1)}ms max ${buildMax.toStringAsFixed(1)}ms, '
        'raster p90 ${rasterP90.toStringAsFixed(1)}ms max ${rasterMax.toStringAsFixed(1)}ms';
  }
}

/// Records frame timings from [SchedulerBinding.addTimingsCallback] for the
/// life of a probe page. Set [dragging] around a drag to get a second window
/// that covers only the interaction we care about.
class FrameStats {
  FrameStats({this.budget = const Duration(microseconds: 16667)});

  final Duration budget;
  final FrameWindow all = FrameWindow();
  final FrameWindow drag = FrameWindow();
  bool dragging = false;
  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void reset() {
    all.clear();
    drag.clear();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      all.add(t);
      if (dragging) drag.add(t);
    }
  }

  static String get buildMode => kReleaseMode
      ? 'release'
      : kProfileMode
      ? 'profile'
      : 'debug';
}
