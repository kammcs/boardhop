import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/git_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../../theme/theme.dart';
import '../pull_requests/diff/highlighter.dart';
import '../shared/account_scope.dart';
import 'widgets/code_view.dart';
import 'widgets/item_actions.dart';
import 'widgets/repo_image.dart';
import 'widgets/repo_markdown.dart';
import 'widgets/repo_visuals.dart';

/// One file on one branch: highlighted source with line numbers (wrap and
/// text size toggles), a rendered view for Markdown, images inline, and a
/// size-and-type card for other binaries. Text above 1 MB waits for "Load
/// anyway". The last twenty files reopen offline from the cache.
class FilePage extends StatefulWidget {
  const FilePage({
    super.key,
    required this.org,
    required this.project,
    required this.repo,
    required this.ref,
    required this.path,
    this.line,
  });

  final String org;
  final String project;
  final GitRepository repo;
  final String ref;
  final String path;

  /// 1-based line to scroll to and tint.
  final int? line;

  @override
  State<FilePage> createState() => _FilePageState();
}

enum _Kind { text, image, binary }

class _FilePageState extends State<FilePage> {
  static const _sizes = [11.0, 12.0, 14.0, 16.0];

  late final String _path = RepoPaths.normalize(widget.path);
  GitItem? _meta;
  _Kind? _kind;
  int? _size;
  String? _content;
  List<List<CodeRun>>? _lines;
  DateTime? _cachedAt;
  bool _tooLarge = false;
  bool _wrap = false;
  int _sizeIndex = 1;
  bool _preview = true;
  bool _loading = true;
  String? _error;
  Brightness? _highlightedFor;
  int _highlightGeneration = 0;

  RepoRepository get _repos => context.read<RepoRepository>();

  String get _name => RepoPaths.segments(_path).lastOrNull ?? widget.repo.name;

  bool get _isMarkdown {
    final ext = _name.split('.').last.toLowerCase();
    return ext == 'md' || ext == 'markdown';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_content != null && _highlightedFor != brightness) _highlight();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repos = _repos;
    final repoId = widget.repo.id;
    try {
      if (_content == null) {
        final cached = await repos.cachedFile(
          repoId,
          ref: widget.ref,
          path: _path,
        );
        if (cached != null && mounted) {
          setState(() {
            _content = cached.content;
            _kind = _Kind.text;
            _cachedAt = cached.fetchedAt;
          });
          _highlight();
        }
      }
      final meta = await repos.fileMetadata(
        widget.org,
        widget.project,
        repoId,
        ref: widget.ref,
        path: _path,
      );
      if (!mounted) return;
      if (meta == null) {
        setState(() => _error = 'This file does not exist on "${widget.ref}".');
        return;
      }
      if (meta.isFolder) {
        setState(() => _error = 'This path is a folder.');
        return;
      }
      setState(() => _meta = meta);
      final objectId = meta.objectId;
      final size = objectId == null
          ? null
          : await repos.blobSize(widget.org, widget.project, repoId, objectId);
      if (!mounted) return;
      setState(() => _size = size);
      if (meta.isImage == true) {
        setState(() => _kind = _Kind.image);
        return;
      }
      if (meta.isBinary == true) {
        setState(() => _kind = _Kind.binary);
        return;
      }
      // Unchanged since the cached copy: nothing to download.
      final cached = await repos.cachedFile(
        repoId,
        ref: widget.ref,
        path: _path,
      );
      if (cached != null &&
          cached.objectId == objectId &&
          cached.objectId != null) {
        if (mounted && _content != cached.content) {
          setState(() {
            _content = cached.content;
            _kind = _Kind.text;
          });
          _highlight();
        }
        if (mounted) setState(() => _cachedAt = null);
        return;
      }
      if (size != null && size > RepoRepository.maxFileBytes) {
        setState(() {
          _kind = _Kind.binary;
          _error = 'Too large to open on a phone.';
        });
        return;
      }
      if (size != null && size > RepoRepository.largeFileBytes && !force) {
        setState(() {
          _tooLarge = true;
          _kind = _Kind.text;
        });
        return;
      }
      final content = await repos.fileContent(
        widget.org,
        widget.project,
        repoId,
        ref: widget.ref,
        path: _path,
        objectId: objectId,
      );
      if (!mounted) return;
      setState(() {
        _content = content;
        _kind = _Kind.text;
        _tooLarge = false;
        _cachedAt = null;
      });
      _highlight();
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

  /// Highlighting above this size is skipped: the grammar pass would take
  /// seconds and the result would hold millions of spans.
  static const _highlightLimit = 300 * 1024;

  Future<void> _highlight() async {
    final content = _content;
    if (content == null) return;
    final brightness = Theme.of(context).brightness;
    final generation = ++_highlightGeneration;
    _highlightedFor = brightness;
    // Plain rows first so the file is readable at once.
    final plain = await CodeHighlighter.highlightLinesAsync(
      content,
      null,
      brightness,
    );
    if (!mounted || generation != _highlightGeneration) return;
    setState(() => _lines = plain);
    final language = content.length > _highlightLimit
        ? null
        : CodeHighlighter.languageFor(_path);
    if (language == null) return;
    final lines = await CodeHighlighter.highlightLinesAsync(
      content,
      language,
      brightness,
    );
    if (!mounted || generation != _highlightGeneration) return;
    setState(() => _lines = lines);
  }

  void _actions() => showItemActions(
    context,
    org: widget.org,
    project: widget.project,
    repo: widget.repo,
    ref: widget.ref,
    path: _path,
    isFolder: false,
  );

  Future<void> _openInBrowser() async {
    final url = RepoWebUrls.file(widget.repo, _path, widget.ref);
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final showPreview = _isMarkdown && _preview;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_name, overflow: TextOverflow.ellipsis),
            Text(
              '${widget.ref}${_size == null ? '' : ' · ${formatBytes(_size)}'}',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (_isMarkdown && _content != null)
            IconButton(
              tooltip: _preview ? 'Show source' : 'Show preview',
              icon: Icon(_preview ? Icons.code : Icons.article_outlined),
              onPressed: () => setState(() => _preview = !_preview),
            ),
          if (_kind == _Kind.text && !showPreview)
            IconButton(
              tooltip: _wrap ? 'Unwrap lines' : 'Wrap lines',
              isSelected: _wrap,
              icon: const Icon(Icons.wrap_text),
              onPressed: () => setState(() => _wrap = !_wrap),
            ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              switch (v) {
                case 'larger':
                  setState(
                    () => _sizeIndex = (_sizeIndex + 1).clamp(
                      0,
                      _sizes.length - 1,
                    ),
                  );
                case 'smaller':
                  setState(
                    () => _sizeIndex = (_sizeIndex - 1).clamp(
                      0,
                      _sizes.length - 1,
                    ),
                  );
                case 'actions':
                  _actions();
              }
            },
            itemBuilder: (_) => [
              if (_kind == _Kind.text && !showPreview) ...[
                PopupMenuItem(
                  value: 'larger',
                  enabled: _sizeIndex < _sizes.length - 1,
                  child: const ListTile(
                    leading: Icon(Icons.text_increase),
                    title: Text('Larger text'),
                  ),
                ),
                PopupMenuItem(
                  value: 'smaller',
                  enabled: _sizeIndex > 0,
                  child: const ListTile(
                    leading: Icon(Icons.text_decrease),
                    title: Text('Smaller text'),
                  ),
                ),
                const PopupMenuDivider(),
              ],
              const PopupMenuItem(
                value: 'actions',
                child: ListTile(
                  leading: Icon(Icons.more_horiz),
                  title: Text('History, copy, open…'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            ListTile(
              leading: Icon(Icons.error_outline, color: scheme.error),
              title: Text(_error!),
              subtitle: _cachedAt == null
                  ? null
                  : Text('Showing the copy from ${relativeTime(_cachedAt)}.'),
            )
          else if (_cachedAt != null && !_loading)
            ListTile(
              dense: true,
              leading: Icon(Icons.cloud_off, color: scheme.onSurfaceVariant),
              title: Text('Copy from ${relativeTime(_cachedAt)}'),
            ),
          Expanded(child: _body(context, showPreview)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, bool showPreview) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    switch (_kind) {
      case null:
        return const SizedBox.shrink();
      case _Kind.image:
        return RepoImage(
          org: widget.org,
          project: widget.project,
          repoId: widget.repo.id,
          ref: widget.ref,
          path: _path,
          alt: _name,
          zoomable: true,
        );
      case _Kind.binary:
        return _InfoCard(
          icon: itemIcon(_meta ?? GitItem(path: _path, isFolder: false)),
          title: _name,
          lines: [
            if (_size != null) formatBytes(_size),
            if (_meta?.contentType != null) _meta!.contentType!,
            'Binary file',
          ],
          action: widget.repo.webUrl == null
              ? null
              : FilledButton.tonalIcon(
                  onPressed: _openInBrowser,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open in browser'),
                ),
        );
      case _Kind.text:
        if (_tooLarge && _content == null) {
          return _InfoCard(
            icon: Icons.warning_amber_outlined,
            title: _name,
            lines: [
              '${formatBytes(_size)} of text.',
              'Files above ${formatBytes(RepoRepository.largeFileBytes)} '
                  'load only on request.',
            ],
            action: FilledButton.tonalIcon(
              onPressed: _loading ? null : () => _load(force: true),
              icon: const Icon(Icons.download),
              label: const Text('Load anyway'),
            ),
          );
        }
        final content = _content;
        if (content == null) return const SizedBox.shrink();
        if (showPreview) {
          return SingleChildScrollView(
            padding: Spacing.page,
            child: ContentColumn(
              child: RepoMarkdown(
                data: content,
                org: widget.org,
                project: widget.project,
                repo: widget.repo,
                ref: widget.ref,
                path: _path,
              ),
            ),
          );
        }
        final lines = _lines;
        if (lines == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (lines.isEmpty) {
          return Center(
            child: Text(
              'Empty file',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return CodeView(
          lines: lines,
          wrap: _wrap,
          fontSize: _sizes[_sizeIndex],
          highlightLine: widget.line,
        );
    }
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.lines,
    this.action,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: Spacing.page,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: Spacing.md),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xs),
            for (final l in lines)
              Text(
                l,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            if (action != null) ...[
              const SizedBox(height: Spacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
