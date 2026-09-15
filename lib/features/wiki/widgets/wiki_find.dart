import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/theme.dart';

/// Find-in-page for the wiki reader (research/20 K4).
///
/// The reader owns one of these; the body registers a key per drawn hit as
/// it builds and the bar drives the term and the up/down step. Two things
/// make it less obvious than it looks:
///
/// * `MarkdownBody` re-parses only when its **data** or its style sheet
///   changes, not when its syntaxes do, so the body has to be re-keyed on
///   the term for a new `WikiMarkSyntax` to take effect. [pass] is that key;
/// * a hit's key can only exist for a section that has been **built**, which
///   on the lazy body is the ones near the viewport. There, the count comes
///   from scanning the source instead ([sectionCounts]) and a step scrolls
///   to the section rather than to the run.
class WikiFindController extends ChangeNotifier {
  String _term = '';
  bool _open = false;
  int _index = 0;
  int _pass = 0;
  final List<GlobalKey> _hits = <GlobalKey>[];
  List<int> _sectionCounts = const [];
  bool _lazy = false;

  /// What is being looked for. Empty means the bar is idle.
  String get term => _term;

  /// Whether the find bar is on screen.
  bool get isOpen => _open;

  /// Changes whenever the body has to be re-parsed.
  int get pass => _pass;

  /// The hit the up/down buttons are on, 0-based.
  int get index => _index;

  /// How many hits the page has.
  int get total =>
      _lazy ? _sectionCounts.fold<int>(0, (sum, n) => sum + n) : _hits.length;

  /// "3 of 12", or null when there is nothing to say yet.
  String? get label {
    if (_term.isEmpty) return null;
    if (total == 0) return 'No matches';
    return '${_index + 1} of $total';
  }

  void open() {
    if (_open) return;
    _open = true;
    notifyListeners();
  }

  void close() {
    if (!_open && _term.isEmpty) return;
    _open = false;
    _term = '';
    _index = 0;
    _hits.clear();
    _sectionCounts = const [];
    _pass++;
    notifyListeners();
  }

  set term(String value) {
    final next = value.trim();
    if (next == _term) return;
    _term = next;
    _index = 0;
    _hits.clear();
    _pass++;
    notifyListeners();
  }

  /// The body is about to build a pass: forget the keys of the last one.
  void beginPass() => _hits.clear();

  /// One drawn hit, in document order.
  GlobalKey register() {
    final key = GlobalKey(debugLabel: 'wiki-find-${_hits.length}');
    _hits.add(key);
    return key;
  }

  /// The lazy body's per-section counts, scanned from the source.
  void useSectionCounts(List<int> counts) {
    _lazy = true;
    _sectionCounts = List.unmodifiable(counts);
  }

  /// The eager body counts what it drew.
  void useDrawnHits() {
    _lazy = false;
    _sectionCounts = const [];
  }

  /// Tells listeners what the finished pass found. Called after the frame,
  /// because the count is only known once the body has been built.
  void settle() {
    if (_index >= total) _index = total == 0 ? 0 : total - 1;
    notifyListeners();
  }

  void next() => _step(1);

  void previous() => _step(-1);

  void _step(int by) {
    if (total == 0) return;
    _index = (_index + by) % total;
    if (_index < 0) _index += total;
    notifyListeners();
  }

  /// Where hit [index] is: the key of the run when it has been drawn, else
  /// the section to jump to on the lazy body.
  ({GlobalKey? key, int? section}) get target {
    if (!_lazy && _index < _hits.length) {
      return (key: _hits[_index], section: null);
    }
    var left = _index;
    for (var section = 0; section < _sectionCounts.length; section++) {
      if (left < _sectionCounts[section]) return (key: null, section: section);
      left -= _sectionCounts[section];
    }
    return (key: null, section: null);
  }
}

/// The find bar, which lives in the reader's app bar rather than over the
/// body.
///
/// Above the keyboard by construction: the reader is a page **outside** the
/// project shell, so its `Scaffold` shrinks for the keyboard and anything
/// anchored at the bottom (the way a comment composer is) would have to
/// spend `viewInsets.bottom` itself. An app-bar bottom never can be covered,
/// and it keeps the page's own scroll position visible while typing.
class WikiFindBar extends StatefulWidget implements PreferredSizeWidget {
  const WikiFindBar({super.key, required this.controller});

  final WikiFindController controller;

  /// The debounce before a keystroke re-parses the page. A wiki page is up
  /// to 100 KB of markdown; re-parsing it on every character is what makes a
  /// find bar feel broken.
  static const debounce = Duration(milliseconds: 400);

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  State<WikiFindBar> createState() => _WikiFindBarState();
}

class _WikiFindBarState extends State<WikiFindBar> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _field.text = widget.controller.term;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(WikiFindBar.debounce, () {
      if (mounted) widget.controller.term = value;
    });
  }

  void _close() {
    _debounce?.cancel();
    widget.controller.close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
          Spacing.sm,
          Spacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                },
                child: Actions(
                  actions: {
                    DismissIntent: CallbackAction<DismissIntent>(
                      onInvoke: (_) {
                        _close();
                        return null;
                      },
                    ),
                  },
                  child: TextField(
                    controller: _field,
                    focusNode: _focus,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: (_) => widget.controller.next(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Find on this page',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: ListenableBuilder(
                        listenable: widget.controller,
                        builder: (context, _) {
                          final label = widget.controller.label;
                          if (label == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.md,
                            ),
                            child: Align(
                              widthFactor: 1,
                              child: Text(
                                label,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final enabled = widget.controller.total > 0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Previous match',
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: enabled ? widget.controller.previous : null,
                    ),
                    IconButton(
                      tooltip: 'Next match',
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: enabled ? widget.controller.next : null,
                    ),
                  ],
                );
              },
            ),
            IconButton(
              tooltip: 'Close find',
              icon: const Icon(Icons.close),
              onPressed: _close,
            ),
          ],
        ),
      ),
    );
  }
}
