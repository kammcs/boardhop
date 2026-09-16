import '../../demo_world.dart';

/// A small WIQL evaluator over the demo's work item field maps.
///
/// It understands what the app sends: `=`, `<>`, `<`, `<=`, `>`, `>=`,
/// `IN`, `NOT IN`, `UNDER`, `NOT UNDER`, `CONTAINS`, `CONTAINS WORDS`,
/// `AND`/`OR`/`NOT` with parentheses, the macros `@project`, `@Me`,
/// `@Today ± n`, `@CurrentIteration` and `ORDER BY`. A clause on a field it
/// cannot evaluate is true, so an unexpected query answers too many items
/// rather than none.
class DemoWiql {
  DemoWiql(this.query) {
    final text = query.replaceAll(RegExp(r'\s+'), ' ').trim();
    final orderAt = RegExp(
      r'\bORDER BY\b',
      caseSensitive: false,
    ).firstMatch(text);
    final whereAt = RegExp(r'\bWHERE\b', caseSensitive: false).firstMatch(text);
    final whereText = whereAt == null
        ? ''
        : text.substring(whereAt.end, orderAt?.start ?? text.length);
    final orderText = orderAt == null ? '' : text.substring(orderAt.end);
    _tokens = _tokenize(whereText);
    _pos = 0;
    _where = _tokens.isEmpty ? null : _parseOr();
    for (final part in orderText.split(',')) {
      final m = RegExp(
        r'\[?([\w.]+)\]?\s*(ASC|DESC)?',
        caseSensitive: false,
      ).firstMatch(part.trim());
      if (m == null) continue;
      order.add((m.group(1)!, (m.group(2) ?? 'ASC').toUpperCase() == 'DESC'));
    }
  }

  final String query;
  final List<(String, bool)> order = [];

  late final List<String> _tokens;
  late int _pos;
  _Node? _where;

  /// Whether a query names the link tables (tree or one-hop), which the
  /// evaluator answers as flat anyway.
  bool get isLinkQuery =>
      RegExp(r'FROM\s+WorkItemLinks', caseSensitive: false).hasMatch(query);

  /// Filters and orders [items] (field maps keyed by reference name).
  List<Map<String, dynamic>> run(Iterable<Map<String, dynamic>> items) {
    final out = [
      for (final i in items)
        if (_where?.eval(i) ?? true) i,
    ];
    if (order.isNotEmpty) {
      out.sort((a, b) {
        for (final (field, desc) in order) {
          final c = _compare(a[field], b[field]);
          if (c != 0) return desc ? -c : c;
        }
        return 0;
      });
    }
    return out;
  }

  // ------------------------------------------------------------ parsing

  static List<String> _tokenize(String s) {
    final out = <String>[];
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == ' ') {
        i++;
      } else if (c == '(' || c == ')' || c == ',') {
        out.add(c);
        i++;
      } else if (c == "'" || c == '"') {
        final buffer = StringBuffer("'");
        i++;
        while (i < s.length) {
          if (s[i] == c) {
            if (i + 1 < s.length && s[i + 1] == c) {
              buffer.write(c);
              i += 2;
              continue;
            }
            i++;
            break;
          }
          buffer.write(s[i]);
          i++;
        }
        out.add(buffer.toString());
      } else if (c == '[') {
        final end = s.indexOf(']', i);
        final stop = end < 0 ? s.length : end;
        out.add('[${s.substring(i + 1, stop)}]');
        i = stop + 1;
      } else if ('<>=!'.contains(c)) {
        var j = i + 1;
        while (j < s.length && '<>='.contains(s[j])) {
          j++;
        }
        out.add(s.substring(i, j));
        i = j;
      } else if (c == '+' || c == '-') {
        out.add(c);
        i++;
      } else {
        var j = i;
        while (j < s.length && !' ()\',[<>=!'.contains(s[j])) {
          if ((s[j] == '+' || s[j] == '-') && j > i && s[i] == '@') break;
          j++;
        }
        if (j == i) j++;
        out.add(s.substring(i, j));
        i = j;
      }
    }
    return out;
  }

  String? get _peek => _pos < _tokens.length ? _tokens[_pos] : null;
  String _next() => _tokens[_pos++];
  bool _isWord(String? t, String word) => t?.toUpperCase() == word;

  _Node _parseOr() {
    var left = _parseAnd();
    while (_isWord(_peek, 'OR')) {
      _next();
      left = _Or(left, _parseAnd());
    }
    return left;
  }

  _Node _parseAnd() {
    var left = _parseNot();
    while (_isWord(_peek, 'AND')) {
      _next();
      left = _And(left, _parseNot());
    }
    return left;
  }

  _Node _parseNot() {
    if (_isWord(_peek, 'NOT') && _pos + 1 < _tokens.length) {
      final after = _tokens[_pos + 1];
      if (after == '(') {
        _next();
        return _Not(_parseNot());
      }
    }
    if (_peek == '(') {
      _next();
      final inner = _parseOr();
      if (_peek == ')') _next();
      return inner;
    }
    return _parseClause();
  }

  _Node _parseClause() {
    final fieldToken = _pos < _tokens.length ? _next() : '';
    final field = fieldToken.startsWith('[')
        ? fieldToken.substring(1, fieldToken.length - 1)
        : fieldToken;
    var op = _pos < _tokens.length ? _next().toUpperCase() : '=';
    if (op == 'NOT' || op == 'EVER' || op == 'CONTAINS') {
      final second = _peek?.toUpperCase();
      if (second == 'IN' ||
          second == 'UNDER' ||
          second == 'CONTAINS' ||
          second == 'WORDS' ||
          second == 'EVER') {
        op = '$op ${_next().toUpperCase()}';
        if (op == 'NOT CONTAINS' && _isWord(_peek, 'WORDS')) {
          op = '$op ${_next().toUpperCase()}';
        }
      }
    }
    final Object? value;
    if (_peek == '(') {
      _next();
      final list = <Object?>[];
      while (_peek != null && _peek != ')') {
        final t = _next();
        if (t == ',') continue;
        list.add(_literal(t));
      }
      if (_peek == ')') _next();
      value = list;
    } else {
      value = _valueExpression();
    }
    return _Clause(field, op, value);
  }

  Object? _valueExpression() {
    if (_peek == null) return null;
    final first = _literal(_next());
    if ((_peek == '+' || _peek == '-') && _pos + 1 < _tokens.length) {
      final sign = _next();
      final amount = num.tryParse(_next()) ?? 0;
      return _Offset(first, sign == '-' ? -amount : amount);
    }
    return first;
  }

  static Object? _literal(String t) {
    if (t.startsWith("'")) return t.substring(1);
    if (t.startsWith('@')) return _Macro(t.substring(1).toLowerCase());
    return num.tryParse(t) ?? t;
  }

  static int _compare(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    if (a is num && b is num) return a.compareTo(b);
    return _text(a).toLowerCase().compareTo(_text(b).toLowerCase());
  }

  static String _text(Object? v) {
    if (v is Map) return '${v['displayName'] ?? ''}';
    return '${v ?? ''}';
  }
}

class _Macro {
  const _Macro(this.name);
  final String name;
}

class _Offset {
  const _Offset(this.base, this.amount);
  final Object? base;
  final num amount;
}

abstract class _Node {
  bool eval(Map<String, dynamic> fields);
}

class _And implements _Node {
  _And(this.a, this.b);
  final _Node a;
  final _Node b;
  @override
  bool eval(Map<String, dynamic> f) => a.eval(f) && b.eval(f);
}

class _Or implements _Node {
  _Or(this.a, this.b);
  final _Node a;
  final _Node b;
  @override
  bool eval(Map<String, dynamic> f) => a.eval(f) || b.eval(f);
}

class _Not implements _Node {
  _Not(this.a);
  final _Node a;
  @override
  bool eval(Map<String, dynamic> f) => !a.eval(f);
}

class _Clause implements _Node {
  _Clause(this.field, this.op, this.value);

  final String field;
  final String op;
  final Object? value;

  @override
  bool eval(Map<String, dynamic> fields) {
    final actual = fields[field];
    final expected = _resolve(value);
    switch (op) {
      case '=':
        return _equals(actual, expected);
      case '<>':
      case '!=':
        return !_equals(actual, expected);
      case '>':
      case '>=':
      case '<':
      case '<=':
        if (actual == null || expected == null) return false;
        final c = _order(actual, expected);
        return switch (op) {
          '>' => c > 0,
          '>=' => c >= 0,
          '<' => c < 0,
          _ => c <= 0,
        };
      case 'IN':
        return expected is List && expected.any((e) => _equals(actual, e));
      case 'NOT IN':
        return expected is! List || !expected.any((e) => _equals(actual, e));
      case 'UNDER':
        return _under(actual, expected);
      case 'NOT UNDER':
        return !_under(actual, expected);
      case 'CONTAINS':
      case 'CONTAINS WORDS':
        return _text(actual)
            .toLowerCase()
            .contains(_text(expected).toLowerCase());
      case 'NOT CONTAINS':
      case 'NOT CONTAINS WORDS':
        return !_text(actual)
            .toLowerCase()
            .contains(_text(expected).toLowerCase());
      default:
        // EVER, IN GROUP and the rest: not modelled.
        return true;
    }
  }

  Object? _resolve(Object? v) {
    if (v is List) return [for (final e in v) _resolve(e)];
    if (v is _Offset) {
      final base = _resolve(v.base);
      if (base is DateTime) {
        return base.add(Duration(days: v.amount.round()));
      }
      return base;
    }
    if (v is _Macro) {
      return switch (v.name) {
        'project' => DemoWorld.project,
        'me' => DemoWorld.me,
        'today' => DemoWorld.today,
        'currentiteration' => DemoWorld.currentSprint.path,
        _ => null,
      };
    }
    return v;
  }

  static String _text(Object? v) {
    if (v is Map) return '${v['displayName'] ?? ''}';
    if (v is DemoPerson) return v.name;
    return '${v ?? ''}';
  }

  static bool _equals(Object? actual, Object? expected) {
    if (expected is DemoPerson) {
      if (actual is! Map) return false;
      return actual['id'] == expected.id ||
          '${actual['uniqueName']}'.toLowerCase() ==
              expected.email.toLowerCase();
    }
    if (actual is Map) {
      final wanted = _text(expected).toLowerCase();
      final display = '${actual['displayName']}'.toLowerCase();
      final unique = '${actual['uniqueName']}'.toLowerCase();
      return wanted == display ||
          wanted == unique ||
          wanted == '$display <$unique>';
    }
    if (actual is num || expected is num) {
      return num.tryParse('$actual') == num.tryParse('$expected');
    }
    if (actual is bool) return '$actual' == '$expected'.toLowerCase();
    if (expected is DateTime) {
      final t = DateTime.tryParse('$actual');
      return t != null && _sameDay(t, expected);
    }
    return _text(actual).toLowerCase() == _text(expected).toLowerCase();
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int _order(Object actual, Object expected) {
    if (expected is DateTime) {
      final t = DateTime.tryParse('$actual');
      if (t == null) return -1;
      return t.compareTo(expected);
    }
    final a = num.tryParse('$actual');
    final b = num.tryParse('$expected');
    if (a != null && b != null) return a.compareTo(b);
    return _text(actual).compareTo(_text(expected));
  }

  static bool _under(Object? actual, Object? expected) {
    final path = _text(actual).toLowerCase();
    final root = _text(expected).toLowerCase();
    return path == root || path.startsWith('$root\\');
  }
}
