import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/git_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../pull_requests/diff/diff_model.dart';
import '../pull_requests/diff/diff_view.dart';
import '../pull_requests/diff/highlighter.dart';
import '../shared/account_scope.dart';

/// One file between two commits (a commit against its parent, or a branch
/// against the common ancestor of a comparison) on the PR diff engine,
/// read-only: no threads, no composer.
class FileDiffPage extends StatefulWidget {
  const FileDiffPage({
    super.key,
    required this.org,
    required this.project,
    required this.repo,
    required this.path,
    required this.oldRef,
    required this.newRef,
    this.changeType = 'edit',
    this.originalPath,
  });

  final String org;
  final String project;
  final GitRepository repo;
  final String path;

  /// Empty for a root commit (everything is added).
  final String oldRef;
  final String newRef;
  final String changeType;
  final String? originalPath;

  @override
  State<FileDiffPage> createState() => _FileDiffPageState();
}

class _FileDiffPageState extends State<FileDiffPage> {
  LineDiffResult? _diff;
  List<List<CodeRun>> _oldRuns = const [];
  List<List<CodeRun>> _newRuns = const [];
  bool _loading = true;
  String? _error;

  bool get _isAdd => widget.changeType.contains('add') || widget.oldRef.isEmpty;
  bool get _isDelete => widget.changeType.contains('delete');

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
    final repos = context.read<RepoRepository>();
    try {
      final oldText = _isAdd
          ? ''
          : await repos.fileAt(
              widget.org,
              widget.project,
              widget.repo.id,
              ref: widget.oldRef,
              path: widget.originalPath ?? widget.path,
            );
      final newText = _isDelete
          ? ''
          : await repos.fileAt(
              widget.org,
              widget.project,
              widget.repo.id,
              ref: widget.newRef,
              path: widget.path,
            );
      if (!mounted) return;
      final brightness = Theme.of(context).brightness;
      final language = CodeHighlighter.languageFor(widget.path);
      final diff = LineDiff.compute(oldText, newText);
      final runs = await Future.wait([
        CodeHighlighter.highlightLinesAsync(oldText, language, brightness),
        CodeHighlighter.highlightLinesAsync(newText, language, brightness),
      ]);
      if (!mounted) return;
      setState(() {
        _diff = diff;
        _oldRuns = runs[0];
        _newRuns = runs[1];
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
                  : '+${diff.added} −${diff.removed} · '
                        '${GitVersion.label(widget.oldRef.isEmpty ? '' : widget.oldRef)}'
                        '${widget.oldRef.isEmpty ? '' : ' → '}'
                        '${GitVersion.label(widget.newRef)}',
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
            tooltip: 'Open file',
            icon: const Icon(Icons.description_outlined),
            onPressed: _isDelete
                ? null
                : () => context.push(
                    '${projectRoute(context, widget.org, widget.project)}'
                    '/repos/${Uri.encodeComponent(widget.repo.name)}'
                    '/file?ref=${Uri.encodeQueryComponent(widget.newRef)}'
                    '&path=${Uri.encodeQueryComponent(widget.path)}',
                  ),
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
            child: diff == null
                ? (_loading
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : const SizedBox.shrink())
                : diff.lines.isEmpty
                ? Center(
                    child: Text(
                      'No text changes (binary or identical).',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : DiffView(diff: diff, oldRuns: _oldRuns, newRuns: _newRuns),
          ),
        ],
      ),
    );
  }
}
