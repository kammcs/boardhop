import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/pull_request.dart';
import '../../data/repositories/pr_diff_source.dart';
import '../../data/repositories/pull_request_repository.dart';
import 'diff/diff_model.dart';
import 'diff/diff_view.dart';
import 'diff/highlighter.dart';

/// One file of a pull request iteration as a unified diff (spike F5), with
/// the threads read for that iteration so they sit on their tracked lines,
/// and a tap-to-comment gutter that posts a new anchored thread.
class PrFileDiffPage extends StatefulWidget {
  const PrFileDiffPage({
    super.key,
    required this.org,
    required this.id,
    required this.path,
    this.iteration,
  });

  final String org;
  final int id;
  final String path;
  final int? iteration;

  @override
  State<PrFileDiffPage> createState() => _PrFileDiffPageState();
}

class _PrFileDiffPageState extends State<PrFileDiffPage> {
  PullRequest? _pr;
  PrRef? _ref;
  int? _iteration;
  PrFileChange? _change;
  LineDiffResult? _diff;
  List<List<CodeRun>> _oldRuns = const [];
  List<List<CodeRun>> _newRuns = const [];
  List<PrThread> _threads = const [];
  int? _composerLine;
  String? _error;
  bool _loading = false;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<PullRequestRepository>();
    final source = PrDiffSource(context.read<AdoClient>());
    try {
      final pr = _pr ?? await repo.get(widget.org, widget.id);
      final ref = repo.ref(widget.org, pr);
      final iterations = await source.iterations(ref);
      if (iterations.isEmpty) {
        setState(() => _error = 'This pull request has no iterations.');
        return;
      }
      final it = iterations.firstWhere(
        (i) => i.id == widget.iteration,
        orElse: () => iterations.last,
      );
      final changes = await source.changes(ref, it.id);
      final change = changes.firstWhere(
        (c) => c.path == widget.path,
        orElse: () => PrFileChange(
          path: widget.path,
          changeType: 'edit',
          changeTrackingId: 0,
        ),
      );
      final oldText = change.isAdd
          ? ''
          : await source.fileAt(
              ref,
              change.originalPath ?? change.path,
              it.commonCommit,
            );
      final newText = change.isDelete
          ? ''
          : await source.fileAt(ref, change.path, it.sourceCommit);
      final threads = await source.threads(
        ref,
        iteration: it.id,
        baseIteration: 0,
      );
      if (!mounted) return;
      final brightness = Theme.of(context).brightness;
      final language = CodeHighlighter.languageFor(widget.path);
      setState(() {
        _pr = pr;
        _ref = ref;
        _iteration = it.id;
        _change = change;
        _diff = LineDiff.compute(oldText, newText);
        _oldRuns = CodeHighlighter.highlightLines(
          oldText,
          language,
          brightness,
        );
        _newRuns = CodeHighlighter.highlightLines(
          newText,
          language,
          brightness,
        );
        _threads = [
          for (final t in threads)
            if (t.filePath == widget.path) t,
        ];
      });
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _post(int line, String text) async {
    final pr = _pr;
    final ref = _ref;
    if (pr == null || ref == null) return;
    setState(() => _posting = true);
    final repo = context.read<PullRequestRepository>();
    final source = PrDiffSource(context.read<AdoClient>());
    try {
      await repo.addThread(
        widget.org,
        pr,
        content: text,
        filePath: widget.path,
        line: line,
        changeTrackingId: _change?.changeTrackingId,
        iteration: _iteration,
      );
      final threads = await source.threads(
        ref,
        iteration: _iteration!,
        baseIteration: 0,
      );
      if (!mounted) return;
      setState(() {
        _threads = [
          for (final t in threads)
            if (t.filePath == widget.path) t,
        ];
        _composerLine = null;
      });
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final diff = _diff;
    final name = widget.path.substring(widget.path.lastIndexOf('/') + 1);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, overflow: TextOverflow.ellipsis),
            Text(
              diff == null
                  ? widget.path
                  : 'iteration $_iteration · +${diff.added} −${diff.removed} · ${_threads.length} threads',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
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
          if (_loading || _posting) const LinearProgressIndicator(),
          if (_error != null)
            ListTile(
              leading: Icon(Icons.error_outline, color: scheme.error),
              title: Text(_error!),
            ),
          Expanded(
            child: diff == null
                ? (_loading
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : const SizedBox.shrink())
                : DiffView(
                    diff: diff,
                    oldRuns: _oldRuns,
                    newRuns: _newRuns,
                    threads: _threads,
                    composerLine: _composerLine,
                    posting: _posting,
                    onGutterTap: _pr?.isActive == true
                        ? (line) => setState(
                            () => _composerLine = _composerLine == line
                                ? null
                                : line,
                          )
                        : null,
                    onCancelComposer: () =>
                        setState(() => _composerLine = null),
                    onPost: _post,
                  ),
          ),
        ],
      ),
    );
  }
}
