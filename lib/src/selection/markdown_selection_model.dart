import 'dart:math' as math;

import 'package:cmark_gfm/cmark_gfm.dart';

/// Builds a mapping between the plain-text representation of a block and
/// individual AST nodes, and serializes selected ranges back to Markdown.
class MarkdownSelectionModel {
  MarkdownSelectionModel(this._block);

  final CmarkNode _block;
  _PlainTextProjection? _projection;

  _PlainTextProjection get _resolvedProjection =>
      _projection ??= _PlainTextProjection.build(_block);

  /// Plain-text content as rendered by the inline renderer for this block.
  String get plainText => _resolvedProjection.plainText;

  /// Length of [plainText].
  int get length => plainText.length;

  /// Serializes the selected range [rawStart, rawEnd) back to Markdown.
  String toMarkdown(int rawStart, int rawEnd) {
    if (length == 0 || rawStart == rawEnd) {
      return '';
    }

    final start = rawStart.clamp(0, length);
    final end = rawEnd.clamp(0, length);
    if (start == end) {
      return '';
    }

    final normalizedStart = math.min(start, end);
    final normalizedEnd = math.max(start, end);
    return _emitNode(
      _resolvedProjection.block,
      normalizedStart,
      normalizedEnd,
    );
  }

  String _emitNode(CmarkNode node, int start, int end) {
    final range = _resolvedProjection.ranges[node];
    if (range == null || end <= range.start || start >= range.end) {
      return '';
    }
    final fullySelected = start <= range.start && end >= range.end;

    switch (node.type) {
      case CmarkNodeType.text:
      case CmarkNodeType.softbreak:
      case CmarkNodeType.linebreak:
      case CmarkNodeType.htmlInline:
      case CmarkNodeType.customInline:
        return _substring(range, start, end);
      case CmarkNodeType.code:
        final literal = _substring(range, start, end);
        if (literal.isEmpty) {
          return '';
        }
        return _wrapCode(literal);
      case CmarkNodeType.math:
        final literal = _substring(range, start, end);
        if (literal.isEmpty) {
          return '';
        }
        final fence = node.mathData.display ? r'$$' : r'$';
        return '$fence$literal$fence';
      case CmarkNodeType.emph:
        return _wrapInline(node, start, end, '*');
      case CmarkNodeType.strong:
        return _wrapInline(node, start, end, '**');
      case CmarkNodeType.strikethrough:
        return _wrapInline(node, start, end, '~~');
      case CmarkNodeType.link:
        final label = _emitChildren(node, start, end);
        if (label.isEmpty) {
          if (fullySelected && node.linkData.url.isNotEmpty) {
            return node.linkData.url;
          }
          return '';
        }
        final url = node.linkData.url;
        if (url.isEmpty) {
          return label;
        }
        final title = node.linkData.title;
        final buffer = StringBuffer()
          ..write('[')
          ..write(label)
          ..write('](')
          ..write(url);
        if (title.isNotEmpty) {
          buffer
            ..write(' "')
            ..write(title)
            ..write('"');
        }
        buffer.write(')');
        return buffer.toString();
      case CmarkNodeType.footnoteReference:
        return _substring(range, start, end);
      case CmarkNodeType.thematicBreak:
        return '---';
      case CmarkNodeType.heading:
        final level = node.headingData.level;
        final prefix = '#' * level;
        final content = _emitChildren(node, start, end);
        if (content.isEmpty) return '';
        return '$prefix $content';
      case CmarkNodeType.list:
        return _emitList(node, start, end);
      case CmarkNodeType.item:
        return _emitListItem(node, start, end, 0);
      default:
        return _emitChildren(node, start, end);
    }
  }

  String _wrapInline(CmarkNode node, int start, int end, String marker) {
    final inner = _emitChildren(node, start, end);
    if (inner.isEmpty) {
      return '';
    }
    return '$marker$inner$marker';
  }

  /// Emits markdown for an entire list node, walking all list items and
  /// preserving nesting/indentation.
  String _emitList(CmarkNode listNode, int start, int end) {
    final buffer = StringBuffer();
    var item = listNode.firstChild;
    while (item != null) {
      if (item.type == CmarkNodeType.item) {
        final itemText = _emitListItem(item, start, end, 0);
        if (itemText.isNotEmpty) {
          if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
            buffer.write('\n');
          }
          buffer.write(itemText);
        }
      }
      item = item.next;
    }
    return buffer.toString();
  }

  /// Emits markdown for a single list item, including proper indentation,
  /// bullet/number markers, and any nested lists it contains.
  ///
  /// For ordered lists, computes the actual item number by counting siblings.
  String _emitListItem(CmarkNode itemNode, int start, int end, int depth) {
    final range = _resolvedProjection.ranges[itemNode];
    if (range == null || end <= range.start || start >= range.end) {
      return '';
    }

    final parentList = itemNode.parent;
    if (parentList == null || parentList.type != CmarkNodeType.list) {
      return _emitChildren(itemNode, start, end);
    }

    final indent = '  ' * depth;
    String marker;
    if (parentList.listData.listType == CmarkListType.ordered) {
      // Count which item this is in the parent list
      var itemNumber = parentList.listData.start == 0 ? 1 : parentList.listData.start;
      var sibling = parentList.firstChild;
      while (sibling != null && !identical(sibling, itemNode)) {
        if (sibling.type == CmarkNodeType.item) {
          itemNumber++;
        }
        sibling = sibling.next;
      }
      marker = '$itemNumber. ';
    } else {
      marker = '- ';
    }

    // First, collect what content this item has
    final directContent = StringBuffer();
    final nestedContent = StringBuffer();
    
    var child = itemNode.firstChild;
    while (child != null) {
      if (child.type == CmarkNodeType.list) {
        // Nested list
        final nestedText = _emitNestedList(child, start, end, depth + 1);
        if (nestedText.isNotEmpty) {
          nestedContent.write(nestedText);
        }
      } else {
        directContent.write(_emitNode(child, start, end));
      }
      child = child.next;
    }
    
    // Only emit this item if it has direct content or nested content
    if (directContent.isEmpty && nestedContent.isEmpty) {
      return '';
    }
    
    final buffer = StringBuffer();
    
    // Only include parent marker if this item has direct content
    if (directContent.isNotEmpty) {
      buffer.write(indent);
      buffer.write(marker);
      buffer.write(directContent);
    }
    
    // Add nested content
    if (nestedContent.isNotEmpty) {
      if (buffer.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write(nestedContent);
    }

    return buffer.toString();
  }

  /// Emits markdown for a nested list (used by [_emitListItem] when a list item
  /// contains a child list).
  String _emitNestedList(CmarkNode listNode, int start, int end, int depth) {
    final buffer = StringBuffer();
    var item = listNode.firstChild;
    var isFirst = true;
    while (item != null) {
      if (item.type == CmarkNodeType.item) {
        final itemText = _emitListItem(item, start, end, depth);
        if (itemText.isNotEmpty) {
          if (!isFirst) {
            buffer.write('\n');
          }
          buffer.write(itemText);
          isFirst = false;
        }
      }
      item = item.next;
    }
    return buffer.toString();
  }

  String _emitChildren(CmarkNode node, int start, int end) {
    final buffer = StringBuffer();
    var child = node.firstChild;
    while (child != null) {
      final emitted = _emitNode(child, start, end);
      if (emitted.isNotEmpty) {
        buffer.write(emitted);
      }
      child = child.next;
    }
    return buffer.toString();
  }

  String _substring(_NodeRange range, int start, int end) {
    final sliceStart = math.max(range.start, start);
    final sliceEnd = math.min(range.end, end);
    if (sliceStart >= sliceEnd) {
      return '';
    }
    return plainText.substring(sliceStart, sliceEnd);
  }

  static String _wrapCode(String literal) {
    final runLength = _longestBacktickRun(literal);
    final fence = '`' * (runLength + 1);
    return '$fence$literal$fence';
  }

  static int _longestBacktickRun(String input) {
    var maxRun = 0;
    var currentRun = 0;
    for (var i = 0; i < input.length; i++) {
      if (input.codeUnitAt(i) == 0x60) {
        currentRun += 1;
        maxRun = math.max(maxRun, currentRun);
      } else {
        currentRun = 0;
      }
    }
    return maxRun;
  }
}

class _PlainTextProjection {
  _PlainTextProjection({
    required this.block,
    required this.plainText,
    required this.ranges,
  });

  final CmarkNode block;
  final String plainText;
  final Map<CmarkNode, _NodeRange> ranges;

  static _PlainTextProjection build(CmarkNode block) {
    final builder = _PlainTextBuilder();
    builder.visit(block);
    return _PlainTextProjection(
      block: block,
      plainText: builder.buffer.toString(),
      ranges: builder.ranges,
    );
  }
}

class _PlainTextBuilder {
  final StringBuffer buffer = StringBuffer();
  final Map<CmarkNode, _NodeRange> ranges = <CmarkNode, _NodeRange>{};

  void visit(CmarkNode node) {
    final start = buffer.length;
    switch (node.type) {
      case CmarkNodeType.text:
      case CmarkNodeType.htmlInline:
      case CmarkNodeType.customInline:
        buffer.write(node.content.toString());
        break;
      case CmarkNodeType.softbreak:
      case CmarkNodeType.linebreak:
        buffer.write('\n');
        break;
      case CmarkNodeType.code:
        buffer.write(node.content.toString());
        break;
      case CmarkNodeType.math:
        buffer.write(node.mathData.literal);
        break;
      case CmarkNodeType.codeBlock:
        buffer.write(node.codeData.literal);
        break;
      case CmarkNodeType.footnoteReference:
        final label = node.footnoteReferenceIndex;
        final text = '[${label == 0 ? node.content.toString() : label}]';
        buffer.write(text);
        break;
      case CmarkNodeType.link:
        if (node.firstChild == null && node.linkData.url.isNotEmpty) {
          buffer.write(node.linkData.url);
          break;
        }
        _visitChildren(node);
        break;
      case CmarkNodeType.image:
        final alt = _collectInlineText(node);
        buffer.write(alt);
        break;
      case CmarkNodeType.item:
        // Visit children, but add newline before nested lists
        var child = node.firstChild;
        while (child != null) {
          if (child.type == CmarkNodeType.list && buffer.isNotEmpty) {
            // Add newline before nested list to separate from parent content
            buffer.write('\n');
          }
          visit(child);
          child = child.next;
        }
        // Add newline after list item (unless it's the last item)
        if (node.next != null && node.next!.type == CmarkNodeType.item) {
          buffer.write('\n');
        }
        break;
      default:
        _visitChildren(node);
        break;
    }
    final end = buffer.length;
    ranges[node] = _NodeRange(start, end);
  }

  void _visitChildren(CmarkNode node) {
    var child = node.firstChild;
    while (child != null) {
      visit(child);
      child = child.next;
    }
  }

  static String _collectInlineText(CmarkNode node) {
    final buffer = StringBuffer();
    var child = node.firstChild;
    while (child != null) {
      if (child.type == CmarkNodeType.text) {
        buffer.write(child.content.toString());
      } else {
        buffer.write(_collectInlineText(child));
      }
      child = child.next;
    }
    final collected = buffer.toString();
    if (collected.isNotEmpty) {
      return collected;
    }
    return node.linkData.title.isNotEmpty
        ? node.linkData.title
        : node.linkData.url;
  }
}

class _NodeRange {
  const _NodeRange(this.start, this.end);

  final int start;
  final int end;
}
