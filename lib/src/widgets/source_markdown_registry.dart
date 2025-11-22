import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/rendering.dart';

import '../selection/markdown_selection_model.dart';

class MarkdownSourceAttachment {
  MarkdownSourceAttachment({
    required this.fullSource,
    this.blockNode,
  });

  final String fullSource;
  final CmarkNode? blockNode;

  MarkdownSelectionModel? _selectionModel;
  MarkdownSelectionModel? get selectionModel {
    final node = blockNode;
    if (node == null) {
      return null;
    }
    return _selectionModel ??= MarkdownSelectionModel(node);
  }
}

/// Global registry mapping RenderObjects to their original markdown source.
/// 
/// Used for intelligent copy/paste - when a widget is selected and copied,
/// we look up its source markdown here instead of using rendered text.
class SourceMarkdownRegistry {
  SourceMarkdownRegistry._();
  
  static final SourceMarkdownRegistry instance = SourceMarkdownRegistry._();
  
  // Use Expando for object-identity mapping without preventing GC
  final Expando<MarkdownSourceAttachment> _registry =
      Expando<MarkdownSourceAttachment>();
  
  /// Register source markdown for a RenderObject
  void register(RenderObject renderObject, MarkdownSourceAttachment attachment) {
    _registry[renderObject] = attachment;
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

  String? findSourceForRenderObject(RenderObject renderObject) {
    return findAttachment(renderObject)?.fullSource;
  }
  
  /// Clear isn't supported with Expando, but objects get GC'd naturally
  void clear() {
    // Expando doesn't support clearing, but that's fine - objects will be GC'd
  }
}
