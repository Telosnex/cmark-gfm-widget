import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/rendering.dart';

import '../flutter/debug_log.dart';

class MarkdownSourceAttachment {
  MarkdownSourceAttachment({
    this.blockNode,
    this.isListMarker = false,
    this.codeLine,
  });

  final CmarkNode? blockNode;

  /// The rendered marker is selected text, not something Copy should infer.
  final bool isListMarker;

  /// Index of a rendered code line, including empty lines. Used only to
  /// preserve line boundaries; never to fetch unselected source content.
  final int? codeLine;
}

/// Global registry mapping RenderObjects to their original markdown source.
///
/// Ordinary Copy uses this identity to preserve structural boundaries, not
/// to replace selected text with reconstructed Markdown.
class SourceMarkdownRegistry {
  SourceMarkdownRegistry._();

  static final SourceMarkdownRegistry instance = SourceMarkdownRegistry._();

  // Weak identity mapping only. No global text matching, bounding-rectangle
  // expansion, or strong references to every rendered document.
  final Expando<MarkdownSourceAttachment> _registry =
      Expando<MarkdownSourceAttachment>();

  /// Register source markdown for a RenderObject
  void register(
      RenderObject renderObject, MarkdownSourceAttachment attachment) {
    _registry[renderObject] = attachment;
    debugLog(() =>
        '📝 Registered ${renderObject.runtimeType} hash=${renderObject.hashCode} '
        'nodeType=${attachment.blockNode?.type}');
  }

  void unregister(RenderObject renderObject) {
    _registry[renderObject] = null;
  }

  /// Find source markdown by checking the RenderObject and its ancestors
  MarkdownSourceAttachment? findAttachment(RenderObject renderObject) {
    int depth = 0;
    RenderObject? current = renderObject;
    while (current != null) {
      final source = _registry[current];
      if (source != null) {
        return source;
      }
      depth++;
      current = current.parent;
      if (depth > 20) {
        break; // Prevent infinite loops
      }
    }
    return null;
  }
}
