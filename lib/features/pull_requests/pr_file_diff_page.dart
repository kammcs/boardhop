import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../auth/auth_service.dart';
import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/routes.dart';
import '../../core/text/mention.dart';
import '../../data/mention_recents.dart';
import '../../data/models/pull_request.dart';
import '../../data/models/work_item.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/pr_diff_source.dart';
import '../../data/repositories/pull_request_repository.dart';
import '../../data/repositories/search_repository.dart';
import '../../data/repositories/work_item_form_repository.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../data/viewed_files_store.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import '../shared/attachments/attachment_links.dart';
import '../shared/attachments/inline_attachment_source.dart';
import '../shared/attachments/inline_attachments.dart';
import '../work_items/form/controls/attachments_section.dart'
    show AttachmentSource;
import '../shared/mention/mention_source.dart';
import '../shared/mention/mention_sources.dart';
import '../wiki/wiki_page_source.dart';
import 'diff/diff_cursor.dart';
import 'diff/diff_model.dart';
import 'diff/diff_nav_pill.dart';
import 'diff/diff_prefs.dart';
import 'diff/diff_view.dart';
import 'diff/highlighter.dart';
import 'pull_request_detail_page.dart' show IterationPicker;

/// Where the reader should land once the file on screen has loaded.
enum _Landing { none, firstChange, lastChange, line }

/// One file of a pull request iteration as a unified — or, on a wide
/// window, side-by-side — diff (spike F5), with the threads read for that
/// iteration so they sit on their tracked lines, a tap-to-comment gutter on
/// either side, ranges, file-level comments, the ▲▼ navigation control of
/// R5–R7 and the keyboard shortcuts of R16.
class PrFileDiffPage extends StatefulWidget {
  const PrFileDiffPage({
    super.key,
    required this.org,
    required this.id,
    required this.path,
    this.iteration,
    this.line,
  });

  final String org;
  final int id;
  final String path;
  final int? iteration;

  /// New-side line to open on, from `?line=` (a jump from the Comments
  /// tab).
  final int? line;

  @override
  State<PrFileDiffPage> createState() => _PrFileDiffPageState();
}

class _PrFileDiffPageState extends State<PrFileDiffPage> {
  PullRequest? _pr;
  PrRef? _ref;
  List<PrIteration> _iterations = const [];
  int? _iteration;

  /// The file on screen. State rather than a route parameter, so ▼ at the
  /// end of a file can open the next one in place (R7).
  late String _path;
  List<PrFileChange> _changes = const [];
  PrFileChange? _change;
  LineDiffResult? _diff;

  /// New-side text of the file at the shown iteration (suggestion apply).
  String _newText = '';
  List<List<CodeRun>> _oldRuns = const [];
  List<List<CodeRun>> _newRuns = const [];
  List<PrThread> _threads = const [];

  /// Where a new comment is being written: a line, a range, either side, or
  /// the file as a whole (R9, R10).
  DiffAnchor? _composer;
  String? _error;
  bool _loading = false;
  bool _posting = false;

  /// The diff's navigation stops and viewport (R5–R7).
  final _nav = DiffViewController();
  DiffNavMode _mode = DiffNavMode.changes;

  /// Where the last jump left the cursor; null falls back to what is on
  /// screen.
  int? _position;
  bool _pillVisible = true;

  /// True while a text field inside the diff has focus — the page's own
  /// composer, a thread's reply box or its edit-in-place field — so the
  /// pill can get out of the way of the Cancel / Save row (R6).
  bool _editorFocused = false;
  _Landing _landing = _Landing.none;

  /// How many frames the pending landing has waited for a laid-out list.
  int _landingTries = 0;

  /// R16's two remembered layout choices; [_sideBySide] null follows the
  /// window (side by side from the expanded breakpoint).
  bool _wrap = false;
  bool? _sideBySide;

  /// R8's local mark for the file on screen.
  bool _viewed = false;

  /// Identity of the signed-in user: whose comments offer edit and delete.
  String? _meId;

  /// The picker the inline reply boxes and the new-thread composer share,
  /// and the names this file's comments resolve their `@<guid>` runs to.
  MentionSources? _sources;
  MentionSource? _mentions;
  Map<String, String> _mentionNames = const {};

  /// The line composers' wiki-page picker (research/20 K12), built once the
  /// pull request has named its project.
  WikiPageSource? _wikiPages;

  /// Images and files the threads on this file carry. Every attachment URL
  /// is authenticated, so this page needs a bearer token of its own
  /// (research/17 §1 bug (b)).
  InlineAttachments? _attachments;

  /// The same source in the shape the line composer and the reply boxes
  /// need: where a picked file is uploaded on Send (T3).
  AttachmentSource? _uploads;

  /// The last request could not reach the service (decision T6).
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _path = widget.path;
    _iteration = widget.iteration;
    if (widget.line != null) _landing = _Landing.line;
    _nav.addListener(_onStops);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPrefs();
      _load();
    });
  }

  @override
  void dispose() {
    _nav.removeListener(_onStops);
    _nav.dispose();
    super.dispose();
  }

  /// The viewer rebuilt its rows. It publishes them from inside its own
  /// build, so everything here waits for the frame to end.
  void _onStops() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The rows moved: the old position indexes nothing.
      setState(() => _position = null);
      _land();
    });
  }

  Future<void> _loadPrefs() async {
    final account = AccountScope.maybeOf(context) ?? '';
    final wrap = await DiffPrefs.wrap(account);
    final sideBySide = await DiffPrefs.sideBySide(account);
    if (!mounted) return;
    setState(() {
      _wrap = wrap;
      _sideBySide = sideBySide;
    });
  }

  /// The same picker the pull request page builds, for the composers that
  /// live under a diff line. Off the critical path: the diff is readable
  /// whether or not the people can be read.
  Future<void> _prepareMentions(PullRequest pr) async {
    final people = context.read<PeopleRepository>();
    unawaited(
      people.rememberIdentities(
        widget.org,
        MentionSources.pullRequestParticipants(pr: pr, threads: _threads),
      ),
    );
    final names = await MentionSources.namesFor(people, widget.org, [
      for (final thread in _threads)
        for (final comment in thread.comments) comment.content,
    ]);
    if (!mounted) return;
    if (!mapEquals(names, _mentionNames)) {
      setState(() => _mentionNames = names);
    }
    if (_mentions != null) return;
    final sources = _sources ??= MentionSources(
      org: widget.org,
      project: pr.projectName,
      projectId: pr.projectId,
      people: people,
      forms: context.read<WorkItemFormRepository>(),
      recents: context.read<MentionRecents>(),
      workItems: context.read<WorkItemRepository>(),
      pullRequests: context.read<PullRequestRepository>(),
      search: context.read<SearchRepository>(),
    );
    final prs = context.read<PullRequestRepository>();
    IdentityRef? me;
    try {
      me = await sources.me(id: await prs.meId(widget.org));
    } on AdoException {
      // Mentioning yourself is a convenience, not the feature.
      me = null;
    }
    if (!mounted || _mentions != null) return;
    setState(() {
      _wikiPages ??= WikiPageSource.maybeOf(
        context,
        org: widget.org,
        project: pr.projectName,
      );
      _mentions = sources.source(
        participants: () async => MentionSources.pullRequestParticipants(
          pr: _pr ?? pr,
          threads: _threads,
        ),
        participantReason: MentionSources.onThisPullRequest,
        me: me,
      );
    });
  }

  /// A `#123` or `!456` tapped inside a comment on this diff (M10).
  void _openMention(MentionKind kind, String id) {
    final account = AccountScope.of(context);
    final pr = _pr;
    switch (kind) {
      case MentionKind.workItem:
        if (pr == null) return;
        // Standalone, not the in-shell route: this page is itself over
        // the project shell (see `Routes.workItemStandalone`).
        context.push(
          Routes.workItemStandalone(account, widget.org, pr.projectName, id),
        );
      case MentionKind.pullRequest:
        if (id == '${widget.id}') return;
        context.push(Routes.pullRequest(account, widget.org, id));
      case MentionKind.person:
        break;
    }
  }

  /// The local viewed marks, absent in the tests that build this page
  /// without the account's repositories.
  ViewedFilesStore? get _viewedStore {
    try {
      return context.read<ViewedFilesStore>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<PullRequestRepository>();
    final source = PrDiffSource(context.read<AdoClient>());
    final auth = context.read<AuthService>();
    final accountId = AccountScope.of(context);
    try {
      final token = await auth.accessToken(accountId: accountId);
      final pr = _pr ?? await repo.get(widget.org, widget.id);
      // The pull request store is keyed by the file name and refuses one it
      // already holds (w32 §4), so the uniquify lives here rather than in
      // the composer.
      _uploads = AttachmentSource(
        bytes: repo.attachmentBytes,
        upload: (name, bytes) => repo.uploadAttachment(
          widget.org,
          pr,
          uniqueAttachmentName(name),
          bytes,
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      _attachments = inlineAttachmentsOf(_uploads!);
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
        (c) => c.path == _path,
        orElse: () =>
            PrFileChange(path: _path, changeType: 'edit', changeTrackingId: 0),
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
      // A deleted comment stays in the thread as the web's stub (R9).
      final threads = await source.threads(
        ref,
        iteration: it.id,
        baseIteration: 0,
        includeDeleted: true,
      );
      if (!mounted) return;
      final brightness = Theme.of(context).brightness;
      final language = CodeHighlighter.languageFor(_path);
      final (oldRuns, newRuns) = await _highlight(
        oldText,
        newText,
        language,
        brightness,
      );
      if (!mounted) return;
      final viewed =
          await _viewedStore?.isViewed(widget.org, widget.id, _path) ?? false;
      if (!mounted) return;
      var meId = _meId;
      if (meId == null) {
        try {
          meId = await repo.meId(widget.org);
        } on AdoException {
          // Only the edit/delete menu depends on it.
          meId = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _pr = pr;
        _ref = ref;
        _iterations = iterations;
        _iteration = it.id;
        _changes = changes;
        _change = change;
        _composer = null;
        _newText = newText;
        _diff = LineDiff.compute(oldText, newText);
        _oldRuns = oldRuns;
        _newRuns = newRuns;
        _threads = _forThisFile(threads);
        _viewed = viewed;
        _meId = meId;
        _offline = false;
      });
      unawaited(_prepareMentions(pr));
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
      if (mounted) {
        setState(() {
          _error = e.message;
          _offline = e is AdoNetworkException;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Whole-file highlighting off the UI thread for anything big enough to
  /// drop a frame (spike F5 measured 376 ms for 3,000 lines); a short file
  /// costs less to colour here than to send to an isolate and back.
  static const _asyncHighlightChars = 20000;

  Future<(List<List<CodeRun>>, List<List<CodeRun>>)> _highlight(
    String oldText,
    String newText,
    String? language,
    Brightness brightness,
  ) async {
    if (oldText.length + newText.length < _asyncHighlightChars) {
      return (
        CodeHighlighter.highlightLines(oldText, language, brightness),
        CodeHighlighter.highlightLines(newText, language, brightness),
      );
    }
    return (
      await CodeHighlighter.highlightLinesAsync(oldText, language, brightness),
      await CodeHighlighter.highlightLinesAsync(newText, language, brightness),
    );
  }

  /// This file's threads, minus the ones the service has emptied: a thread
  /// whose every comment is deleted is gone on the web too.
  List<PrThread> _forThisFile(List<PrThread> threads) => [
    for (final t in threads)
      if (t.filePath == _path && t.comments.any((c) => !c.isDeleted)) t,
  ];

  void _selectIteration(int id) {
    if (id == _iteration) return;
    setState(() => _iteration = id);
    _load();
  }

  // ───────────────────────── navigation (R5–R7) ─────────────────────────

  int get _fileIndex {
    final i = _changes.indexWhere((c) => c.path == _path);
    return i < 0 ? 0 : i;
  }

  static String _nameOf(String path) =>
      path.substring(path.lastIndexOf('/') + 1);

  List<int> _stopsFor(DiffNavMode mode) => switch (mode) {
    DiffNavMode.changes => _nav.stops.changes,
    DiffNavMode.comments => _nav.stops.comments,
    DiffNavMode.files => [for (var i = 0; i < _changes.length; i++) i],
  };

  DiffCursor get _cursor {
    final index = _fileIndex;
    var cursor = DiffCursor(
      mode: _mode,
      stops: _stopsFor(_mode),
      position: _mode == DiffNavMode.files ? index : _position,
      nextFile: index + 1 < _changes.length
          ? _nameOf(_changes[index + 1].path)
          : null,
      previousFile: index > 0 ? _nameOf(_changes[index - 1].path) : null,
    );
    if (_mode == DiffNavMode.files) return cursor;
    final visible = _nav.visibleRows;
    if (visible != null) cursor = cursor.resolvedFrom(visible.$1, visible.$2);
    return cursor;
  }

  Map<DiffNavMode, int> get _counts => {
    for (final mode in DiffNavMode.values) mode: _stopsFor(mode).length,
  };

  /// One press of ▲ or ▼, from the pill, the app bar or the keyboard.
  void _step({required bool down}) {
    final cursor = _cursor;
    final next = down ? cursor.nextPosition : cursor.previousPosition;
    if (next != null) {
      if (_mode == DiffNavMode.files) {
        _openFile(
          cursor.stops[next],
          landing: down ? _Landing.firstChange : _Landing.lastChange,
        );
        return;
      }
      setState(() => _position = next);
      _nav.jumpTo(cursor.stops[next]);
      return;
    }
    switch (down ? cursor.downEdge : cursor.upEdge) {
      case DiffNavEdge.file:
        _openFile(
          _fileIndex + (down ? 1 : -1),
          landing: down ? _Landing.firstChange : _Landing.lastChange,
        );
      case DiffNavEdge.back:
        if (context.canPop()) context.pop();
      case DiffNavEdge.stop:
        break;
    }
  }

  /// Opens another file of the same pull request in place: same page, same
  /// iteration, threads re-read (R7).
  void _openFile(int index, {_Landing landing = _Landing.firstChange}) {
    if (index < 0 || index >= _changes.length) return;
    final path = _changes[index].path;
    if (path == _path) return;
    setState(() {
      _path = path;
      _diff = null;
      _threads = const [];
      _oldRuns = const [];
      _newRuns = const [];
      _composer = null;
      _position = null;
      _landing = landing;
      _landingTries = 0;
    });
    _load();
  }

  /// Puts the reader where the jump that opened this file promised.
  void _land() {
    final landing = _landing;
    if (landing == _Landing.none || !_nav.isAttached) return;
    _landingTries++;
    final stops = _nav.stops.changes;
    final int? row = switch (landing) {
      _Landing.firstChange => stops.isEmpty ? null : stops.first,
      _Landing.lastChange => stops.isEmpty ? null : stops.last,
      _Landing.line =>
        widget.line == null ? null : _nav.rowForNewLine(widget.line!),
      _Landing.none => null,
    };
    // The list may not be laid out on the frame the rows were published;
    // give it a few before giving up on the jump.
    if (row == null && _landingTries < 5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _land();
      });
      return;
    }
    setState(() {
      _landing = _Landing.none;
      _landingTries = 0;
      // The cursor only follows the landing when the reader is stepping
      // changes; in the other modes the stops are different rows and the
      // viewport decides.
      if (row != null &&
          landing != _Landing.line &&
          _mode == DiffNavMode.changes) {
        _position = landing == _Landing.firstChange ? 0 : stops.length - 1;
      } else {
        _position = null;
      }
    });
    if (row != null) _nav.jumpTo(row, animate: false);
  }

  void _setMode(DiffNavMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _position = null;
    });
  }

  // ───────────────────────── writes (R9, R10) ──────────────────────────

  /// Runs a write, re-reads the threads, and reports whether the write
  /// itself succeeded (a chained resolve stops if the reply failed).
  Future<bool> _write(Future<void> Function() action) async {
    final ref = _ref;
    final it = _iteration;
    if (ref == null || it == null) return false;
    setState(() {
      _posting = true;
      _error = null;
    });
    final source = PrDiffSource(context.read<AdoClient>());
    var ok = false;
    try {
      await action();
      ok = true;
      final threads = await source.threads(
        ref,
        iteration: it,
        baseIteration: 0,
        includeDeleted: true,
      );
      if (!mounted) return ok;
      setState(() {
        _threads = _forThisFile(threads);
        _composer = null;
      });
      // A comment just posted can name somebody no earlier comment on this
      // file named, and the names map is built from the threads; without
      // this the new `@<guid>` draws as "@someone" until the page is
      // reopened (M-D finding 1).
      final pr = _pr;
      if (pr != null) unawaited(_prepareMentions(pr));
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
      if (mounted) {
        setState(() {
          _error = e.message;
          _offline = e is AdoNetworkException;
        });
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
    return ok;
  }

  Future<void> _post(DiffAnchor anchor, String text) async {
    final pr = _pr;
    if (pr == null) return;
    final repo = context.read<PullRequestRepository>();
    await _write(
      () => repo.addThread(
        widget.org,
        pr,
        content: text,
        filePath: _path,
        line: anchor.fileLevel ? null : anchor.line,
        endLine: anchor.fileLevel || !anchor.isRange ? null : anchor.last,
        leftSide: anchor.leftSide,
        fileLevel: anchor.fileLevel,
        changeTrackingId: _change?.changeTrackingId,
        iteration: _iteration,
      ),
    );
  }

  Future<bool> _reply(PrThread thread, String text) async {
    final pr = _pr;
    if (pr == null) return false;
    final repo = context.read<PullRequestRepository>();
    return _write(() => repo.reply(widget.org, pr, thread.id, text));
  }

  Future<bool> _setThreadStatus(PrThread thread, String status) async {
    final pr = _pr;
    if (pr == null) return false;
    final repo = context.read<PullRequestRepository>();
    return _write(
      () => repo.setThreadStatus(widget.org, pr, thread.id, status),
    );
  }

  Future<bool> _editComment(
    PrThread thread,
    PrComment comment,
    String text,
  ) async {
    final pr = _pr;
    if (pr == null) return false;
    final repo = context.read<PullRequestRepository>();
    return _write(
      () => repo.editComment(widget.org, pr, thread.id, comment.id, text),
    );
  }

  Future<bool> _deleteComment(PrThread thread, PrComment comment) async {
    final pr = _pr;
    if (pr == null) return false;
    final repo = context.read<PullRequestRepository>();
    return _write(
      () => repo.deleteComment(widget.org, pr, thread.id, comment.id),
    );
  }

  Future<bool> _likeComment(
    PrThread thread,
    PrComment comment,
    bool like,
  ) async {
    final pr = _pr;
    if (pr == null) return false;
    final repo = context.read<PullRequestRepository>();
    return _write(
      () => like
          ? repo.like(widget.org, pr, thread.id, comment.id)
          : repo.unlike(widget.org, pr, thread.id, comment.id),
    );
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
          '(line${end > start ? 's $start–$end' : ' $start'} of $_path) '
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
        path: _path,
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

  // ─────────────────────── app bar actions (R8, R16) ────────────────────

  Future<void> _toggleViewed() async {
    final store = _viewedStore;
    final iteration = _iteration;
    if (store == null || iteration == null) return;
    final viewed = _viewed;
    // Marking advances nothing: the reader stays on the file (R8).
    setState(() => _viewed = !viewed);
    if (viewed) {
      await store.clear(widget.org, widget.id, path: _path);
    } else {
      await store.markViewed(
        widget.org,
        widget.id,
        _path,
        iterationId: iteration,
        objectId: _change?.objectId,
      );
    }
  }

  Future<void> _toggleWrap() async {
    setState(() => _wrap = !_wrap);
    await DiffPrefs.setWrap(AccountScope.maybeOf(context) ?? '', _wrap);
  }

  Future<void> _toggleSideBySide() async {
    final next = !_sideBySideNow;
    setState(() => _sideBySide = next);
    await DiffPrefs.setSideBySide(AccountScope.maybeOf(context) ?? '', next);
  }

  /// Two panes unless the reader said otherwise: the default follows the
  /// window (R16).
  bool get _sideBySideNow =>
      _sideBySide ?? (context.breakpoint == Breakpoint.expanded);

  void _commentOnFile() => setState(
    () => _composer = _composer?.fileLevel == true
        ? null
        : const DiffAnchor.file(),
  );

  // ───────────────────────── keyboard (R16) ─────────────────────────────

  /// Shortcuts never fire while a comment is being typed.
  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _shortcutStep(DiffNavMode mode, {required bool down}) {
    if (_mode != mode) {
      setState(() {
        _mode = mode;
        _position = null;
      });
    }
    _step(down: down);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final diff = _diff;
    final name = _nameOf(_path);
    final expanded = context.breakpoint == Breakpoint.expanded;
    final cursor = _cursor;
    final canAct = _pr?.isActive == true;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.bracketRight): _NextFileIntent(),
        SingleActivator(LogicalKeyboardKey.bracketLeft): _PreviousFileIntent(),
        SingleActivator(LogicalKeyboardKey.keyN): _NextCommentIntent(),
        SingleActivator(LogicalKeyboardKey.keyP): _PreviousCommentIntent(),
        SingleActivator(LogicalKeyboardKey.f7): _NextChangeIntent(),
        SingleActivator(LogicalKeyboardKey.f7, shift: true):
            _PreviousChangeIntent(),
        SingleActivator(LogicalKeyboardKey.keyV): _ToggleViewedIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _NextFileIntent: _DiffShortcut<_NextFileIntent>(
            () => !_typing,
            () => _openFile(_fileIndex + 1),
          ),
          _PreviousFileIntent: _DiffShortcut<_PreviousFileIntent>(
            () => !_typing,
            () => _openFile(_fileIndex - 1),
          ),
          _NextCommentIntent: _DiffShortcut<_NextCommentIntent>(
            () => !_typing,
            () => _shortcutStep(DiffNavMode.comments, down: true),
          ),
          _PreviousCommentIntent: _DiffShortcut<_PreviousCommentIntent>(
            () => !_typing,
            () => _shortcutStep(DiffNavMode.comments, down: false),
          ),
          _NextChangeIntent: _DiffShortcut<_NextChangeIntent>(
            () => !_typing,
            () => _shortcutStep(DiffNavMode.changes, down: true),
          ),
          _PreviousChangeIntent: _DiffShortcut<_PreviousChangeIntent>(
            () => !_typing,
            () => _shortcutStep(DiffNavMode.changes, down: false),
          ),
          _ToggleViewedIntent: _DiffShortcut<_ToggleViewedIntent>(
            () => !_typing,
            _toggleViewed,
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, overflow: TextOverflow.ellipsis),
                  Text(
                    diff == null
                        ? _path
                        : '+${diff.added} −${diff.removed} · '
                              '${_threads.length} thread'
                              '${_threads.length == 1 ? '' : 's'}',
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
                if (expanded && diff != null)
                  DiffNavBarControls(
                    cursor: cursor,
                    counts: _counts,
                    onUp: () => _step(down: false),
                    onDown: () => _step(down: true),
                    onMode: _setMode,
                  ),
                IconButton(
                  tooltip: _viewed ? 'Viewed' : 'Mark as viewed',
                  onPressed: _viewedStore == null ? null : _toggleViewed,
                  icon: Icon(
                    _viewed ? Icons.check_circle : Icons.check_circle_outline,
                    color: _viewed ? context.boardhopColors.voteApproved : null,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Diff options',
                  offset: kTrailingMenuOffset,
                  onSelected: (value) => switch (value) {
                    'file' => _commentOnFile(),
                    'wrap' => _toggleWrap(),
                    _ => _toggleSideBySide(),
                  },
                  itemBuilder: (context) => [
                    if (canAct)
                      const PopupMenuItem(
                        value: 'file',
                        child: ListTile(
                          leading: Icon(Icons.comment_outlined),
                          title: Text('Comment on file'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    CheckedPopupMenuItem(
                      value: 'wrap',
                      checked: _wrap,
                      child: const Text('Wrap long lines'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'split',
                      checked: _sideBySideNow,
                      child: const Text('Side by side'),
                    ),
                  ],
                ),
                if (_iterations.isNotEmpty)
                  IterationPicker(
                    iterations: _iterations,
                    selected: _iteration,
                    onSelect: _loading ? (_) {} : _selectIteration,
                    dense: true,
                  ),
              ],
            ),
            body: SafeArea(
              top: false,
              bottom: false,
              child: Column(
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
                        : _body(diff, canAct: canAct, expanded: expanded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(
    LineDiffResult diff, {
    required bool canAct,
    required bool expanded,
  }) {
    // The pill hides while a comment is being written and while the reader
    // scrolls down, and comes back on the way up (R6).
    //
    // "Being written" is more than the page's own new-thread composer: a
    // thread card's inline reply box and its edit-in-place field are its
    // own state, and on a phone the pill sat straight over their Cancel /
    // Save row (P-D). Both autofocus, so descendant focus is the signal
    // that covers all three without the card having to report upwards.
    final showsPill =
        !expanded && _composer == null && !_editorFocused && _pillVisible;
    return Stack(
      children: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (hasFocus) {
            if (hasFocus != _editorFocused) {
              setState(() => _editorFocused = hasFocus);
            }
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.axis != Axis.vertical) return false;
              if (notification is UserScrollNotification) {
                final visible = switch (notification.direction) {
                  ScrollDirection.reverse => false,
                  ScrollDirection.forward => true,
                  ScrollDirection.idle => _pillVisible,
                };
                if (visible != _pillVisible) {
                  setState(() => _pillVisible = visible);
                }
              } else if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                // The reader took over from the last jump: from here the
                // indicator follows the viewport (R6).
                setState(() => _position = null);
              } else if (notification is ScrollEndNotification) {
                // Re-read the viewport, which is where the indicator comes
                // from while no jump is standing.
                if (_position == null) setState(() {});
              }
              return false;
            },
            // The diff scrolls sideways too, so only a pull on the
            // rows themselves refreshes (same rule as the board).
            child: RefreshIndicator(
              onRefresh: _load,
              notificationPredicate: (n) =>
                  n.depth == 1 && n.metrics.axis == Axis.vertical,
              child: DiffView(
                diff: diff,
                controller: _nav,
                oldRuns: _oldRuns,
                newRuns: _newRuns,
                threads: _threads,
                composer: _composer,
                wrap: _wrap,
                sideBySide: _sideBySideNow,
                endPadding: expanded ? Spacing.xxl : 96,
                posting: _posting,
                canAct: canAct,
                meId: _meId,
                mentions: _mentions,
                mentionNames: _mentionNames,
                attachments: _attachments,
                uploads: _uploads,
                wikiPages: _wikiPages,
                offline: _offline,
                onOpenMention: _openMention,
                onGutterTap: canAct
                    ? (anchor) => setState(
                        () => _composer = _composer == anchor ? null : anchor,
                      )
                    : null,
                onCancelComposer: () => setState(() => _composer = null),
                onPost: _post,
                onReply: _reply,
                onSetThreadStatus: _setThreadStatus,
                onEditComment: _editComment,
                onDeleteComment: _deleteComment,
                onLikeComment: _likeComment,
                onApplySuggestion: canAct && _atLatestIteration
                    ? _applySuggestion
                    : null,
              ),
            ),
          ),
        ),
        if (!expanded)
          Positioned(
            right: Spacing.lg,
            bottom: Spacing.lg + MediaQuery.paddingOf(context).bottom,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 120),
              offset: showsPill ? Offset.zero : const Offset(0, 1.6),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: showsPill ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !showsPill,
                  child: DiffNavPill(
                    cursor: _cursor,
                    counts: _counts,
                    onUp: () => _step(down: false),
                    onDown: () => _step(down: true),
                    onMode: _setMode,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One of the diff's keyboard shortcuts (R16).
///
/// It is an [Action] rather than a `CallbackAction` for one reason: an
/// action that is **disabled** leaves the key event alone, while one that
/// invokes and does nothing still swallows it. Typing `n` into a comment on
/// an iPad has to reach the field, and on the device it did not until this
/// reported itself disabled (found on the iPad, 2026-09-16).
class _DiffShortcut<T extends Intent> extends Action<T> {
  _DiffShortcut(this.enabled, this.run);

  final bool Function() enabled;
  final void Function() run;

  @override
  bool isEnabled(T intent, [BuildContext? context]) => enabled();

  @override
  Object? invoke(covariant T intent) {
    run();
    return null;
  }
}

class _NextFileIntent extends Intent {
  const _NextFileIntent();
}

class _PreviousFileIntent extends Intent {
  const _PreviousFileIntent();
}

class _NextCommentIntent extends Intent {
  const _NextCommentIntent();
}

class _PreviousCommentIntent extends Intent {
  const _PreviousCommentIntent();
}

class _NextChangeIntent extends Intent {
  const _NextChangeIntent();
}

class _PreviousChangeIntent extends Intent {
  const _PreviousChangeIntent();
}

class _ToggleViewedIntent extends Intent {
  const _ToggleViewedIntent();
}
