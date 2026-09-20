import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/rendering.dart';

import '../widgets/source_markdown_registry.dart';

/// Actual selected leaf text plus identity used ONLY for structural boundaries.
/// No inferred source offsets or text-content lookups belong on this path.
class DisplayedTextFragment {
  const DisplayedTextFragment({
    required this.text,
    required this.rect,
    this.attachment,
  });

  final String text;
  final Rect rect;
  final MarkdownSourceAttachment? attachment;
}

/// Ordinary Copy, Share, and selection callbacks use displayed text. Markdown
/// reconstruction belongs to explicit export, never this serializer.
class DisplayedTextSerializer {
  const DisplayedTextSerializer();

  String serialize(List<DisplayedTextFragment> fragments) {
    final buffer = StringBuffer();
    DisplayedTextFragment? previous;
    for (final fragment in fragments) {
      final attachment = fragment.attachment;
      if (fragment.text.isEmpty) {
        continue;
      }
      if (previous != null) {
        buffer.write(_separator(previous, fragment));
      }
      if (attachment?.isListMarker == true) {
        // Indent only an actually selected marker; never synthesize a bullet,
        // number, parent item, or punctuation based on the selected words.
        final depth = _listDepth(attachment!.blockNode);
        if (depth > 1) buffer.write('  ' * (depth - 1));
      }
      buffer.write(fragment.text);
      previous = fragment;
    }
    return buffer.toString();
  }

  String _separator(
      DisplayedTextFragment previous, DisplayedTextFragment next) {
    final a = previous.attachment;
    final b = next.attachment;
    final nodeA = a?.blockNode;
    final nodeB = b?.blockNode;

    if (nodeA != null && identical(nodeA, nodeB)) {
      final lineA = a?.codeLine;
      final lineB = b?.codeLine;
      if (lineA != null && lineB != null && lineB > lineA) {
        return '\n' * (lineB - lineA);
      }
      // Inline widgets (including math) and wrapped fragments from a single
      // paragraph/cell are continuations, irrespective of screen Y position.
      return '';
    }

    if (nodeA?.type == CmarkNodeType.tableCell &&
        nodeB?.type == CmarkNodeType.tableCell &&
        identical(nodeA!.parent?.parent, nodeB!.parent?.parent)) {
      if (identical(nodeA.parent, nodeB.parent)) {
        // Empty cells have no selectable glyphs; retain their column boundaries
        // between selected cells. Never fetch any intermediate cell's text.
        var columns = 1;
        var cell = nodeA.next;
        while (cell != null && !identical(cell, nodeB)) {
          columns++;
          cell = cell.next;
        }
        return '\t' * columns;
      }
      // A continuous selection crossing rows includes the empty edge cells
      // between these selected leaves. Emit only their structural separators.
      var trailing = 0;
      var cell = nodeA.next;
      while (cell != null && cell.firstChild == null) {
        trailing++;
        cell = cell.next;
      }
      var leading = 0;
      cell = nodeB.previous;
      while (cell != null && cell.firstChild == null) {
        leading++;
        cell = cell.previous;
      }
      return '${'\t' * trailing}\n${'\t' * leading}';
    }

    final itemA = _ancestor(nodeA, CmarkNodeType.item);
    final itemB = _ancestor(nodeB, CmarkNodeType.item);
    if (a?.isListMarker == true && identical(itemA, itemB)) return '';
    if (itemA != null &&
        itemB != null &&
        identical(_outerList(itemA), _outerList(itemB))) {
      return identical(itemA, itemB) ? '\n\n' : '\n';
    }

    if (nodeA != null || nodeB != null) return '\n\n';
    // Best-effort fallback for unattributed app widgets. Do not infer Markdown
    // or try the global text-content registry if metadata is unavailable.
    return next.rect.top - previous.rect.top > 5 ? '\n' : '';
  }

  static CmarkNode? _ancestor(CmarkNode? node, CmarkNodeType type) {
    while (node != null) {
      if (node.type == type) return node;
      node = node.parent;
    }
    return null;
  }

  static CmarkNode? _outerList(CmarkNode node) {
    CmarkNode? result;
    CmarkNode? current = node;
    while (current != null) {
      if (current.type == CmarkNodeType.list) result = current;
      current = current.parent;
    }
    return result;
  }

  static int _listDepth(CmarkNode? node) {
    var depth = 0;
    while (node != null) {
      if (node.type == CmarkNodeType.list) depth++;
      node = node.parent;
    }
    return depth;
  }
}
