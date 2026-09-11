import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/repositories/pipeline_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import 'widgets/pipeline_visuals.dart';

/// One timeline record's log, wrapped monospace lines with the service's
/// `##[error]` / `##[warning]` / `##[section]` accents; timestamps can be
/// hidden.
class PipelineLogPage extends StatefulWidget {
  const PipelineLogPage({
    super.key,
    required this.org,
    required this.project,
    required this.buildId,
    required this.logId,
    this.title,
  });

  final String org;
  final String project;
  final int buildId;
  final int logId;
  final String? title;

  @override
  State<PipelineLogPage> createState() => _PipelineLogPageState();
}

class _PipelineLogPageState extends State<PipelineLogPage> {
  List<String> _lines = const [];
  String? _error;
  bool _loading = false;
  bool _timestamps = false;
  bool _wrap = true;
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lines = await context.read<PipelineRepository>().log(
        widget.org,
        widget.project,
        widget.buildId,
        widget.logId,
      );
      if (mounted) setState(() => _lines = lines);
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _jumpToEnd() {
    if (!_controller.hasClients) return;
    _controller.jumpTo(_controller.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final style = BoardhopTheme.codeStyle(context).copyWith(fontSize: 11.5);
    final errors = _lines.where((l) => l.contains('##[error]')).length;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title ?? 'Log', overflow: TextOverflow.ellipsis),
            Text(
              '${_lines.length} lines${errors > 0 ? ' · $errors errors' : ''}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: _timestamps ? 'Hide timestamps' : 'Show timestamps',
            icon: Icon(
              _timestamps ? Icons.schedule : Icons.schedule_outlined,
              color: _timestamps ? scheme.primary : null,
            ),
            onPressed: () => setState(() => _timestamps = !_timestamps),
          ),
          IconButton(
            tooltip: _wrap ? 'No wrapping' : 'Wrap lines',
            icon: Icon(Icons.wrap_text, color: _wrap ? scheme.primary : null),
            onPressed: () => setState(() => _wrap = !_wrap),
          ),
          IconButton(
            tooltip: 'Jump to end',
            icon: const Icon(Icons.vertical_align_bottom),
            onPressed: _lines.isEmpty ? null : _jumpToEnd,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            ListTile(
              leading: Icon(Icons.error_outline, color: scheme.error),
              title: Text(_error!),
            ),
          Expanded(
            child: ColoredBox(
              color: colors.codeBackground,
              child: SelectionArea(
                child: _wrap
                    ? _list(style)
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: _widest(style),
                          child: _list(style),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _widest(TextStyle style) {
    var max = 0;
    for (final l in _lines) {
      final n = (_timestamps ? l : stripLogTimestamp(l)).length;
      if (n > max) max = n;
    }
    return max * (style.fontSize ?? 12) * 0.62 + 40 + Spacing.lg * 2;
  }

  Widget _list(TextStyle style) => ListView.builder(
    controller: _controller,
    padding: const EdgeInsets.symmetric(
      horizontal: Spacing.lg,
      vertical: Spacing.sm,
    ),
    itemCount: _lines.length,
    itemBuilder: (context, i) {
      final raw = _lines[i];
      final text = _timestamps ? raw : stripLogTimestamp(raw);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${i + 1}',
              textAlign: TextAlign.right,
              style: style.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              text.isEmpty ? ' ' : text,
              style: logLineStyle(context, style, raw),
              softWrap: _wrap,
              overflow: _wrap ? TextOverflow.visible : TextOverflow.clip,
            ),
          ),
        ],
      );
    },
  );
}
