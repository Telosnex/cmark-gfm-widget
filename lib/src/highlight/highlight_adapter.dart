import 'dart:collection';

import 'package:highlight/highlight.dart' as hi;
import 'package:pixel_snap/material.dart';

/// Highlighted code, as one [TextSpan] per display line.
///
/// Line spans are stable across streaming appends: while code streams in and
/// only grows, previously produced line spans are returned as *identical
/// instances*. Rendering each line in its own `RichText` therefore lets
/// `RenderParagraph` skip layout entirely for unchanged lines, which is what
/// makes long streaming code blocks O(1) per appended chunk instead of O(n).
class HighlightedCodeLines {
  const HighlightedCodeLines({required this.lines, required this.baseStyle});

  /// One span per display line. Line spans never contain newline characters.
  final List<TextSpan> lines;

  /// The effective base style (theme `root` merged over the given base style).
  final TextStyle baseStyle;
}

/// Converts code into highlighted [TextSpan]s using package:highlight.
///
/// Two layers of caching:
///
/// 1. An exact-result LRU cache, which serves rebuilds where the code did not
///    change (e.g. unrelated widget rebuilds).
/// 2. Incremental *stream states* keyed by highlight configuration. Streamed
///    code blocks are append-only, so completed lines are highlighted exactly
///    once using the parser-continuation API
///    (`Highlight.parseWithContinuation`), and only the trailing partial line
///    is re-highlighted per append. Without this, every streamed chunk
///    re-parses the entire code block, which is quadratic over the stream.
class HighlightAdapter {
  HighlightAdapter({this.maxCacheEntries = 128, this.maxStreamStates = 8});

  final int maxCacheEntries;

  /// Maximum number of concurrently tracked streaming code blocks.
  final int maxStreamStates;

  final LinkedHashMap<_CacheKey, HighlightedCodeLines> _cache = LinkedHashMap();
  final List<_StreamState> _streamStates = [];

  HighlightedCodeLines buildLines({
    required String code,
    required TextStyle baseStyle,
    required Map<String, TextStyle> theme,
    required bool autoDetectLanguage,
    required String? language,
    required TextStyle? fallbackStyle,
    required int tabSize,
  }) {
    final normalized = _normalizeTabs(code.replaceAll('\r\n', '\n'), tabSize);
    final trimmed = normalized.trimRight();
    final trailing = normalized.substring(trimmed.length);

    final themeHash = _themeHash(theme);
    final key = _CacheKey(
      codeHash: trimmed.hashCode,
      trailingHash: trailing.hashCode,
      language: language,
      autoDetect: autoDetectLanguage,
      themeHash: themeHash,
      baseStyleHash: baseStyle.hashCode,
      fallbackHash: fallbackStyle?.hashCode ?? 0,
      tabSize: tabSize,
    );

    final cached = _cache.remove(key);
    if (cached != null) {
      // Re-insert to approximate LRU semantics.
      _cache[key] = cached;
      return cached;
    }

    final effectiveBase = theme['root'] != null
        ? baseStyle.merge(theme['root'])
        : baseStyle;
    final styles = _SpanStyles(
      base: effectiveBase,
      theme: theme,
      fallback: fallbackStyle ?? baseStyle,
    );

    final List<TextSpan> lines;
    if (autoDetectLanguage) {
      lines = _autoDetectLines(trimmed, styles);
    } else {
      final configHash = Object.hash(
        language,
        themeHash,
        baseStyle.hashCode,
        fallbackStyle?.hashCode ?? 0,
        tabSize,
      );
      lines = _incrementalLines(trimmed, language, configHash, styles);
    }

    _appendTrailingWhitespace(lines, trailing, effectiveBase);

    if (lines.isEmpty) {
      lines.add(TextSpan(text: '', style: effectiveBase));
    }

    final result = HighlightedCodeLines(
      lines: List<TextSpan>.unmodifiable(lines),
      baseStyle: effectiveBase,
    );
    _cache[key] = result;
    if (_cache.length > maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    return result;
  }

  /// Incrementally highlights [trimmed], reusing a matching stream state when
  /// the code is an append-only extension of previously highlighted code.
  List<TextSpan> _incrementalLines(
    String trimmed,
    String? language,
    int configHash,
    _SpanStyles styles,
  ) {
    if (trimmed.isEmpty) {
      return <TextSpan>[];
    }

    // `trimmed` never ends with '\n' (trimRight), so the tail line is always
    // non-empty and `completed` always ends at a line boundary.
    final lastNewline = trimmed.lastIndexOf('\n');
    final completed = lastNewline == -1 ? '' : trimmed.substring(0, lastNewline + 1);
    final tail = trimmed.substring(lastNewline + 1);

    var state = _findState(configHash, trimmed);
    if (state == null) {
      state = _StreamState(configHash);
      _streamStates.add(state);
      if (_streamStates.length > maxStreamStates) {
        _streamStates.removeAt(0);
      }
    }

    // The matched state's prefix ends at a line boundary and is a prefix of
    // `trimmed`, so it is always a prefix of `completed` as well.
    if (completed.length > state.prefix.length) {
      final delta = completed.substring(state.prefix.length);
      if (!_extendState(state, delta, language, styles)) {
        // Continuation could not reproduce the source; rebuild from scratch.
        state.reset();
        if (!_extendState(state, completed, language, styles)) {
          state.reset();
          _extendStatePlain(state, completed, styles.base);
        }
      }
    }

    return <TextSpan>[
      ...state.lineSpans,
      if (tail.isNotEmpty)
        _tailLineSpan(tail, language, state.continuation, styles),
    ];
  }

  /// Finds the stream state with the longest prefix of [trimmed], if any.
  _StreamState? _findState(int configHash, String trimmed) {
    _StreamState? best;
    var bestIndex = -1;
    for (var index = 0; index < _streamStates.length; index += 1) {
      final state = _streamStates[index];
      if (state.configHash != configHash) {
        continue;
      }
      if (!trimmed.startsWith(state.prefix)) {
        continue;
      }
      if (best == null || state.prefix.length > best.prefix.length) {
        best = state;
        bestIndex = index;
      }
    }
    if (best != null) {
      // Move to the end to approximate LRU semantics.
      _streamStates
        ..removeAt(bestIndex)
        ..add(best);
    }
    return best;
  }

  /// Parses [source] (which always ends with '\n') as a continuation of
  /// [state], appending one span per completed line. Returns false when the
  /// parse fails or does not losslessly reproduce [source].
  bool _extendState(
    _StreamState state,
    String source,
    String? language,
    _SpanStyles styles,
  ) {
    assert(source.endsWith('\n'), 'extend chunks must end at a line boundary');
    final hi.Result result;
    try {
      result = hi.highlight.parseWithContinuation(
        source,
        language: language,
        continuation: state.continuation,
      );
    } catch (_) {
      return false;
    }

    final runs = _flattenNodes(result.nodes, styles);
    if (runs == null || _runsLength(runs) != source.length) {
      return false;
    }

    final lineRuns = _splitRunsIntoLines(runs);
    // `source` ends with '\n', producing an empty trailing segment; drop it.
    lineRuns.removeLast();
    for (final line in lineRuns) {
      state.lineSpans.add(_lineSpan(line, styles.base));
    }
    state.prefix += source;
    state.continuation = result.top;
    return true;
  }

  /// Fallback: appends unhighlighted lines for [source] (ends with '\n').
  void _extendStatePlain(_StreamState state, String source, TextStyle base) {
    final segments = source.split('\n')..removeLast();
    for (final segment in segments) {
      state.lineSpans.add(TextSpan(text: segment, style: base));
    }
    state.prefix += source;
    state.continuation = null;
  }

  /// Highlights the trailing partial line. Does not mutate stream state:
  /// the tail is re-highlighted on every append until its line completes.
  TextSpan _tailLineSpan(
    String tail,
    String? language,
    hi.Mode? continuation,
    _SpanStyles styles,
  ) {
    try {
      final result = hi.highlight.parseWithContinuation(
        tail,
        language: language,
        continuation: continuation,
      );
      final runs = _flattenNodes(result.nodes, styles);
      if (runs != null && _runsLength(runs) == tail.length) {
        return _lineSpan(runs, styles.base);
      }
    } catch (_) {
      // Fall through to plain text.
    }
    return TextSpan(text: tail, style: styles.base);
  }

  /// Whole-text parse with language auto-detection (non-incremental).
  List<TextSpan> _autoDetectLines(String trimmed, _SpanStyles styles) {
    if (trimmed.isEmpty) {
      return <TextSpan>[];
    }
    try {
      final result = hi.highlight.parse(trimmed, autoDetection: true);
      final runs = _flattenNodes(result.nodes, styles);
      if (runs != null && _runsLength(runs) == trimmed.length) {
        return _splitRunsIntoLines(runs)
            .map((line) => _lineSpan(line, styles.base))
            .toList();
      }
    } catch (_) {
      // Fall through to plain text.
    }
    return trimmed
        .split('\n')
        .map((line) => TextSpan(text: line, style: styles.base))
        .toList();
  }

  /// Preserves trailing whitespace that isn't purely newlines, matching the
  /// previous behavior of appending it unhighlighted. Trailing whitespace
  /// segments after a newline become their own (blank) display lines.
  void _appendTrailingWhitespace(
    List<TextSpan> lines,
    String trailing,
    TextStyle base,
  ) {
    if (trailing.isEmpty) {
      return;
    }
    final hasNonNewline = trailing.codeUnits.any(
      (unit) => unit != 0x0A && unit != 0x0D,
    );
    if (!hasNonNewline) {
      return;
    }
    final segments = trailing.replaceAll('\r', '').split('\n');
    final first = segments.removeAt(0);
    if (first.isNotEmpty) {
      if (lines.isEmpty) {
        lines.add(TextSpan(text: first, style: base));
      } else {
        final last = lines.removeLast();
        lines.add(
          TextSpan(
            style: base,
            children: [last, TextSpan(text: first, style: base)],
          ),
        );
      }
    }
    for (final segment in segments) {
      lines.add(TextSpan(text: segment, style: base));
    }
  }

  /// Flattens a highlight node tree into style-resolved text runs.
  /// Returns null when [nodes] is null.
  List<_Run>? _flattenNodes(List<hi.Node>? nodes, _SpanStyles styles) {
    if (nodes == null) {
      return null;
    }
    final runs = <_Run>[];
    _appendRuns(nodes, styles.base, styles, runs);
    return runs;
  }

  void _appendRuns(
    List<hi.Node> nodes,
    TextStyle parentStyle,
    _SpanStyles styles,
    List<_Run> out,
  ) {
    for (final node in nodes) {
      final style = _resolveStyle(parentStyle, node.className, styles);
      final value = node.value;
      if (value != null) {
        if (value.isNotEmpty) {
          out.add(_Run(value, style));
        }
        continue;
      }
      final children = node.children;
      if (children != null && children.isNotEmpty) {
        _appendRuns(children, style, styles, out);
      }
    }
  }

  TextStyle _resolveStyle(
    TextStyle parent,
    String? className,
    _SpanStyles styles,
  ) {
    if (className == null) {
      return parent;
    }
    final themed = styles.theme[className];
    if (themed != null) {
      return parent.merge(themed);
    }
    return parent.merge(styles.fallback);
  }

  int _runsLength(List<_Run> runs) {
    var length = 0;
    for (final run in runs) {
      length += run.text.length;
    }
    return length;
  }

  /// Splits runs at newlines into per-line run lists. A trailing '\n'
  /// produces a final empty line entry.
  List<List<_Run>> _splitRunsIntoLines(List<_Run> runs) {
    final lines = <List<_Run>>[<_Run>[]];
    for (final run in runs) {
      var text = run.text;
      while (true) {
        final newline = text.indexOf('\n');
        if (newline == -1) {
          if (text.isNotEmpty) {
            lines.last.add(_Run(text, run.style));
          }
          break;
        }
        if (newline > 0) {
          lines.last.add(_Run(text.substring(0, newline), run.style));
        }
        lines.add(<_Run>[]);
        text = text.substring(newline + 1);
      }
    }
    return lines;
  }

  /// Builds a single-line span, merging adjacent runs with equal styles.
  TextSpan _lineSpan(List<_Run> runs, TextStyle base) {
    if (runs.isEmpty) {
      return TextSpan(text: '', style: base);
    }
    final children = <TextSpan>[];
    var pendingText = StringBuffer(runs.first.text);
    var pendingStyle = runs.first.style;
    for (var index = 1; index < runs.length; index += 1) {
      final run = runs[index];
      if (identical(run.style, pendingStyle) || run.style == pendingStyle) {
        pendingText.write(run.text);
      } else {
        children.add(TextSpan(text: pendingText.toString(), style: pendingStyle));
        pendingText = StringBuffer(run.text);
        pendingStyle = run.style;
      }
    }
    children.add(TextSpan(text: pendingText.toString(), style: pendingStyle));
    if (children.length == 1) {
      return children.first;
    }
    return TextSpan(style: base, children: children);
  }

  int _themeHash(Map<String, TextStyle> theme) {
    if (theme.isEmpty) {
      return 0;
    }
    final keys = theme.keys.toList()..sort();
    return Object.hashAll(
      keys.map((key) => Object.hash(key, theme[key]?.hashCode ?? 0)),
    );
  }

  String _normalizeTabs(String input, int tabSize) {
    if (!input.contains('\t') || tabSize <= 0) {
      return input;
    }
    final replacement = ' ' * tabSize;
    return input.replaceAll('\t', replacement);
  }
}

class _SpanStyles {
  const _SpanStyles({
    required this.base,
    required this.theme,
    required this.fallback,
  });

  final TextStyle base;
  final Map<String, TextStyle> theme;
  final TextStyle fallback;
}

class _Run {
  const _Run(this.text, this.style);

  final String text;
  final TextStyle style;
}

/// Incremental highlight state for one streaming code block.
class _StreamState {
  _StreamState(this.configHash);

  final int configHash;

  /// Text highlighted so far. Empty, or ends with '\n' (a line boundary).
  String prefix = '';

  /// One span per completed line in [prefix].
  final List<TextSpan> lineSpans = [];

  /// Parser state after [prefix]; input to the next continuation parse.
  hi.Mode? continuation;

  void reset() {
    prefix = '';
    lineSpans.clear();
    continuation = null;
  }
}

class _CacheKey {
  const _CacheKey({
    required this.codeHash,
    required this.trailingHash,
    required this.language,
    required this.autoDetect,
    required this.themeHash,
    required this.baseStyleHash,
    required this.fallbackHash,
    required this.tabSize,
  });

  final int codeHash;
  final int trailingHash;
  final String? language;
  final bool autoDetect;
  final int themeHash;
  final int baseStyleHash;
  final int fallbackHash;
  final int tabSize;

  @override
  int get hashCode => Object.hash(
    codeHash,
    trailingHash,
    language,
    autoDetect,
    themeHash,
    baseStyleHash,
    fallbackHash,
    tabSize,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _CacheKey) return false;
    return codeHash == other.codeHash &&
        trailingHash == other.trailingHash &&
        language == other.language &&
        autoDetect == other.autoDetect &&
        themeHash == other.themeHash &&
        baseStyleHash == other.baseStyleHash &&
        fallbackHash == other.fallbackHash &&
        tabSize == other.tabSize;
  }
}
