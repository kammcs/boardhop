import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/git_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../../theme/theme.dart';
import '../pull_requests/diff/highlighter.dart';
import '../shared/account_scope.dart';
import 'widgets/repo_visuals.dart';

/// Edits one text file from the phone. The commit never lands on the
/// branch being viewed: it goes to a new branch named from the person's
/// alias and the file, and a sheet then offers a pull request against the
/// viewed branch. That respects branch policies everywhere.
class FileEditPage extends StatefulWidget {
  const FileEditPage({
    super.key,
    required this.org,
    required this.project,
    required this.repo,
    required this.ref,
    required this.path,
  });

  final String org;
  final String project;
  final GitRepository repo;

  /// Branch name the file was opened on (the PR target).
  final String ref;
  final String path;

  @override
  State<FileEditPage> createState() => _FileEditPageState();
}

class _FileEditPageState extends State<FileEditPage> {
  CodeLineEditingController? _controller;
  String _original = '';
  String? _tipCommit;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  String? _error;

  RepoRepository get _repos => context.read<RepoRepository>();

  String get _name => RepoPaths.segments(widget.path).lastOrNull ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repos = _repos;
    try {
      final meta = await repos.fileMetadata(
        widget.org,
        widget.project,
        widget.repo.id,
        ref: widget.ref,
        path: widget.path,
      );
      if (!mounted) return;
      if (meta == null || meta.isFolder) {
        setState(() => _error = 'This file does not exist on "${widget.ref}".');
        return;
      }
      if (meta.isBinary == true) {
        setState(() => _error = 'Binary files cannot be edited here.');
        return;
      }
      final size = meta.objectId == null
          ? null
          : await repos.blobSize(
              widget.org,
              widget.project,
              widget.repo.id,
              meta.objectId!,
            );
      if (size != null && size > RepoRepository.maxEditableBytes) {
        if (mounted) {
          setState(
            () => _error =
                'Files above ${formatBytes(RepoRepository.maxEditableBytes)} '
                'cannot be edited on a phone (${formatBytes(size)}).',
          );
        }
        return;
      }
      final content = await repos.fileAt(
        widget.org,
        widget.project,
        widget.repo.id,
        ref: widget.ref,
        path: widget.path,
      );
      if (!mounted) return;
      final controller = CodeLineEditingController.fromText(content);
      controller.addListener(_onChanged);
      setState(() {
        _original = content;
        _tipCommit = meta.commitId;
        _controller?.dispose();
        _controller = controller;
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

  void _onChanged() {
    final dirty = _controller?.text != _original;
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  /// Alias of the signed-in account (the part of the sign-in name before
  /// the @), for the branch name.
  String get _alias {
    final state = context.read<AuthBloc>().state;
    final id = AccountScope.maybeOf(context);
    if (state is AuthSignedIn) {
      for (final a in state.accounts) {
        if (id == null || a.id == id) {
          final user = a.username ?? '';
          if (user.isNotEmpty) return user.split('@').first;
        }
      }
    }
    return 'boardhop';
  }

  /// Keeps the file's line ending style when the editor normalized it.
  String get _edited {
    final text = _controller?.text ?? _original;
    if (_original.contains('\r\n') && !text.contains('\r\n')) {
      return text.replaceAll('\n', '\r\n');
    }
    return text;
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text('Your edits to $_name have not been committed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _commit() async {
    final tip = _tipCommit;
    if (tip == null) return;
    final draft = await showModalBottomSheet<_CommitDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CommitSheet(
        fileName: _name,
        branchName: RepoRepository.branchNameFor(_alias, widget.path),
        target: widget.ref,
      ),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repos = _repos;
    try {
      await repos.createBranch(
        widget.org,
        widget.project,
        widget.repo.id,
        name: draft.branch,
        fromCommit: tip,
      );
      final commitId = await repos.pushFile(
        widget.org,
        widget.project,
        widget.repo.id,
        branch: draft.branch,
        oldObjectId: tip,
        path: widget.path,
        content: _edited,
        message: draft.message,
      );
      if (!mounted) return;
      setState(() {
        _original = _controller?.text ?? _original;
        _dirty = false;
      });
      await _offerPullRequest(draft, commitId);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offerPullRequest(_CommitDraft draft, String commitId) async {
    final short = commitId.length > 7 ? commitId.substring(0, 7) : commitId;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Committed'),
        content: Text(
          '$short is on ${draft.branch}. Open a pull request into '
          '${widget.ref}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open pull request'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (open != true) {
      context.pop(true);
      return;
    }
    final pr = await showModalBottomSheet<_PrDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _PrSheet(
        title: draft.message,
        source: draft.branch,
        target: widget.ref,
      ),
    );
    if (pr == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final id = await _repos.createPullRequest(
        widget.org,
        widget.project,
        widget.repo.id,
        sourceBranch: draft.branch,
        targetBranch: widget.ref,
        title: pr.title,
        description: pr.description,
      );
      if (!mounted) return;
      context.pop(true);
      context.push('${orgRoute(context, widget.org)}/pull-requests/$id');
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = _controller;
    final language = CodeHighlighter.languageFor(widget.path);
    final mode = language == null ? null : builtinLanguages[language];
    final codeStyle = BoardhopTheme.codeStyle(context);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit $_name', overflow: TextOverflow.ellipsis),
              Text(
                'on ${widget.ref}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _dirty && !_busy && controller != null
                  ? _commit
                  : null,
              child: const Text('Commit'),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading || _busy) const LinearProgressIndicator(),
            if (_error != null)
              ListTile(
                leading: Icon(Icons.error_outline, color: scheme.error),
                title: Text(_error!),
              ),
            Expanded(
              child: controller == null
                  ? const SizedBox.shrink()
                  : CodeEditor(
                      controller: controller,
                      readOnly: _busy,
                      wordWrap: false,
                      autofocus: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm,
                        vertical: Spacing.sm,
                      ),
                      style: CodeEditorStyle(
                        fontSize: 13,
                        fontFamily: codeStyle.fontFamily,
                        fontFamilyFallback: codeStyle.fontFamilyFallback,
                        fontHeight: 1.45,
                        textColor: scheme.onSurface,
                        backgroundColor: scheme.surface,
                        codeTheme: mode == null
                            ? null
                            : CodeHighlightTheme(
                                languages: {
                                  language!: CodeHighlightThemeMode(mode: mode),
                                },
                                theme: CodeHighlighter.themeFor(
                                  theme.brightness,
                                ),
                              ),
                      ),
                      indicatorBuilder:
                          (
                            context,
                            editingController,
                            chunkController,
                            notifier,
                          ) => Row(
                            children: [
                              DefaultCodeLineNumber(
                                controller: editingController,
                                notifier: notifier,
                                textStyle: codeStyle.copyWith(
                                  fontSize: 13,
                                  color: scheme.outline,
                                ),
                              ),
                              const SizedBox(width: Spacing.sm),
                            ],
                          ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommitDraft {
  const _CommitDraft({required this.message, required this.branch});

  final String message;
  final String branch;
}

class _CommitSheet extends StatefulWidget {
  const _CommitSheet({
    required this.fileName,
    required this.branchName,
    required this.target,
  });

  final String fileName;
  final String branchName;
  final String target;

  @override
  State<_CommitSheet> createState() => _CommitSheetState();
}

class _CommitSheetState extends State<_CommitSheet> {
  late final _message = TextEditingController(
    text: 'Update ${widget.fileName}',
  );
  late final _branch = TextEditingController(text: widget.branchName);

  @override
  void dispose() {
    _message.dispose();
    _branch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final branch = RepoRepository.sanitizeBranchName(_branch.text);
    final valid = _message.text.trim().isNotEmpty && branch.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        0,
        Spacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Commit to a new branch', style: theme.textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text(
            'The change goes to its own branch off ${widget.target}; a pull '
            'request can follow.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          TextField(
            controller: _message,
            autofocus: true,
            textInputAction: TextInputAction.next,
            maxLines: 3,
            minLines: 1,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Commit message'),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _branch,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'New branch',
              helperText: branch == _branch.text.trim()
                  ? null
                  : 'Will be created as $branch',
            ),
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton.icon(
            onPressed: valid
                ? () => Navigator.of(context).pop(
                    _CommitDraft(message: _message.text.trim(), branch: branch),
                  )
                : null,
            icon: const Icon(Icons.commit),
            label: const Text('Commit'),
          ),
        ],
      ),
    );
  }
}

class _PrDraft {
  const _PrDraft({required this.title, required this.description});

  final String title;
  final String description;
}

class _PrSheet extends StatefulWidget {
  const _PrSheet({
    required this.title,
    required this.source,
    required this.target,
  });

  final String title;
  final String source;
  final String target;

  @override
  State<_PrSheet> createState() => _PrSheetState();
}

class _PrSheetState extends State<_PrSheet> {
  late final _title = TextEditingController(text: widget.title);
  final _description = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        0,
        Spacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New pull request', style: theme.textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text(
            '${widget.source} → ${widget.target}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          TextField(
            controller: _title,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _description,
            maxLines: 5,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'Description (Markdown)',
            ),
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton.icon(
            onPressed: _title.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(
                    _PrDraft(
                      title: _title.text.trim(),
                      description: _description.text.trim(),
                    ),
                  ),
            icon: const Icon(Icons.call_merge),
            label: const Text('Create pull request'),
          ),
        ],
      ),
    );
  }
}
