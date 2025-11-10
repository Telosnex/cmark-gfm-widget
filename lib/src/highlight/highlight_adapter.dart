import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' as hi;

class HighlightAdapter {
  HighlightAdapter({this.maxCacheEntries = 128});

  final int maxCacheEntries;

  final LinkedHashMap<_CacheKey, TextSpan> _cache = LinkedHashMap();

  TextSpan build({
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

    final key = _CacheKey(
      codeHash: trimmed.hashCode,
      trailingHash: trailing.hashCode,
      language: language,
      autoDetect: autoDetectLanguage,
      themeHash: _themeHash(theme),
      baseStyleHash: baseStyle.hashCode,
      fallbackHash: fallbackStyle?.hashCode ?? 0,
      tabSize: tabSize,
    );

    final cached = _cache[key];
    if (cached != null) {
      // Move to the end to approximate LRU semantics.
      _cache.remove(key);
      _cache[key] = cached;
      return cached;
    }

    final nodes = hi.highlight
        .parse(
          trimmed,
          language: autoDetectLanguage ? null : language,
          autoDetection: autoDetectLanguage,
        )
        .nodes;

    final effectiveBase = theme['root'] != null
        ? baseStyle.merge(theme['root'])
        : baseStyle;
    final spans = <InlineSpan>[];
    if (nodes != null) {
      spans.addAll(
        _convertNodes(nodes, effectiveBase, theme, fallbackStyle ?? baseStyle),
      );
    } else if (trimmed.isNotEmpty) {
      spans.add(TextSpan(text: trimmed, style: effectiveBase));
    }

    if (trailing.isNotEmpty) {
      final hasNonNewline = trailing.runes.any((code) {
        return code != 0x0A && code != 0x0D;
      });
      if (hasNonNewline) {
        spans.add(TextSpan(text: trailing, style: effectiveBase));
      }
    }

    final merged = _mergeAdjacentTextSpans(spans);
    
    // Safety: If highlighting produced no output but we have code, force display
    final result = merged.isEmpty
        ? TextSpan(text: trimmed + trailing, style: effectiveBase)
        : TextSpan(
            style: effectiveBase,
            children: merged,
          );

    _cache[key] = result;
    if (_cache.length > maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }

    return result;
  }

  List<InlineSpan> _convertNodes(
    List<hi.Node> nodes,
    TextStyle parentStyle,
    Map<String, TextStyle> theme,
    TextStyle fallback,
  ) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      spans.addAll(_convertNode(node, parentStyle, theme, fallback));
    }
    return spans;
  }

  List<InlineSpan> _convertNode(
    hi.Node node,
    TextStyle parentStyle,
    Map<String, TextStyle> theme,
    TextStyle fallback,
  ) {
    final style = _resolveStyle(parentStyle, node.className, theme, fallback);
    if (node.value != null) {
      return [TextSpan(text: node.value, style: style)];
    }
    final children = node.children;
    if (children == null || children.isEmpty) {
      return const [];
    }
    final converted = <InlineSpan>[];
    for (final child in children) {
      converted.addAll(_convertNode(child, style, theme, fallback));
    }
    if (node.className == null) {
      return converted;
    }
    return [TextSpan(style: style, children: converted)];
  }

  TextStyle _resolveStyle(
    TextStyle parent,
    String? className,
    Map<String, TextStyle> theme,
    TextStyle fallback,
  ) {
    if (className == null) {
      return parent;
    }
    final themed = theme[className];
    if (themed != null) {
      return parent.merge(themed);
    }
    return parent.merge(fallback);
  }

  List<InlineSpan> _mergeAdjacentTextSpans(List<InlineSpan> spans) {
    if (spans.isEmpty) {
      return spans;
    }
    final merged = <InlineSpan>[];
    TextSpan? pending;

    void flush() {
      if (pending != null) {
        merged.add(pending!);
        pending = null;
      }
    }

    for (final span in spans) {
      if (span is TextSpan &&
          span.children == null &&
          span.recognizer == null) {
        if (pending == null) {
          pending = span;
        } else if (pending!.style == span.style) {
          pending = TextSpan(
            text: (pending!.text ?? '') + (span.text ?? ''),
            style: pending!.style,
          );
        } else {
          flush();
          pending = span;
        }
      } else {
        flush();
        merged.add(span);
      }
    }

    flush();
    return merged;
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
