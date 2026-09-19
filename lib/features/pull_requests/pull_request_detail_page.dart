import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/auth_bloc.dart';
import '../../auth/auth_service.dart';
import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/routes.dart';
import '../../core/text/mention.dart';
import '../../core/util/format.dart';
import '../../data/mention_recents.dart';
import '../../data/models/pr_check.dart';
import '../../data/models/pull_request.dart';
import '../../data/models/work_item.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/pr_diff_source.dart';
import '../../data/repositories/pull_request_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../../data/repositories/search_repository.dart';
import '../../data/repositories/sprint_repository.dart';
import '../../data/repositories/work_item_form_repository.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../data/viewed_files_store.dart';
import '../../theme/theme.dart';
import '../shared/mention/mention_controller.dart';
import '../shared/mention/mention_field.dart';
import '../shared/mention/mention_markdown.dart';
import '../shared/mention/mention_source.dart';
import '../wiki/wiki_page_source.dart';
import '../shared/widgets/tab_count_badge.dart';
import '../shared/mention/mention_sources.dart';
import '../work_items/widgets/work_item_actions.dart' show CommentComposer;
import '../work_items/widgets/work_item_visuals.dart';
import '../shared/account_scope.dart';
import '../shared/anchor_highlight.dart';
import '../shared/attachments/attachment_links.dart';
import '../shared/attachments/inline_attachment_source.dart';
import '../shared/attachments/inline_attachments.dart';
import '../work_items/form/controls/attachments_section.dart'
    show AttachmentSource;
import 'widgets/auto_complete_banner.dart';
import 'widgets/branch_picker_sheet.dart';
import 'widgets/completion_sheet.dart';
import 'widgets/labels_editor.dart';
import 'widgets/merge_box.dart';
import 'widgets/pr_visuals.dart';
import 'widgets/reviewers_section.dart';
import 'widgets/thread_card.dart';
import 'widgets/work_item_link_sheet.dart';

/// One pull request: overview (description, checks, reviewers, linked work
/// items), changed files of a chosen iteration, and the conversation with
/// replies and thread status. Vote, complete and abandon from the app bar;
/// new conversation comments from the composer.
class PullRequestDetailPage extends StatefulWidget {
  const PullRequestDetailPage({
    super.key,
    required this.org,
    required this.id,
    this.initialTab,
    this.initialThreadId,
  });

  final String org;
  final int id;

  /// Which tab a pushed notification wants (`?tab=comments|files`,
  /// research/14 §4.2). Anything else, and the page opens on Overview
  /// as it always has.
  final String? initialTab;

  /// The thread a pushed comment notification names (`?thread={id}`). It
  /// selects Comments; a conversation thread is scrolled to and tinted, a
  /// file thread opens the diff at that file the way tapping its header
  /// does, so Back returns to this page.
  final int? initialThreadId;

  @override
  State<PullRequestDetailPage> createState() => _PullRequestDetailPageState();
}

class _PullRequestDetailPageState extends State<PullRequestDetailPage>
    with SingleTickerProviderStateMixin {
  /// Overview, Files, Comments. Owned here rather than through a
  /// `DefaultTabController` so the scaffold rebuilds when the tab changes
  /// and can take its composer away; see [_commentsTab].
  late final TabController _tabs =
      TabController(length: 3, vsync: this, initialIndex: _initialIndex)
        ..addListener(() {
          if (!mounted) return;
          setState(() {});
        });

  /// The tab a deep link asks for (research/14 §4.2); a thread anchor
  /// implies Comments, because that is where the thread lives.
  int get _initialIndex => switch (widget.initialTab) {
    'files' => _filesTab,
    'comments' => _commentsTab,
    _ => widget.initialThreadId != null ? _commentsTab : 0,
  };

  /// The Comments tab's index. The composer posts a conversation comment,
  /// which means nothing under Overview and is the wrong gesture under
  /// Files, where a comment belongs to a line and is written from the
  /// diff's gutter (iPhone walkthrough, finding j).
  static const int _commentsTab = 2;
  static const int _filesTab = 1;

  /// One key per thread card, and the tint the anchored one wears for two
  /// seconds (research/14 §4.2).
  final Map<int, GlobalKey> _threadKeys = {};
  final _threadScroll = ScrollController();
  int? _highlighted;
  Timer? _highlightTimer;

  /// The anchor is honoured once: a pull to refresh, or coming back from
  /// the file diff, must not scroll the reader away again.
  int? _anchoredFor;

  PullRequest? _pr;
  String? _me;
  List<WorkItem> _workItems = const [];
  List<PrCheck> _checks = const [];

  /// The target branch's policies: what decides whether auto-complete is
  /// offered, which merge strategies the sheet may show and who the
  /// required reviewers are (R2/R3). Null when the read was refused.
  PrPolicySet? _policies;

  /// Names for the GUIDs a "Required reviewers" policy carries, keyed by
  /// the lower-cased GUID (NEXT-STEPS item 8's open end).
  Map<String, IdentityRef> _requiredReviewers = const {};

  /// Read only while `mergeStatus` is `conflicts`.
  List<PrConflict> _conflicts = const [];

  List<PrIteration> _iterations = const [];
  List<PrFileChange> _changes = const [];
  int? _iteration;

  /// Which files have been read on this device (R8), and the store they
  /// live in — shared with the diff page.
  Map<String, ViewedMark> _viewed = const {};

  /// The threads as the service answered them, kept so the Activity chip
  /// can re-render the same read with the system threads in (R11).
  List<Map<String, dynamic>> _rawThreads = const [];
  List<PrThread> _conversation = const [];
  bool _activity = false;
  PrConversationFilter _threadFilter = PrConversationFilter.all;
  String? _error;
  bool _loading = false;
  bool _changesLoading = false;
  bool _acting = false;

  /// The mention picker for the composer and every reply box, built once the
  /// pull request is read (research/16 §4.5), and the names its comments'
  /// `@<guid>` runs resolve to. Both are niceties: the page is complete
  /// without them and neither failure is worth an error.
  MentionSources? _sources;
  MentionSource? _mentions;
  Map<String, String> _mentionNames = const {};

  /// The composers' wiki-page picker, built once the pull request has said
  /// which project it belongs to (research/20 K12). Null hides the book
  /// button, which is also what a widget test with no `WikiRepository`
  /// gets.
  WikiPageSource? _wikiPages;

  /// Images and files inside the description and the comments. A pull
  /// request page held no bearer token until now; every attachment URL is
  /// authenticated, so without one a web-authored image renders as nothing
  /// (research/17 §1 bug (b)).
  InlineAttachments? _attachments;

  /// The same source in the shape the composers need: where a file picked
  /// into a comment or a reply is uploaded on Send (T3).
  AttachmentSource? _uploads;

  /// The last request could not reach the service (decision T6).
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(PullRequestDetailPage old) {
    super.didUpdateWidget(old);
    if (old.initialThreadId != widget.initialThreadId) {
      _anchoredFor = null;
      _anchorThread();
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _threadScroll.dispose();
    _tabs.dispose();
    super.dispose();
  }

  /// Lands a pushed comment notification on its thread (research/14 §4.2).
  ///
  /// A conversation thread is scrolled to and tinted. A file thread opens
  /// the file diff exactly as tapping the thread's header does, but only
  /// after the Comments tab has been shown, so Back comes back here. A
  /// thread that is no longer in the list leaves the tab as it is, with no
  /// error.
  void _anchorThread() {
    final id = widget.initialThreadId;
    if (id == null || _anchoredFor == id) return;
    final thread = _conversation.where((t) => t.id == id).firstOrNull;
    if (thread == null) return;
    _anchoredFor = id;
    // A filter hiding the thread would make the anchor land on nothing.
    if (PullRequestRepository.filterConversation([
      thread,
    ], _threadFilter).isEmpty) {
      setState(() => _threadFilter = PrConversationFilter.all);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (thread.isFileThread) {
        await _openThread(thread);
        return;
      }
      final key = _threadKeys.putIfAbsent(id, GlobalKey.new);
      final found = await revealAnchor(target: key, scroller: _threadScroll);
      if (!found || !mounted) return;
      setState(() => _highlighted = id);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(kAnchorHighlight, () {
        if (mounted) setState(() => _highlighted = null);
      });
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<PullRequestRepository>();
    final workItems = context.read<WorkItemRepository>();
    final source = PrDiffSource(context.read<AdoClient>());
    final auth = context.read<AuthService>();
    final viewedFiles = context.read<ViewedFilesStore>();
    final accountId = AccountScope.of(context);
    try {
      final token = await auth.accessToken(accountId: accountId);
      final pr = await repo.get(widget.org, widget.id);
      // The pull request store is keyed by the file name and answers 400
      // for one it already holds (w32 §4), so the uniquify lives here
      // rather than in the composer, which stays surface-agnostic.
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
      _me = await repo.meId(widget.org);
      final ref = repo.ref(widget.org, pr);
      final results = await Future.wait<Object?>([
        repo.workItemIds(widget.org, pr),
        source.iterations(ref),
        repo.rawThreads(widget.org, pr),
        repo.checks(widget.org, pr),
        // Labels are filled on every list route and never on the get
        // (spikes s65 §A, w40), so the detail merges the sub-resource;
        // the policies decide what the merge box may offer. Neither is
        // worth failing the page over.
        _optional(() => repo.labels(widget.org, pr)),
        _optional(
          () => repo.policies(
            widget.org,
            pr.projectId,
            pr.repositoryId,
            pr.targetRefName,
          ),
        ),
        pr.mergeStatus == 'conflicts'
            ? _optional(() => repo.conflicts(widget.org, pr))
            : Future<List<PrConflict>?>.value(const []),
      ]);
      final ids = results[0]! as List<int>;
      final iterations = results[1]! as List<PrIteration>;
      final raw = results[2]! as List<Map<String, dynamic>>;
      final checks = results[3]! as List<PrCheck>;
      final labels = results[4] as List<PrLabel>?;
      final policies = results[5] as PrPolicySet?;
      final conflicts = results[6] as List<PrConflict>?;
      // Keep the chosen iteration across reloads when it still exists.
      final selected = iterations.any((i) => i.id == _iteration)
          ? _iteration
          : (iterations.isEmpty ? null : iterations.last.id);
      final changes = selected == null
          ? const <PrFileChange>[]
          : await source.changes(ref, selected);
      // R8: a mark is only as good as the version it was made against, so
      // the ones whose file moved in this iteration go before they are read.
      if (selected != null && changes.isNotEmpty) {
        await viewedFiles.prune(
          widget.org,
          widget.id,
          changes,
          iterationId: selected,
        );
      }
      final viewed = Map<String, ViewedMark>.of(
        await viewedFiles.marks(widget.org, widget.id),
      );
      final linked = ids.isEmpty
          ? const <WorkItem>[]
          : await workItems.batch(widget.org, pr.projectId, ids);
      if (!mounted) return;
      setState(() {
        _pr = labels == null ? pr : pr.withLabels(labels);
        _offline = false;
        _iterations = iterations;
        _iteration = selected;
        _changes = changes;
        _viewed = viewed;
        _checks = checks;
        _policies = policies;
        _conflicts = conflicts ?? const [];
        _workItems = linked;
        _rawThreads = raw;
        _conversation = PullRequestRepository.conversation(raw);
      });
      _anchorThread();
      unawaited(_prepareMentions(pr));
      unawaited(_resolveRequiredReviewers(policies));
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
    } catch (e, stack) {
      // A response the parsers did not expect (a deleted file with no
      // `item.path` once left the page blank with no error at all): say so
      // instead of showing nothing, and keep the trace for debug builds.
      FlutterError.reportError(
        FlutterErrorDetails(exception: e, stack: stack, library: 'boardhop'),
      );
      if (mounted) {
        setState(() => _error = 'This pull request could not be read.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A read the page is better with and fine without: an `AdoException`
  /// other than an auth one answers null instead of taking the page down.
  /// The auth one still travels, so `_load` can raise
  /// `AuthInteractionRequired` for it.
  static Future<T?> _optional<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on AdoAuthException {
      rethrow;
    } on AdoException {
      return null;
    }
  }

  /// Names for the identity GUIDs the target's "Required reviewers" policy
  /// carries. `identityById` is memoised and never throws, so this is a
  /// background nicety; it closes the open end of NEXT-STEPS item 8, where
  /// the Checks row could only say how many there were.
  Future<void> _resolveRequiredReviewers(PrPolicySet? policies) async {
    final ids = policies?.requiredReviewerIds ?? const <String>[];
    if (ids.isEmpty) {
      if (mounted && _requiredReviewers.isNotEmpty) {
        setState(() => _requiredReviewers = const {});
      }
      return;
    }
    final people = context.read<PeopleRepository>();
    final pr = _pr;
    // Reviewers already on the pull request are seeded first, so a policy
    // reviewer who has voted needs no call at all.
    if (pr != null) {
      unawaited(
        people.rememberIdentities(widget.org, [
          for (final r in pr.reviewers) r.identity,
        ]),
      );
    }
    final found = <String, IdentityRef>{};
    for (final id in ids) {
      final person = await people.identityById(widget.org, id);
      if (person != null) found[id.toLowerCase()] = person;
    }
    if (!mounted) return;
    setState(() => _requiredReviewers = found);
  }

  /// The picker and the comment names, off the page's critical path.
  ///
  /// Everybody on a pull request — the author, the reviewers and every
  /// commenter — is seeded into the identity memory first, which is what
  /// lets most `@<guid>` runs be named without a call (M9).
  Future<void> _prepareMentions(PullRequest pr) async {
    final people = context.read<PeopleRepository>();
    final participants = MentionSources.pullRequestParticipants(
      pr: pr,
      threads: _conversation,
    );
    unawaited(people.rememberIdentities(widget.org, participants));
    final names = await MentionSources.namesFor(people, widget.org, [
      ?pr.description,
      for (final thread in _conversation)
        for (final comment in thread.comments) comment.content,
    ]);
    if (!mounted) return;
    if (!mapEquals(names, _mentionNames)) {
      setState(() => _mentionNames = names);
    }
    // The source is built once: a new instance would make every open picker
    // reload its bands.
    if (_mentions != null) return;
    final sources = _ensureSources(pr);
    final me = await sources.me(id: _me);
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
          threads: _conversation,
        ),
        participantReason: MentionSources.onThisPullRequest,
        me: me,
      );
    });
  }

  /// The page's [MentionSources], built on demand.
  ///
  /// The composers get it from [_prepareMentions], which runs in the
  /// background; the work item link picker reuses its `#` band and may be
  /// opened before that has finished, so the construction (which makes no
  /// call of its own) lives here.
  MentionSources _ensureSources(PullRequest pr) => _sources ??= MentionSources(
    org: widget.org,
    project: pr.projectName,
    projectId: pr.projectId,
    people: context.read<PeopleRepository>(),
    forms: context.read<WorkItemFormRepository>(),
    recents: context.read<MentionRecents>(),
    workItems: context.read<WorkItemRepository>(),
    pullRequests: context.read<PullRequestRepository>(),
    search: context.read<SearchRepository>(),
    extraWorkItems: () => _workItems,
  );

  /// A `#123` or `!456` tapped inside a comment (M10).
  void _openMention(MentionKind kind, String id) {
    final account = AccountScope.of(context);
    switch (kind) {
      case MentionKind.workItem:
        final pr = _pr;
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

  Future<void> _selectIteration(int id) async {
    final pr = _pr;
    if (pr == null || id == _iteration) return;
    setState(() {
      _iteration = id;
      _changesLoading = true;
    });
    final source = PrDiffSource(context.read<AdoClient>());
    final ref = context.read<PullRequestRepository>().ref(widget.org, pr);
    final viewedFiles = context.read<ViewedFilesStore>();
    try {
      final changes = await source.changes(ref, id);
      // R8 again: picking a newer iteration is the other way a reader meets
      // a version they have not read, so the marks it touches go here too.
      // Only `_load` used to prune, so stepping the picker from 9 to 10 left
      // a tick on a file that the tenth iteration had just rewritten (P-D).
      if (changes.isNotEmpty) {
        await viewedFiles.prune(
          widget.org,
          widget.id,
          changes,
          iterationId: id,
        );
      }
      final marks = Map<String, ViewedMark>.of(
        await viewedFiles.marks(widget.org, widget.id),
      );
      if (mounted) {
        setState(() {
          _changes = changes;
          _viewed = marks;
        });
      }
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
      if (mounted) setState(() => _changesLoading = false);
    }
  }

  /// Runs a write, then reloads. Completing a pull request is asynchronous
  /// on the service (the merge is queued), so [settle] keeps reloading for
  /// a few seconds until the status leaves `active`.
  /// Runs a write, reloads, and reports whether the write itself went
  /// through, so a caller chaining two writes can stop after the first.
  Future<bool> _act(
    Future<void> Function() action, {
    bool settle = false,
  }) async {
    setState(() {
      _acting = true;
      _error = null;
    });
    var ok = false;
    try {
      await action();
      ok = true;
      await _load();
      for (var i = 0; settle && i < 6 && _pr?.isActive == true; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return ok;
        await _load();
      }
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
      if (mounted) setState(() => _acting = false);
    }
    return ok;
  }

  Future<void> _vote(PrVote vote) async {
    final pr = _pr;
    if (pr == null) return;
    final repo = context.read<PullRequestRepository>();
    await _act(() => repo.vote(widget.org, pr, vote));
  }

  // ------------------------------------------------------------- actions

  /// The merge box's one button (R2).
  Future<void> _primary(PrPrimaryAction action) async {
    final pr = _pr;
    if (pr == null) return;
    final repo = context.read<PullRequestRepository>();
    switch (action) {
      case PrPrimaryAction.complete:
        await _completion(autoComplete: false);
      case PrPrimaryAction.setAutoComplete:
        await _completion(autoComplete: true);
      case PrPrimaryAction.publish:
        await _setDraft(false);
      case PrPrimaryAction.reactivate:
        await _act(() => repo.setStatus(widget.org, pr, 'active'));
    }
  }

  /// Complete and Set auto-complete share one sheet (R3); only the write at
  /// the end differs. A completion is asynchronous on the service, so it
  /// settles; auto-complete lands at once and does not.
  Future<void> _completion({required bool autoComplete}) async {
    final pr = _pr;
    if (pr == null) return;
    final options = await showCompletionSheet(
      context,
      pr: pr,
      policies: _policies,
      autoComplete: autoComplete,
      checks: mergePolicyRows(_checks, _policies),
    );
    if (options == null || !mounted) return;
    final repo = context.read<PullRequestRepository>();
    await _act(
      () => autoComplete
          ? repo.setAutoComplete(widget.org, pr, options)
          : repo.complete(widget.org, pr, options),
      settle: !autoComplete,
    );
  }

  Future<void> _cancelAutoComplete() async {
    final pr = _pr;
    if (pr == null) return;
    final repo = context.read<PullRequestRepository>();
    await _act(() => repo.cancelAutoComplete(widget.org, pr));
  }

  /// Marking as draft resets every vote, which is what R4's confirm warns
  /// about; publishing needs no confirmation.
  Future<void> _setDraft(bool isDraft) async {
    final pr = _pr;
    if (pr == null) return;
    if (isDraft) {
      final ok = await _confirm(
        title: 'Mark !${pr.id} as draft?',
        body:
            'Reviewers stay on the pull request, but every vote already '
            'cast is reset.',
        verb: 'Mark as draft',
      );
      if (ok != true || !mounted) return;
    }
    final repo = context.read<PullRequestRepository>();
    await _act(() => repo.setDraft(widget.org, pr, isDraft));
  }

  /// A new target branch adds a `retarget` iteration and re-queues the
  /// merge (research/22 §1), so the page reloads onto it.
  Future<void> _retarget() async {
    final pr = _pr;
    if (pr == null) return;
    final repos = context.read<RepoRepository>();
    final branch = await pickBranch(
      context,
      title: 'Change target branch',
      current: pr.targetBranch,
      branches: () => repos.branches(widget.org, pr.projectId, pr.repositoryId),
    );
    if (branch == null || !mounted) return;
    final repo = context.read<PullRequestRepository>();
    await _act(() => repo.retarget(widget.org, pr, 'refs/heads/$branch'));
  }

  Future<void> _restartMerge() async {
    final pr = _pr;
    if (pr == null) return;
    final repo = context.read<PullRequestRepository>();
    await _act(() => repo.restartMerge(widget.org, pr), settle: false);
  }

  Future<void> _share() async {
    final pr = _pr;
    if (pr == null) return;
    await SharePlus.instance.share(
      ShareParams(
        uri: Uri.parse(pr.webUrl(widget.org)),
        title: '!${pr.id} ${pr.title}',
      ),
    );
  }

  void _copyLink() {
    final pr = _pr;
    if (pr == null) return;
    // Not awaited: the platform write cannot fail in a way the user could
    // act on, and awaiting it would put the confirmation a frame behind the
    // tap.
    unawaited(Clipboard.setData(ClipboardData(text: pr.webUrl(widget.org))));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Link copied.')));
  }

  /// Title and description, the description through a [MentionField] so an
  /// `@` in it is written as `@<guid>` the way a comment is (M15).
  Future<void> _editDetails() async {
    final pr = _pr;
    if (pr == null) return;
    final edited = await showPrEditSheet(context, pr: pr, mentions: _mentions);
    if (edited == null || !mounted) return;
    final repo = context.read<PullRequestRepository>();
    await _act(
      () => repo.update(
        widget.org,
        pr,
        title: edited.title == pr.title ? null : edited.title,
        description: edited.description == (pr.description ?? '')
            ? null
            : edited.description,
      ),
    );
  }

  Future<void> _reviewerAction(PrReviewer r, PrReviewerAction action) async {
    final pr = _pr;
    if (pr == null) return;
    final repo = context.read<PullRequestRepository>();
    await _act(() async {
      switch (action) {
        case PrReviewerAction.makeRequired:
          await repo.setRequired(widget.org, pr, r.id, true);
        case PrReviewerAction.makeOptional:
          await repo.setRequired(widget.org, pr, r.id, false);
        case PrReviewerAction.resetVote:
          await repo.resetVote(widget.org, pr, r.id);
        case PrReviewerAction.remove:
          await repo.removeReviewer(widget.org, pr, r.id);
        case PrReviewerAction.flag:
          await repo.flag(widget.org, pr, r.id);
        case PrReviewerAction.unflag:
          await repo.flag(widget.org, pr, r.id, isFlagged: false);
        case PrReviewerAction.decline:
          await repo.decline(widget.org, pr, r.id);
        case PrReviewerAction.undecline:
          await repo.decline(widget.org, pr, r.id, hasDeclined: false);
      }
    });
  }

  Future<void> _addReviewer() async {
    final pr = _pr;
    if (pr == null) return;
    final people = context.read<PeopleRepository>();
    final sprints = context.read<SprintRepository>();
    final picked = await pickReviewer(
      context,
      teams: () => sprints.teams(widget.org, pr.projectName),
      search: (q) => people.searchPeople(widget.org, pr.projectId, q),
      resolve: (person) => people.resolveIdentityId(widget.org, person),
      existing: {for (final r in pr.reviewers) r.id.toLowerCase()},
    );
    if (picked == null || !mounted) return;
    final repo = context.read<PullRequestRepository>();
    await _act(
      () => repo.addReviewer(
        widget.org,
        pr,
        picked.id,
        isRequired: picked.isRequired,
      ),
    );
  }

  /// The editor answers with the list the user settled on; the page sends
  /// one write per change, because the service has no "set labels" route.
  Future<void> _editLabels() async {
    final pr = _pr;
    if (pr == null) return;
    final forms = context.read<WorkItemFormRepository>();
    final current = [for (final l in pr.labels) l.name];
    final next = await showLabelsEditor(
      context,
      current: current,
      suggestions: () => forms.tags(widget.org, pr.projectName),
    );
    if (next == null || !mounted) return;
    bool has(List<String> list, String name) =>
        list.any((v) => v.toLowerCase() == name.toLowerCase());
    final added = [
      for (final n in next)
        if (!has(current, n)) n,
    ];
    final removed = [
      for (final c in current)
        if (!has(next, c)) c,
    ];
    if (added.isEmpty && removed.isEmpty) return;
    final repo = context.read<PullRequestRepository>();
    await _act(() async {
      for (final name in added) {
        await repo.addLabel(widget.org, pr, name);
      }
      for (final name in removed) {
        await repo.removeLabel(widget.org, pr, name);
      }
    });
  }

  /// Linking is a **work item** write (json-patch on its relations); the
  /// pull request side has no route for it (research/22 §1).
  Future<void> _linkWorkItem() async {
    final pr = _pr;
    if (pr == null) return;
    final sources = _ensureSources(pr);
    final id = await pickWorkItemToLink(
      context,
      search: sources.workItemMatches,
      linked: {for (final w in _workItems) w.id},
    );
    if (id == null || !mounted) return;
    final items = context.read<WorkItemRepository>();
    await _act(
      () => items.linkPullRequest(
        widget.org,
        id,
        pr.projectId,
        pr.repositoryId,
        pr.id,
        project: pr.projectName,
      ),
    );
  }

  Future<void> _unlinkWorkItem(WorkItem item) async {
    final pr = _pr;
    if (pr == null) return;
    final ok = await _confirm(
      title: 'Unlink #${item.id}?',
      body: 'The work item itself is not changed.',
      verb: 'Unlink',
    );
    if (ok != true || !mounted) return;
    final items = context.read<WorkItemRepository>();
    await _act(
      () => items.unlinkPullRequest(
        widget.org,
        item.id,
        pr.projectId,
        pr.repositoryId,
        pr.id,
        project: pr.projectName,
      ),
    );
  }

  /// R8's check on the Files tab. Local only: Azure DevOps has no
  /// server-side viewed state (spike s64).
  Future<void> _toggleViewed(PrFileChange change) async {
    final iteration = _iteration;
    if (iteration == null) return;
    final store = context.read<ViewedFilesStore>();
    if (_viewed.containsKey(change.path)) {
      await store.clear(widget.org, widget.id, path: change.path);
    } else {
      await store.markViewed(
        widget.org,
        widget.id,
        change.path,
        iterationId: iteration,
        objectId: change.objectId,
      );
    }
    final marks = Map<String, ViewedMark>.of(
      await store.marks(widget.org, widget.id),
    );
    if (mounted) setState(() => _viewed = marks);
  }

  Future<void> _more(PrMoreAction action) async {
    switch (action) {
      case PrMoreAction.edit:
        await _editDetails();
      case PrMoreAction.markDraft:
        await _setDraft(true);
      case PrMoreAction.publish:
        await _setDraft(false);
      case PrMoreAction.retarget:
        await _retarget();
      case PrMoreAction.restartMerge:
        await _restartMerge();
      case PrMoreAction.abandon:
        await _abandon();
      case PrMoreAction.reactivate:
        await _primary(PrPrimaryAction.reactivate);
      case PrMoreAction.share:
        await _share();
      case PrMoreAction.copyLink:
        _copyLink();
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String verb,
  }) => showDialog<bool>(
    context: context,
    // Both actions are text buttons, which is what an adaptive dialog wants:
    // a filled pill inside a Cupertino alert reads as a foreign control
    // (checked on the iPhone 17 simulator), and this is the shape the work
    // item form's confirms already use.
    builder: (context) => AlertDialog.adaptive(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(verb),
        ),
      ],
    ),
  );

  Future<void> _abandon() async {
    final pr = _pr;
    if (pr == null) return;
    final ok = await _confirm(
      title: 'Abandon !${pr.id}?',
      body: 'The pull request can be reactivated later.',
      verb: 'Abandon',
    );
    if (ok != true || !mounted) return;
    final repo = context.read<PullRequestRepository>();
    await _act(() => repo.setStatus(widget.org, pr, 'abandoned'), settle: true);
  }

  Future<bool> _comment(String text) async {
    final pr = _pr;
    if (pr == null) return false;
    final repo = context.read<PullRequestRepository>();
    var ok = false;
    await _act(() async {
      await repo.addThread(widget.org, pr, content: text);
      ok = true;
    });
    return ok;
  }

  Future<bool> _reply(PrThread thread, String text) async {
    final pr = _pr;
    if (pr == null) return false;
    final repo = context.read<PullRequestRepository>();
    return _act(() => repo.reply(widget.org, pr, thread.id, text));
  }

  Future<bool> _setThreadStatus(PrThread thread, String status) async {
    final pr = _pr;
    if (pr == null) return false;
    final repo = context.read<PullRequestRepository>();
    return _act(() => repo.setThreadStatus(widget.org, pr, thread.id, status));
  }

  Future<void> _openFile(PrFileChange change) => _openDiff(change.path);

  /// Opens the file a thread is anchored to, at the iteration being
  /// viewed, so the comment can be read in context.
  ///
  /// The thread's own new-side line rides along as `?line=`, so the diff
  /// lands on the commented line instead of the top of the file (R5's
  /// Comments jump, research/22 §4.4). A left-side-only thread has no
  /// new-side line to land on, so it opens the file plain.
  Future<void> _openThread(PrThread thread) async {
    final path = thread.filePath;
    if (path == null) return;
    await _openDiff(path, line: thread.rightLine);
  }

  /// The diff is a route pushed over this page, and threads are written
  /// there too (a reply, a resolve, a new anchored thread). This page kept
  /// the threads it read before that, so the Comments tab showed the state
  /// from before the write until someone pulled (iPad walkthrough, defect
  /// 6). Re-read them when the diff comes back.
  Future<void> _openDiff(String path, {int? line}) async {
    final it = _iteration;
    if (it == null) return;
    await context.push(
      Uri(
        path:
            '${orgRoute(context, widget.org)}/pull-requests/${widget.id}/diff',
        queryParameters: {
          'path': path,
          'iteration': '$it',
          if (line != null) 'line': '$line',
        },
      ).toString(),
    );
    if (!mounted) return;
    await _reloadThreads();
  }

  /// Just the conversation, without the file list and the checks: what a
  /// write on another page can have changed.
  Future<void> _reloadThreads() async {
    final pr = _pr;
    if (pr == null) return;
    final repo = context.read<PullRequestRepository>();
    setState(() => _loading = true);
    try {
      final raw = await repo.rawThreads(widget.org, pr);
      if (!mounted) return;
      setState(() {
        _rawThreads = raw;
        _conversation = PullRequestRepository.conversation(raw);
      });
      // The names map is built from the threads, so a comment that names
      // somebody none of the earlier ones did has to re-run it, or its
      // `@<guid>` draws as "@someone" (M-D finding 1).
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
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openWorkItem(WorkItem item) {
    final pr = _pr;
    if (pr == null) return;
    context.push(
      Routes.workItemStandalone(
        AccountScope.of(context),
        widget.org,
        pr.projectName,
        '${item.id}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pr = _pr;
    final myVote = pr?.reviewer(_me)?.vote ?? PrVote.none;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('!${widget.id}'),
            if (pr != null)
              Text(
                '${pr.projectName} / ${pr.repositoryName}',
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
          if (pr != null && pr.isActive)
            PopupMenuButton<PrVote>(
              tooltip: 'Vote',
              offset: kTrailingMenuOffset,
              enabled: !_acting,
              icon: Icon(voteIcon(myVote), color: voteColor(context, myVote)),
              onSelected: _vote,
              itemBuilder: (context) => [
                for (final v in PrVote.values)
                  PopupMenuItem(
                    value: v,
                    child: Row(
                      children: [
                        Icon(voteIcon(v), color: voteColor(context, v)),
                        const SizedBox(width: Spacing.md),
                        Expanded(child: Text(v.label)),
                        if (v == myVote) const Icon(Icons.check, size: 18),
                      ],
                    ),
                  ),
              ],
            ),
          if (pr != null)
            PopupMenuButton<PrMoreAction>(
              tooltip: 'More',
              offset: kTrailingMenuOffset,
              enabled: !_acting,
              onSelected: _more,
              itemBuilder: (context) => [
                for (final a in prMoreActions(pr))
                  PopupMenuItem(value: a, child: Text(a.label)),
              ],
            ),
        ],
        bottom: CountedTabBar(
          controller: _tabs,
          tabs: [
            const TabCount('Overview'),
            TabCount('Files', _changes.length),
            TabCount('Comments', _conversation.length),
          ],
        ),
      ),
      bottomNavigationBar:
          pr == null || !pr.isActive || _tabs.index != _commentsTab
          ? null
          : CommentComposer(
              wikiPages: _wikiPages,
              onSubmit: _comment,
              busy: _acting,
              mentions: _mentions,
              attachments: _uploads,
              offline: _offline,
            ),
      // The project shell insets its own pages; this one is pushed over it,
      // and a phone in landscape reports 59 dp on each side (DESIGN §7).
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading || _acting || _changesLoading)
              const LinearProgressIndicator(),
            if (_error != null)
              ListTile(
                leading: Icon(Icons.error_outline, color: scheme.error),
                title: Text(_error!),
              ),
            Expanded(
              child: pr == null
                  ? (_loading
                        ? const Center(
                            child: CircularProgressIndicator.adaptive(),
                          )
                        : const SizedBox.shrink())
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        RefreshIndicator(
                          onRefresh: _load,
                          child: _Overview(
                            pr: pr,
                            checks: _checks,
                            policies: _policies,
                            conflicts: _conflicts,
                            requiredReviewers: _requiredReviewers,
                            meId: _me,
                            busy: _acting,
                            workItems: _workItems,
                            onWorkItemTap: _openWorkItem,
                            onLinkWorkItem: _linkWorkItem,
                            onUnlinkWorkItem: _unlinkWorkItem,
                            onPrimary: _primary,
                            onCancelAutoComplete: _cancelAutoComplete,
                            onEditLabels: _editLabels,
                            onAddReviewer: _addReviewer,
                            onReviewerAction: _reviewerAction,
                            mentionNames: _mentionNames,
                            attachments: _attachments,
                            onOpenMention: _openMention,
                          ),
                        ),
                        RefreshIndicator(
                          onRefresh: _load,
                          child: _Files(
                            changes: _changes,
                            iterations: _iterations,
                            iteration: _iteration,
                            viewed: _viewed.keys.toSet(),
                            onToggleViewed: _toggleViewed,
                            onSelectIteration: _selectIteration,
                            onTap: _openFile,
                          ),
                        ),
                        RefreshIndicator(
                          onRefresh: _load,
                          child: _Conversation(
                            threads: _activity
                                ? PullRequestRepository.conversation(
                                    _rawThreads,
                                    includeSystem: true,
                                  )
                                : _conversation,
                            activity: _activity,
                            onActivity: (v) => setState(() => _activity = v),
                            keyFor: (id) =>
                                _threadKeys.putIfAbsent(id, GlobalKey.new),
                            scroller: _threadScroll,
                            highlighted: _highlighted,
                            filter: _threadFilter,
                            onFilter: (f) => setState(() => _threadFilter = f),
                            canAct: pr.isActive,
                            busy: _acting,
                            mentions: _mentions,
                            mentionNames: _mentionNames,
                            attachments: _attachments,
                            uploads: _uploads,
                            wikiPages: _wikiPages,
                            offline: _offline,
                            onOpenMention: _openMention,
                            onReply: _reply,
                            onSetStatus: _setThreadStatus,
                            onOpenThread: _openThread,
                          ),
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

/// The detail page's overflow menu (R2). Complete and Set auto-complete are
/// deliberately not here: they belong to the merge box, which knows which
/// of the two the pull request's state allows.
enum PrMoreAction {
  edit('Edit…'),
  markDraft('Mark as draft…'),
  publish('Publish'),
  retarget('Change target branch…'),
  restartMerge('Restart merge'),
  abandon('Abandon…'),
  reactivate('Reactivate'),
  share('Share…'),
  copyLink('Copy link');

  const PrMoreAction(this.label);

  final String label;
}

/// Which overflow items this pull request's state allows, as a list so the
/// rules are testable without a pump.
List<PrMoreAction> prMoreActions(PullRequest pr) => [
  if (pr.isActive) ...[
    PrMoreAction.edit,
    if (pr.isDraft) PrMoreAction.publish else PrMoreAction.markDraft,
    PrMoreAction.retarget,
    PrMoreAction.restartMerge,
    PrMoreAction.abandon,
  ],
  if (pr.status == 'abandoned') PrMoreAction.reactivate,
  PrMoreAction.share,
  PrMoreAction.copyLink,
];

class _Overview extends StatelessWidget {
  const _Overview({
    required this.pr,
    required this.checks,
    required this.workItems,
    required this.onWorkItemTap,
    required this.onLinkWorkItem,
    required this.onUnlinkWorkItem,
    required this.onPrimary,
    required this.onCancelAutoComplete,
    required this.onEditLabels,
    required this.onAddReviewer,
    required this.onReviewerAction,
    this.policies,
    this.conflicts = const [],
    this.requiredReviewers = const {},
    this.meId,
    this.busy = false,
    this.mentionNames = const {},
    this.attachments,
    this.onOpenMention,
  });

  final PullRequest pr;

  /// The description is Markdown the service stores verbatim, so a `@<guid>`
  /// in it reaches the screen as a GUID unless it is resolved here (M9).
  final Map<String, String> mentionNames;

  /// Images and files the description links to.
  final InlineAttachments? attachments;
  final void Function(MentionKind kind, String id)? onOpenMention;
  final List<PrCheck> checks;
  final PrPolicySet? policies;
  final List<PrConflict> conflicts;
  final Map<String, IdentityRef> requiredReviewers;
  final String? meId;
  final bool busy;
  final List<WorkItem> workItems;
  final ValueChanged<WorkItem> onWorkItemTap;
  final VoidCallback onLinkWorkItem;
  final ValueChanged<WorkItem> onUnlinkWorkItem;
  final ValueChanged<PrPrimaryAction> onPrimary;
  final VoidCallback onCancelAutoComplete;
  final VoidCallback onEditLabels;
  final VoidCallback onAddReviewer;
  final void Function(PrReviewer reviewer, PrReviewerAction action)
  onReviewerAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ContentColumn(
      child: ListView(
        // Short pages must still answer a pull-to-refresh.
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: scrollEndPadding(context),
        children: [
          Padding(
            padding: Spacing.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(pr.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: Spacing.md),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      avatar: StateDot(
                        color: prStatusColor(context, pr.status),
                      ),
                      label: Text(pr.status),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (pr.isDraft) const DraftChip(),
                    Chip(
                      avatar: IdentityAvatar(
                        identity: pr.createdBy,
                        radius: 10,
                      ),
                      label: Text(pr.createdBy.displayName),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      avatar: const Icon(Icons.schedule, size: 16),
                      label: Text(relativeTime(pr.creationDate)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                Row(
                  children: [
                    Icon(
                      Icons.call_merge,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Spacing.xs),
                    Expanded(
                      child: Text(
                        '${pr.sourceBranch} → ${pr.targetBranch}',
                        style: BoardhopTheme.codeStyle(context),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Full width rather than in a column: it is about the whole pull
          // request, and its Cancel has to be found at a glance (R2).
          AutoCompleteBanner(
            pr: pr,
            checks: checks,
            busy: busy,
            onCancel: onCancelAutoComplete,
          ),
          // From tablet width the description sits beside the merge box,
          // labels, reviewers and linked work items.
          SideBySide(
            startFlex: 3,
            endFlex: 2,
            start: [
              _SectionTitle('Description'),
              Padding(
                padding: Spacing.pageHorizontal,
                child: (pr.description ?? '').trim().isEmpty
                    ? Text(
                        'No description.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : MentionMarkdown(
                        data: pr.description!,
                        names: mentionNames,
                        onOpen: onOpenMention,
                        attachments: attachments,
                      ),
              ),
            ],
            end: [
              MergeBox(
                pr: pr,
                checks: checks,
                policies: policies,
                conflicts: conflicts,
                requiredReviewers: requiredReviewers,
                busy: busy,
                onPrimary: onPrimary,
              ),
              LabelsSection(
                labels: pr.labels,
                canEdit: pr.isActive,
                busy: busy,
                onEdit: onEditLabels,
              ),
              ReviewersSection(
                pr: pr,
                meId: meId,
                busy: busy,
                onAdd: onAddReviewer,
                onAction: onReviewerAction,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.sm,
                  Spacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Linked work items (${workItems.length})',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (pr.isActive)
                      IconButton(
                        tooltip: 'Link a work item',
                        icon: const Icon(Icons.add_link),
                        onPressed: busy ? null : onLinkWorkItem,
                      ),
                  ],
                ),
              ),
              if (workItems.isEmpty)
                Padding(
                  padding: Spacing.pageHorizontal,
                  child: Text(
                    'None.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final w in workItems)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.link),
                  title: Text(
                    w.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${w.type} ${w.id} · ${w.state}'),
                  trailing: pr.isActive
                      ? IconButton(
                          tooltip: 'Unlink #${w.id}',
                          icon: const Icon(Icons.close),
                          onPressed: busy ? null : () => onUnlinkWorkItem(w),
                        )
                      : null,
                  onTap: () => onWorkItemTap(w),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Title and description in one small form (R2's Edit).
typedef PrEdit = ({String title, String description});

Future<PrEdit?> showPrEditSheet(
  BuildContext context, {
  required PullRequest pr,
  MentionSource? mentions,
}) {
  if (!context.breakpoint.isCompact) {
    return showDialog<PrEdit>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _PrEditSheet(pr: pr, mentions: mentions, dialog: true),
        ),
      ),
    );
  }
  return showModalBottomSheet<PrEdit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _PrEditSheet(pr: pr, mentions: mentions),
  );
}

class _PrEditSheet extends StatefulWidget {
  const _PrEditSheet({required this.pr, this.mentions, this.dialog = false});

  final PullRequest pr;
  final MentionSource? mentions;
  final bool dialog;

  @override
  State<_PrEditSheet> createState() => _PrEditSheetState();
}

class _PrEditSheetState extends State<_PrEditSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.pr.title,
  );

  /// The description is stored in wire form (`@<guid>`), and that is what
  /// goes back: text nobody touched round-trips unchanged, and anything
  /// picked from the `@` list this time is written as a new `@<guid>`.
  late final MentionController _description = MentionController(
    text: widget.pr.description ?? '',
  );

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
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Spacing.lg,
          widget.dialog ? Spacing.lg : Spacing.sm,
          Spacing.lg,
          Spacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Edit !${widget.pr.id}', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _title,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Title',
              ),
            ),
            const SizedBox(height: Spacing.md),
            MentionField(
              controller: _description,
              source: widget.mentions,
              minLines: 3,
              maxLines: 10,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Description',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: Spacing.sm,
              overflowSpacing: Spacing.sm,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _title.text.trim().isEmpty
                      ? null
                      : () => Navigator.of(context).pop((
                          title: _title.text.trim(),
                          description: _description
                              .toWire(MentionWire.markdown)
                              .trim(),
                        )),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Spacing.lg,
      Spacing.lg,
      Spacing.lg,
      Spacing.sm,
    ),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// "Iteration 3 of 4 · push · 2 h ago" with a menu of all iterations.
class IterationPicker extends StatelessWidget {
  const IterationPicker({
    super.key,
    required this.iterations,
    required this.selected,
    required this.onSelect,
    this.dense = false,
  });

  final List<PrIteration> iterations;
  final int? selected;
  final ValueChanged<int> onSelect;
  final bool dense;

  static String describe(PrIteration it) => [
    if (it.reason != null && it.reason!.isNotEmpty) it.reason!,
    if (it.createdDate != null) relativeTime(it.createdDate),
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = iterations.cast<PrIteration?>().firstWhere(
      (i) => i?.id == selected,
      orElse: () => null,
    );
    final title = current == null
        ? 'Iterations'
        : 'Iteration ${current.id} of ${iterations.length}';
    return PopupMenuButton<int>(
      tooltip: 'Choose iteration',
      enabled: iterations.length > 1,
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final it in iterations.reversed)
          PopupMenuItem(
            value: it.id,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: it.id == selected
                      ? const Icon(Icons.check, size: 18)
                      : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Iteration ${it.id}'),
                      Text(
                        [
                          if (it.description.isNotEmpty) it.description,
                          describe(it),
                        ].join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      child: dense
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    current == null ? '' : 'it. ${current.id}',
                    style: theme.textTheme.labelLarge,
                  ),
                  if (iterations.length > 1)
                    const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            )
          : ListTile(
              leading: const Icon(Icons.history),
              title: Text(title),
              subtitle: current == null
                  ? null
                  : Text(
                      [
                        if (current.description.isNotEmpty) current.description,
                        describe(current),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: iterations.length > 1
                  ? const Icon(Icons.arrow_drop_down)
                  : null,
            ),
    );
  }
}

class _Files extends StatelessWidget {
  const _Files({
    required this.changes,
    required this.iterations,
    required this.iteration,
    required this.onSelectIteration,
    required this.onTap,
    this.viewed = const {},
    required this.onToggleViewed,
  });

  final List<PrFileChange> changes;
  final List<PrIteration> iterations;
  final int? iteration;
  final ValueChanged<int> onSelectIteration;
  final ValueChanged<PrFileChange> onTap;

  /// Paths marked as read on this device (R8). Azure DevOps has no
  /// server-side viewed state, so this is local and per account.
  final Set<String> viewed;
  final ValueChanged<PrFileChange> onToggleViewed;

  static IconData _icon(String changeType) => switch (changeType) {
    'add' => Icons.add_circle_outline,
    'delete' => Icons.remove_circle_outline,
    'rename' || 'rename, edit' => Icons.drive_file_rename_outline,
    _ => Icons.edit_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ContentColumn(
      child: ListView(
        // Short pages must still answer a pull-to-refresh.
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: scrollEndPadding(context),
        children: [
          if (iterations.isNotEmpty)
            IterationPicker(
              iterations: iterations,
              selected: iteration,
              onSelect: onSelectIteration,
            ),
          if (changes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.sm,
              ),
              child: Text(
                '${changes.where((c) => viewed.contains(c.path)).length}'
                '/${changes.length} viewed',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (iterations.isNotEmpty) const Divider(height: 1),
          if (changes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Spacing.xl),
              child: Text(
                'No changed files.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final c in changes)
            ListTile(
              leading: Icon(_icon(c.changeType)),
              title: Text(
                c.path.substring(c.path.lastIndexOf('/') + 1),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.path,
                    style: BoardhopTheme.codeStyle(context)
                        .copyWith(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    c.changeType,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              // The check is the whole trailing slot: at xxxL a change type
              // beside it left the title no room (DESIGN §4).
              trailing: Checkbox(
                value: viewed.contains(c.path),
                semanticLabel: 'Viewed',
                onChanged: (_) => onToggleViewed(c),
              ),
              onTap: () => onTap(c),
            ),
        ],
      ),
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.threads,
    required this.activity,
    required this.onActivity,
    required this.keyFor,
    required this.scroller,
    required this.highlighted,
    required this.filter,
    required this.onFilter,
    required this.canAct,
    required this.busy,
    required this.onReply,
    required this.onSetStatus,
    required this.onOpenThread,
    this.mentions,
    this.mentionNames = const {},
    this.attachments,
    this.uploads,
    this.wikiPages,
    this.offline = false,
    this.onOpenMention,
  });

  final List<PrThread> threads;

  /// The Activity chip (R11): the system threads — votes, pushes, status
  /// and auto-complete changes — shown as quiet rows beside the comments.
  /// The default view is comments only, as it always was.
  final bool activity;
  final ValueChanged<bool> onActivity;

  /// One stable key per thread id, so `?thread={id}` has something to
  /// scroll to (research/14 §4.2).
  final GlobalKey Function(int id) keyFor;

  /// The thread list's own controller, so the anchor can page down to a
  /// thread that has not been built yet.
  final ScrollController scroller;

  /// The thread a deep link landed on; tinted for two seconds.
  final int? highlighted;

  final PrConversationFilter filter;
  final ValueChanged<PrConversationFilter> onFilter;
  final bool canAct;
  final bool busy;
  final Future<bool> Function(PrThread thread, String text) onReply;
  final Future<bool> Function(PrThread thread, String status) onSetStatus;
  final ValueChanged<PrThread> onOpenThread;

  /// What the reply boxes offer behind `@`, `#` and `!`, the names the
  /// comments' `@<guid>` runs read as, and where a tapped reference goes.
  final MentionSource? mentions;
  final Map<String, String> mentionNames;

  /// Images and files the comments carry, and where a file picked into a
  /// reply is uploaded (research/17 §4).
  final InlineAttachments? attachments;
  final AttachmentSource? uploads;

  /// The project's wikis, for the reply boxes' book button (research/20
  /// K12).
  final WikiPageSource? wikiPages;
  final bool offline;
  final void Function(MentionKind kind, String id)? onOpenMention;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (threads.isEmpty) {
      return Center(
        child: Text(
          'No comments yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    // A system thread has no status a reader set, so the Active/Resolved
    // filters are applied to the comments only and the events stay in
    // place in the timeline.
    final comments = [
      for (final t in threads)
        if (!t.isSystem) t,
    ];
    final shown =
        [
          ...PullRequestRepository.filterConversation(comments, filter),
          for (final t in threads)
            if (t.isSystem) t,
        ]..sort((a, b) {
          final ta = a.startedAt?.millisecondsSinceEpoch ?? 0;
          final tb = b.startedAt?.millisecondsSinceEpoch ?? 0;
          return ta == tb ? a.id.compareTo(b.id) : ta.compareTo(tb);
        });
    final counts = {
      for (final f in PrConversationFilter.values)
        f: PullRequestRepository.filterConversation(comments, f).length,
    };
    return ContentColumn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.sm,
              Spacing.lg,
              0,
            ),
            child: Row(
              children: [
                for (final f in PrConversationFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: Spacing.sm),
                    child: ChoiceChip(
                      label: Text('${f.label} (${counts[f]})'),
                      selected: filter == f,
                      onSelected: (_) => onFilter(f),
                    ),
                  ),
                ChoiceChip(
                  avatar: const Icon(Icons.history, size: 16),
                  label: const Text('Activity'),
                  selected: activity,
                  onSelected: onActivity,
                ),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      switch (filter) {
                        PrConversationFilter.active =>
                          'Every comment has been resolved.',
                        PrConversationFilter.resolved =>
                          'No comment has been resolved yet.',
                        PrConversationFilter.all => 'No comments yet.',
                      },
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    controller: scroller,
                    physics: const AlwaysScrollableScrollPhysics(),
                    // A swipe down the thread list puts the keyboard
                    // away while a reply is being written.
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      Spacing.sm,
                      Spacing.lg,
                      Spacing.xxl,
                    ),
                    children: [
                      for (final t in shown)
                        if (t.isSystem)
                          _SystemRow(key: keyFor(t.id), thread: t)
                        else
                          Padding(
                            key: keyFor(t.id),
                            padding: const EdgeInsets.only(bottom: Spacing.md),
                            child: AnchorHighlight(
                              active: t.id == highlighted,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (t.isFileThread)
                                    _ThreadFileHeader(
                                      thread: t,
                                      onTap: () => onOpenThread(t),
                                    ),
                                  ThreadCard(
                                    thread: t,
                                    canAct: canAct,
                                    busy: busy,
                                    mentions: mentions,
                                    mentionNames: mentionNames,
                                    attachments: attachments,
                                    uploads: uploads,
                                    wikiPages: wikiPages,
                                    offline: offline,
                                    onOpenMention: onOpenMention,
                                    onReply: (text) => onReply(t, text),
                                    onSetStatus: (status) =>
                                        onSetStatus(t, status),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One system thread as a quiet row: a vote, a push, a status change, an
/// auto-complete or a retarget (R11). The service pre-renders the sentence
/// and [PrThread] has already substituted the `{n}` identity placeholders.
class _SystemRow extends StatelessWidget {
  const _SystemRow({super.key, required this.thread});

  final PrThread thread;

  static IconData iconFor(String? kind) => switch (kind) {
    'VoteUpdate' => Icons.how_to_vote_outlined,
    'ResetMultipleVotes' => Icons.restart_alt,
    'ReviewersUpdate' => Icons.group_add_outlined,
    'StatusUpdate' => Icons.flag_outlined,
    'RefUpdate' => Icons.upload_outlined,
    'AutoCompleteUpdate' => Icons.schedule_send,
    'IsDraftUpdate' => Icons.edit_note,
    'TargetChanged' => Icons.alt_route,
    'PolicyStatusUpdate' => Icons.policy_outlined,
    _ => Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text =
        thread.systemText ??
        (thread.comments.isEmpty ? '' : thread.comments.first.content);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            iconFor(thread.systemKind),
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            relativeTime(thread.startedAt ?? thread.publishedDate),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Above a file-anchored thread: which file and line it hangs on, tapping
/// opens the diff there.
class _ThreadFileHeader extends StatelessWidget {
  const _ThreadFileHeader({required this.thread, required this.onTap});

  final PrThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final path = thread.filePath ?? '';
    final name = path.substring(path.lastIndexOf('/') + 1);
    final line = thread.rightLine ?? thread.leftLine;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.sm,
          Spacing.xs,
          Spacing.sm,
          Spacing.xs,
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 14,
              color: scheme.primary,
            ),
            const SizedBox(width: Spacing.xs),
            Expanded(
              child: Text(
                line == null ? name : '$name:$line',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
