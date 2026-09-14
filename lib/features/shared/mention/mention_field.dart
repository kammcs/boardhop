import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart';

import '../../../core/http/ado_exceptions.dart';
import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import '../../search/widgets/work_item_hit_tile.dart' show WorkItemTypeTile;
import '../../work_items/widgets/work_item_visuals.dart';
import 'mention_controller.dart';
import 'mention_source.dart';
import '../../../core/text/mention.dart';

/// A real [TextField] that offers people, work items and pull requests when
/// the caret sits after `@`, `#` or `!`.
///
/// It is a drop-in for the `TextField` each composer builds today — the same
/// parameters, and a `TextField` still in the tree so every existing
/// `find.byType(TextField)` keeps working. `source: null` is a plain field
/// with no list at all, which is what every host that has not been wired yet
/// passes.
///
/// The list is an [OverlayPortal] child laid out with Flutter 3.47's
/// `RawAutocomplete` maths: deflate the overlay by the safe area and the
/// keyboard, open into whichever side has more room (up over a phone's
/// keyboard, down on a tablet), and shrink away when the field has scrolled
/// out of sight. Copying that is the difference between a two-week feature
/// and a six-week one (r2-ux §4b).
class MentionField extends StatefulWidget {
  const MentionField({
    super.key,
    required this.controller,
    this.source,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.minLines,
    this.maxLines = 1,
    this.textInputAction,
    this.enabled,
    this.style,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  /// The composer's controller. It has to be a [MentionController] because
  /// the tokens, the trigger and the wire form all live on it.
  final MentionController controller;

  /// Null for a plain field.
  final MentionSource? source;

  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final int? minLines;
  final int? maxLines;
  final TextInputAction? textInputAction;
  final bool? enabled;
  final TextStyle? style;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  State<MentionField> createState() => _MentionFieldState();
}

class _MentionFieldState extends State<MentionField> {
  /// The directory search is debounced by this, exactly as the assignee
  /// sheet debounces its own (M5).
  static const _debounceFor = Duration(milliseconds: 300);

  /// Below this a query is a cached lookup, above it the work item search
  /// API, so only the longer one is worth debouncing (M8).
  static const _artifactSearchQuery = 3;

  /// About five rows before the list scrolls inside itself (M4).
  static const _visibleRows = 5;

  /// Enough room for one row even when the field is jammed against an edge;
  /// `RawAutocomplete` uses the same floor.
  static const double _minUsableHeight = kMinInteractiveDimension;

  /// A list wider than this on a tablet makes the eye travel; the pickers
  /// already cap their dialog here.
  static const double _maxWidth = 480;

  final _overlay = OverlayPortalController();

  FocusNode? _ownedFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownedFocus ??= FocusNode());

  Timer? _debounce;
  int _request = 0;

  MentionTrigger? _trigger;

  /// The trigger the user dismissed with Escape, as `<character><start>`, so
  /// the list does not spring back on the next keystroke.
  String? _dismissed;

  bool _bandsLoaded = false;
  List<IdentityRef> _participants = const [];
  List<IdentityRef> _recents = const [];
  List<IdentityRef> _members = const [];
  List<IdentityRef> _hits = const [];
  List<ArtifactSuggestion> _found = const [];

  /// The value the field held before the change being handled, so a Return
  /// that arrives as an inserted newline can be told apart from any other
  /// edit (see [_returnWhileOpen]).
  TextEditingValue? _previous;

  /// What a pick just did, kept for exactly one more change: `from` is the
  /// text it replaced, `to` and `tokens` what it wrote. See [_onChanged].
  ({TextEditingValue from, TextEditingValue to, List<MentionToken> tokens})?
  _pickGuard;

  bool _loading = false;
  String? _error;
  int _highlight = 0;
  int? _errorRow;
  String? _rowError;
  int? _resolvingRow;

  late final Map<Type, Action<Intent>> _actions = {
    _MentionPreviousIntent: _GatedAction<_MentionPreviousIntent>(
      onInvoke: (_) => _move(-1),
      enabled: () => _navigable,
    ),
    _MentionNextIntent: _GatedAction<_MentionNextIntent>(
      onInvoke: (_) => _move(1),
      enabled: () => _navigable,
    ),
    _MentionPickIntent: _GatedAction<_MentionPickIntent>(
      onInvoke: (_) {
        _pick(_highlight);
        return null;
      },
      enabled: () => _navigable,
    ),
    _MentionCloseIntent: _GatedAction<_MentionCloseIntent>(
      onInvoke: (_) {
        _dismiss();
        return null;
      },
      enabled: () => _open,
    ),
  };

  /// Up, Down and Enter are bound only while there is something to move
  /// through. A disabled action falls through to the field, so the arrow keys
  /// never stop moving the caret and Enter still inserts a newline — the
  /// worst possible regression in a comment box (M12).
  static const Map<ShortcutActivator, Intent> _shortcuts = {
    SingleActivator(LogicalKeyboardKey.arrowUp): _MentionPreviousIntent(),
    SingleActivator(LogicalKeyboardKey.arrowDown): _MentionNextIntent(),
    SingleActivator(LogicalKeyboardKey.enter): _MentionPickIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): _MentionPickIntent(),
    SingleActivator(LogicalKeyboardKey.escape): _MentionCloseIntent(),
    // Tab is deliberately unbound: on a tablet with a keyboard, stealing it
    // from form traversal is the worse trade.
  };

  bool get _open => _overlay.isShowing;
  bool get _navigable => _open && _rowCount > 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(MentionField old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _previous = null;
    }
    if (old.focusNode != widget.focusNode) {
      old.focusNode?.removeListener(_onFocusChanged);
      _focus.addListener(_onFocusChanged);
    }
    if (!identical(old.source, widget.source)) {
      _bandsLoaded = false;
      _participants = _recents = _members = _hits = const [];
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onChanged);
    widget.focusNode?.removeListener(_onFocusChanged);
    _ownedFocus?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- trigger

  void _onFocusChanged() {
    // Losing focus is also how a tap outside closes the list: the options are
    // inside a TextFieldTapRegion, so tapping one is not "outside".
    if (!_focus.hasFocus && _open) _close();
  }

  void _onChanged() {
    final before = _previous;
    final value = widget.controller.value;
    _previous = value;
    final guard = _pickGuard;
    _pickGuard = null;
    // On iOS the Return key reaches the `Shortcuts` binding *and* is turned
    // into an insertion by the platform's text input, which computed it from
    // the text as it was before the pick. That stale editing state arrives
    // after the token has been written and overwrites it (M-D finding 2):
    // put the pick back.
    if (guard != null && _returnWhileOpen(guard.from, value)) {
      widget.controller.restore(guard.to, guard.tokens);
      return;
    }
    // M12's Enter binding is a `Shortcuts` entry, and on iOS a hardware
    // Return never reaches it: the key is consumed by the text input system
    // and comes back as an inserted newline (verified on the iPhone 17
    // simulator, M-D finding 2). Catch it here instead, so Return picks the
    // highlighted row on every platform and a soft-keyboard Return does the
    // same thing as a hardware one.
    if (before != null && _navigable && _returnWhileOpen(before, value)) {
      _previous = before;
      widget.controller.value = before;
      unawaited(_pick(_highlight));
      return;
    }
    final source = widget.source;
    if (source == null || widget.enabled == false) {
      if (_open) _close();
      return;
    }
    final trigger = widget.controller.activeTrigger;
    if (trigger == null || !source.supports(trigger.kind)) {
      _trigger = null;
      _dismissed = null;
      if (_open) _close();
      return;
    }
    if (_dismissed == '${trigger.character}${trigger.range.start}') {
      _trigger = trigger;
      if (_open) _close();
      return;
    }

    final previous = _trigger;
    final fresh =
        previous == null ||
        previous.character != trigger.character ||
        previous.range.start != trigger.range.start;
    _trigger = trigger;

    if (fresh) {
      _request++;
      _debounce?.cancel();
      setState(() {
        _hits = const [];
        _found = const [];
        _error = null;
        _errorRow = null;
        _rowError = null;
        _resolvingRow = null;
        _highlight = 0;
        _loading = false;
      });
      unawaited(_loadBands(source));
      _fetch(trigger, source);
    } else if (previous.query != trigger.query) {
      setState(() {
        _highlight = 0;
        _errorRow = null;
        _rowError = null;
      });
      _fetch(trigger, source);
    } else {
      setState(() {});
    }
    if (!_open && _focus.hasFocus) _overlay.show();
  }

  /// True when the only difference between the two values is one newline
  /// typed at a collapsed caret — what a Return looks like once the platform
  /// has turned it into text. Anything else (a paste carrying a newline, an
  /// IME composition, a replaced selection) is left alone.
  static bool _returnWhileOpen(TextEditingValue before, TextEditingValue now) {
    if (!before.selection.isValid || !before.selection.isCollapsed) return false;
    if (!now.selection.isCollapsed) return false;
    if (before.composing.isValid || now.composing.isValid) return false;
    final at = before.selection.baseOffset;
    if (at < 0 || at > before.text.length) return false;
    if (now.selection.baseOffset != at + 1) return false;
    return now.text ==
        '${before.text.substring(0, at)}\n${before.text.substring(at)}';
  }

  /// The three cached bands, loaded once per field. Offline is just "the call
  /// throws": whatever did answer stays on screen and the failure becomes one
  /// quiet line (M13).
  Future<void> _loadBands(MentionSource source) async {
    if (_bandsLoaded) return;
    _bandsLoaded = true;
    await Future.wait([
      _band(source.participants, (v) => _participants = v),
      _band(source.recents, (v) => _recents = v),
      _band(source.members, (v) => _members = v),
    ]);
  }

  Future<void> _band(
    Future<List<IdentityRef>> Function()? load,
    void Function(List<IdentityRef>) assign,
  ) async {
    if (load == null) return;
    try {
      final people = await load();
      if (!mounted) return;
      setState(() => assign(people));
    } on AdoException catch (e) {
      if (!mounted) return;
      setState(() => _error ??= e.message);
    }
  }

  /// Ask the remote half for this query, debounced, last request wins.
  void _fetch(MentionTrigger trigger, MentionSource source) {
    _debounce?.cancel();
    final id = ++_request;
    final query = trigger.query.trim();

    if (trigger.kind == MentionKind.person) {
      if (source.search == null ||
          query.length < MentionSuggestions.minSearchQuery) {
        if (_hits.isNotEmpty || _loading) {
          setState(() {
            _hits = const [];
            _loading = false;
          });
        }
        return;
      }
      setState(() => _loading = true);
      _debounce = Timer(_debounceFor, () async {
        try {
          final hits = await source.search!(query);
          if (!mounted || id != _request) return;
          setState(() {
            _hits = hits;
            _loading = false;
          });
        } on AdoException catch (e) {
          if (!mounted || id != _request) return;
          setState(() {
            _error = e.message;
            _loading = false;
          });
        }
      });
      return;
    }

    final load = trigger.kind == MentionKind.workItem
        ? source.workItems
        : source.pullRequests;
    if (load == null) return;
    Future<void> run() async {
      try {
        final found = await load(query);
        if (!mounted || id != _request) return;
        setState(() {
          _found = found;
          _loading = false;
        });
      } on AdoException catch (e) {
        if (!mounted || id != _request) return;
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }

    // The cached lists answer at once; only the search API is worth waiting
    // for (M8).
    if (query.length < _artifactSearchQuery) {
      unawaited(run());
    } else {
      setState(() => _loading = true);
      _debounce = Timer(_debounceFor, run);
    }
  }

  void _close() {
    _debounce?.cancel();
    if (_overlay.isShowing) _overlay.hide();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _highlight = 0;
      _errorRow = null;
      _rowError = null;
      _resolvingRow = null;
    });
  }

  void _dismiss() {
    final trigger = _trigger;
    if (trigger != null) {
      _dismissed = '${trigger.character}${trigger.range.start}';
    }
    _close();
  }

  // ------------------------------------------------------------ suggestions

  List<PersonSuggestion> get _people {
    final source = widget.source;
    final trigger = _trigger;
    if (source == null || trigger == null) return const [];
    return MentionSuggestions.people(
      query: trigger.query,
      participants: _participants,
      participantReason: source.participantReason,
      recents: _recents,
      members: _members,
      hits: _hits,
      me: source.me,
    );
  }

  List<ArtifactSuggestion> get _artifacts =>
      MentionSuggestions.artifacts(_found, query: _trigger?.query ?? '');

  int get _rowCount =>
      _trigger?.kind == MentionKind.person ? _people.length : _artifacts.length;

  /// Dart's `%` is never negative for a positive divisor, so this wraps in
  /// both directions: Up from the first row lands on the last.
  Object? _move(int delta) {
    final count = _rowCount;
    if (count == 0) return null;
    setState(() => _highlight = (_highlight + delta) % count);
    return null;
  }

  Future<void> _pick(int index) async {
    final source = widget.source;
    final trigger = _trigger;
    if (source == null || trigger == null || !_open) return;
    if (_resolvingRow != null) return;
    final from = widget.controller.value;
    setState(() {
      _errorRow = null;
      _rowError = null;
    });

    if (trigger.kind == MentionKind.person) {
      final list = _people;
      if (index < 0 || index >= list.length) return;
      var person = list[index].person;
      if (person.id == null || person.id!.isEmpty) {
        final resolve = source.resolve;
        if (resolve == null) {
          setState(() {
            _errorRow = index;
            _rowError = 'No identity id for this person.';
          });
          return;
        }
        // M15: the GUID is resolved while the list is still open, so a
        // failure is visible here and not at post time.
        setState(() => _resolvingRow = index);
        try {
          person = await resolve(person);
        } on AdoException catch (e) {
          if (!mounted) return;
          setState(() {
            _resolvingRow = null;
            _errorRow = index;
            _rowError = e.message;
          });
          return;
        }
        if (!mounted) return;
        setState(() => _resolvingRow = null);
        if (person.id == null || person.id!.isEmpty) {
          setState(() {
            _errorRow = index;
            _rowError =
                'Azure DevOps has no identity id for ${person.displayName}.';
          });
          return;
        }
      }
      widget.controller.insertToken(
        MentionKind.person,
        person.id,
        '@${person.displayName}',
        replacing: _targetRange(trigger),
      );
      _rememberPick(from);
      source.onPicked?.call(person);
    } else {
      final list = _artifacts;
      if (index < 0 || index >= list.length) return;
      final item = list[index];
      widget.controller.insertToken(
        item.kind,
        item.id,
        item.label,
        replacing: _targetRange(trigger),
      );
      _rememberPick(from);
    }
    _close();
  }

  void _rememberPick(TextEditingValue from) {
    _pickGuard = (
      from: from,
      to: widget.controller.value,
      tokens: widget.controller.tokens,
    );
  }

  /// The range to replace, re-read after an await in case the user kept
  /// typing while the GUID was being resolved.
  TextRange _targetRange(MentionTrigger trigger) {
    final now = widget.controller.activeTrigger;
    if (now != null &&
        now.character == trigger.character &&
        now.range.start == trigger.range.start) {
      return now.range;
    }
    return trigger.range;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlay,
      overlayChildBuilder: _buildOptions,
      child: TextFieldTapRegion(
        child: Shortcuts(
          shortcuts: _shortcuts,
          child: Actions(actions: _actions, child: _buildField(context)),
        ),
      ),
    );
  }

  Widget _buildField(BuildContext context) => TextField(
    controller: widget.controller,
    focusNode: _focus,
    decoration: widget.decoration,
    minLines: widget.minLines,
    maxLines: widget.maxLines,
    textInputAction: widget.textInputAction,
    enabled: widget.enabled,
    style: widget.style,
    autofocus: widget.autofocus,
    onChanged: widget.onChanged,
    onSubmitted: widget.onSubmitted,
  );

  Widget _buildOptions(BuildContext context, OverlayChildLayoutInfo info) {
    if (info.childPaintTransform.determinant() == 0.0) {
      // The field has scrolled out of sight (a reply box inside a thread
      // list): draw nothing rather than an orphan list.
      return const SizedBox.shrink();
    }
    final fieldSize = info.childSize;
    final invert = info.childPaintTransform.clone()..invert();
    final overlayRect = MediaQuery.paddingOf(context).deflateRect(
      MediaQuery.viewInsetsOf(context)
          .deflateRect(Offset.zero & info.overlaySize),
    );
    final rectInField = MatrixUtils.transformRect(invert, overlayRect);

    final spaceAbove = -rectInField.top;
    final spaceBelow = rectInField.bottom - fieldSize.height;
    // `mostSpace`: above the field over a phone's keyboard, below it on a
    // tablet where the field sits high (M4).
    final opensUp = spaceAbove > spaceBelow;
    final box = Size(
      fieldSize.width,
      math.max(opensUp ? spaceAbove : spaceBelow, _minUsableHeight),
    );
    final originY = opensUp ? rectInField.top : rectInField.bottom - box.height;
    final transform = info.childPaintTransform.clone()
      ..translateByDouble(0, originY, 0, 1);

    final width = context.breakpoint.isCompact
        ? fieldSize.width
        : math.min(fieldSize.width, _maxWidth);

    return Transform(
      transform: transform,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints.tight(box),
          child: Align(
            alignment: opensUp
                ? AlignmentDirectional.bottomStart
                : AlignmentDirectional.topStart,
            child: TextFieldTapRegion(
              // The options never take focus: Tab has to leave the composer,
              // not detour into the list.
              child: ExcludeFocus(
                child: SizedBox(
                  width: width,
                  child: _buildCard(context, box.height),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, double available) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final person = _trigger?.kind == MentionKind.person;
    final rows = _rowCount;
    // Five rows, grown with the text scale, but never past the space the
    // field actually has.
    final cap = MediaQuery.textScalerOf(context)
        .scale(kMinTapTarget + Spacing.sm);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.max(
            math.min(available - Spacing.sm, _visibleRows * cap),
            _minUsableHeight,
          ),
        ),
        child: Material(
          // Named so a test can measure the panel without guessing which
          // Material it is.
          key: const Key('mentionOptions'),
          elevation: 3,
          color: scheme.surfaceContainerHigh,
          borderRadius: Radii.card,
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              Flexible(
                child: rows == 0
                    ? _quiet(
                        context,
                        person
                            ? 'No one matches'
                            : _trigger?.kind == MentionKind.pullRequest
                            ? 'No pull request matches'
                            : 'No work item matches',
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: rows,
                        itemBuilder: (context, index) => person
                            ? _personRow(context, index, _people[index])
                            : _artifactRow(context, index, _artifacts[index]),
                      ),
              ),
              if (_error != null) _quiet(context, _error!, error: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quiet(BuildContext context, String text, {bool error = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: error
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _personRow(BuildContext context, int index, PersonSuggestion person) {
    final theme = Theme.of(context);
    final failed = _errorRow == index ? _rowError : null;
    final secondary = failed ?? person.secondary;
    return _Row(
      selected: index == _highlight,
      onTap: () => _pick(index),
      leading: IdentityAvatar(identity: person.person, radius: 14),
      title: _Highlighted(
        text: person.person.displayName,
        ranges: person.matches,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: secondary,
      subtitleIsError: failed != null,
      busy: _resolvingRow == index,
    );
  }

  Widget _artifactRow(
    BuildContext context,
    int index,
    ArtifactSuggestion item,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = <String>[
      if (item.kind == MentionKind.workItem)
        '${item.typeName ?? 'Work item'} ${item.label}'
      else
        'Pull request ${item.label}',
      if (item.state != null && item.state!.isNotEmpty) item.state!,
    ].join(' · ');
    return _Row(
      selected: index == _highlight,
      onTap: () => _pick(index),
      leading: item.kind == MentionKind.workItem
          ? WorkItemTypeTile(type: item.typeName ?? '', size: 32)
          : Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: Radii.chip,
              ),
              child: Icon(
                Icons.call_merge,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
            ),
      title: _Highlighted(
        text: item.title,
        ranges: item.matches,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: meta,
      subtitleIsError: false,
      busy: false,
    );
  }
}

/// One row of the list: at least [kMinTapTarget] tall, everything ellipsised
/// so nothing overflows at accessibility text sizes.
class _Row extends StatelessWidget {
  const _Row({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.subtitleIsError,
    required this.busy,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget leading;
  final Widget title;
  final String? subtitle;
  final bool subtitleIsError;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? scheme.surfaceContainerHighest : null,
        constraints: const BoxConstraints(minHeight: kMinTapTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: subtitleIsError
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (busy) ...[
              const SizedBox(width: Spacing.sm),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A name with the matched letters in bold — weight only, never a different
/// size, so the row's height does not jump as the query narrows.
class _Highlighted extends StatelessWidget {
  const _Highlighted({
    required this.text,
    required this.ranges,
    required this.style,
  });

  final String text;
  final List<TextRange> ranges;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (ranges.isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final spans = <InlineSpan>[];
    var at = 0;
    for (final range in ranges) {
      if (range.start < at || range.end > text.length) continue;
      if (range.start > at) {
        spans.add(TextSpan(text: text.substring(at, range.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      at = range.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _MentionPreviousIntent extends Intent {
  const _MentionPreviousIntent();
}

class _MentionNextIntent extends Intent {
  const _MentionNextIntent();
}

class _MentionPickIntent extends Intent {
  const _MentionPickIntent();
}

class _MentionCloseIntent extends Intent {
  const _MentionCloseIntent();
}

/// An action that consumes its key only while the list can use it, so every
/// binding falls through to the text field when the list is closed.
class _GatedAction<T extends Intent> extends CallbackAction<T> {
  _GatedAction({required super.onInvoke, required this.enabled});

  final bool Function() enabled;

  @override
  bool isEnabled(covariant T intent) => enabled();

  @override
  bool consumesKey(covariant T intent) => enabled();
}
