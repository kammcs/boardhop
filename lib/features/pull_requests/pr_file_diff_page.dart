import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/pull_request.dart';
import '../../data/repositories/pr_diff_source.dart';
import '../../data/repositories/pull_request_repository.dart';
import '../shared/account_scope.dart';
import 'diff/diff_model.dart';
import 'diff/diff_view.dart';
import 'diff/highlighter.dart';
import 'pull_request_detail_page.dart' show IterationPicker;

/// One file of a pull request iteration as a unified diff (spike F5), with
/// the threads read for that iteration so they sit on their tracked lines,
/// a tap-to-comment gutter that posts a new anchored thread, replies and
/// thread status under each thread, and an iteration picker in the bar.
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
  List<PrIteration> _iterations = const [];
  int? _iteration;
  PrFileChange? _change;
  LineDiffResult? _diff;

  /// New-side text of the file at the shown iteration (suggestion apply).
  String _newText = '';
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
    _iteration = widget.iteration;
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
      final iterations = _iterations.isEmpty
          ? await source.iterations(ref)
          : _iterations;
      if (iterations.isEmpty) {
        setState(() => _error = 'This pull request has no iterations.');
        return;
      }
      final it = iterations.firstWhere(
        (i) => i.id == _iteration,
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
        _iterations = iterations;
        _iteration = it.id;
        _change = change;
        _composerLine = null;
        _newText = newText;
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
        _threads = _forThisFile(threads);
      });
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

  List<PrThread> _forThisFile(List<PrThread> threads) => [
    for (final t in threads)
      if (t.filePath == widget.path) t,
  ];

  void _selectIteration(int id) {
    if (id == _iteration) return;
    setState(() => _iteration = id);
    _load();
  }

  /// Runs a thread write, then re-reads the threads for this iteration.
  Future<void> _write(Future<void> Function() action) async {
    final ref = _ref;
    final it = _iteration;
    if (ref == null || it == null) return;
    setState(() {
      _posting = true;
      _error = null;
    });
    final source = PrDiffSource(context.read<AdoClient>());
    try {
      await action();
      final threads = await source.threads(
        ref,
        iteration: it,
        baseIteration: 0,
      );
      if (!mounted) return;
      setState(() {
        _threads = _forThisFile(threads);
        _composerLine = null;
      });
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
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _post(int line, String text) async {
    final pr = _pr;
    if (pr == null) return;
    final repo = context.read<PullRequestRepository>();
    await _write(
      () => repo.addThread(
        widget.org,
        pr,
        content: text,
        filePath: widget.path,
        line: line,
        changeTrackingId: _change?.changeTrackingId,
        iteration: _iteration,
      ),
    );
  }

  Future<void> _reply(PrThread thread, String text) async {
    final pr = _pr;
    if (pr == null) return;
    final repo = context.read<PullRequestRepository>();
    await _write(() => repo.reply(widget.org, pr, thread.id, text));
  }

  Future<void> _setThreadStatus(PrThread thread, String status) async {
    final pr = _pr;
    if (pr == null) return;
    final repo = context.read<PullRequestRepository>();
    await _write(() => repo.setThreadStatus(widget.org, pr, thread.id, status));
  }

  /// Whether the file on screen is the source branch tip, so anchored line
  /// numbers can be edited in place.
  bool get _atLatestIteration =>
      _iterations.isNotEmpty && _iteration == _iterations.last.id;

  /// Commits the suggestion to the source branch (one edit through the
  /// Pushes API), resolves the thread, then reloads at the new iteration.
  Future<void> _applySuggestion(
    PrThread thread,
    PrComment comment,
    String suggestion,
  ) async {
    final pr = _pr;
    final start = thread.rightLine;
    if (pr == null || start == null || !_atLatestIteration) return;
    final end = thread.rightLineEnd ?? start;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply suggestion?'),
        content: Text(
          'Commits the change to ${pr.sourceBranch} '
          '(line${end > start ? 's $start–$end' : ' $start'} of ${widget.path}) '
          'and resolves the thread.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Commit'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = context.read<PullRequestRepository>();
    final content = PullRequestRepository.applySuggestion(
      _newText,
      start,
      end,
      suggestion,
    );
    var pushed = false;
    await _write(() async {
      await repo.pushEdit(
        widget.org,
        pr,
        path: widget.path,
        content: content,
        message: 'Apply suggestion from thread ${thread.id} (Boardhop)',
      );
      pushed = true;
      await repo.setThreadStatus(
        widget.org,
        pr,
        thread.id,
        PrThreadStatus.fixed,
      );
    });
    if (!pushed || !mounted) return;
    // The push added an iteration: reload the PR and show the newest one.
    setState(() {
      _pr = null;
      _iterations = const [];
      _iteration = null;
    });
    await _load();
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
                  : '+${diff.added} −${diff.removed} · ${_threads.length} thread${_threads.length == 1 ? '' : 's'}',
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
          if (_iterations.isNotEmpty)
            IterationPicker(
              iterations: _iterations,
              selected: _iteration,
              onSelect: _loading ? (_) {} : _selectIteration,
              dense: true,
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
                    canAct: _pr?.isActive == true,
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
                    onReply: _reply,
                    onSetThreadStatus: _setThreadStatus,
                    onApplySuggestion:
                        _pr?.isActive == true && _atLatestIteration
                        ? _applySuggestion
                        : null,
                  ),
          ),
        ],
      ),
    );
  }
}
