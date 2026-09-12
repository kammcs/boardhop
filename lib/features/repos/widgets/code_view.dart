import 'dart:math';

import 'package:flutter/material.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../../theme/theme.dart';
import '../../pull_requests/diff/highlighter.dart';

/// A whole file as numbered, highlighted lines. Long lines pan under one
/// horizontal scroll view unless [wrap] is on. Rows are laid out lazily on
/// a [SuperListView] so a jump to a line later lands exactly (spike F5).
class CodeView extends StatefulWidget {
  const CodeView({
    super.key,
    required this.lines,
    this.wrap = false,
    this.fontSize = 12,
    this.highlightLine,
  });

  final List<List<CodeRun>> lines;
  final bool wrap;
  final double fontSize;

  /// 1-based line to tint (search hit, deep link).
  final int? highlightLine;

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  final _listController = ListController();
  final _vertical = ScrollController();
  double _charWidth = 7;
  int _maxChars = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _measure();
  }

  @override
  void didUpdateWidget(CodeView old) {
    super.didUpdateWidget(old);
    if (old.lines != widget.lines || old.fontSize != widget.fontSize) {
      _measure();
    }
    if (old.highlightLine != widget.highlightLine) _jump();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jump());
  }

  @override
  void dispose() {
    _listController.dispose();
    _vertical.dispose();
    super.dispose();
  }

  TextStyle _style(BuildContext context) =>
      BoardhopTheme.codeStyle(context)
          .copyWith(fontSize: widget.fontSize, height: 1.45);

  void _measure() {
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: _style(context)),
      textDirection: TextDirection.ltr,
    )..layout();
    _charWidth = painter.width;
    var maxChars = 0;
    for (final line in widget.lines) {
      var n = 0;
      for (final r in line) {
        n += r.text.length;
      }
      if (n > maxChars) maxChars = n;
    }
    _maxChars = maxChars;
  }

  void _jump() {
    final line = widget.highlightLine;
    if (line == null || line < 1 || line > widget.lines.length) return;
    _listController.jumpToItem(
      index: line - 1,
      scrollController: _vertical,
      alignment: 0.3,
    );
  }

  double get _gutterWidth {
    final digits = max(2, widget.lines.length.toString().length);
    return digits * _charWidth + Spacing.md * 2;
  }

  @override
  Widget build(BuildContext context) {
    final style = _style(context);
    final gutter = _gutterWidth;
    final list = SuperListView.builder(
      controller: _vertical,
      listController: _listController,
      itemCount: widget.lines.length,
      padding: scrollEndPadding(context),
      itemBuilder: (context, i) => _LineView(
        number: i + 1,
        runs: widget.lines[i],
        style: style,
        gutterWidth: gutter,
        wrap: widget.wrap,
        highlighted: widget.highlightLine == i + 1,
      ),
    );
    if (widget.wrap) return list;
    final width = gutter + _maxChars * _charWidth + Spacing.lg * 2;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: max(width, constraints.maxWidth), child: list),
      ),
    );
  }
}

class _LineView extends StatelessWidget {
  const _LineView({
    required this.number,
    required this.runs,
    required this.style,
    required this.gutterWidth,
    required this.wrap,
    required this.highlighted,
  });

  final int number;
  final List<CodeRun> runs;
  final TextStyle style;
  final double gutterWidth;
  final bool wrap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: highlighted
          ? scheme.tertiaryContainer.withValues(alpha: 0.6)
          : Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutterWidth,
            child: Padding(
              padding: const EdgeInsets.only(right: Spacing.md),
              child: Text(
                '$number',
                textAlign: TextAlign.right,
                style: style.copyWith(color: scheme.outline),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: Spacing.lg),
              child: Text.rich(
                TextSpan(
                  style: style,
                  children: [
                    for (final r in runs)
                      TextSpan(text: r.text, style: r.style),
                    if (runs.isEmpty) const TextSpan(text: ' '),
                  ],
                ),
                softWrap: wrap,
                overflow: TextOverflow.visible,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
