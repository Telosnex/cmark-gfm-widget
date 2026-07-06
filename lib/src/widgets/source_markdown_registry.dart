import 'dart:collection';

import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/rendering.dart';

import '../flutter/debug_log.dart';

class MarkdownSourceAttachment {
  MarkdownSourceAttachment({
    this.blockNode,
  });

  final CmarkNode? blockNode;
}

class MarkdownSourceMatch {
  const MarkdownSourceMatch({
    required this.attachment,
    required this.rect,
  });

  final MarkdownSourceAttachment attachment;
  final Rect rect;
}

/// Global registry mapping RenderObjects to their original markdown source.
///
/// Used for intelligent copy/paste - when a widget is selected and copied,
/// we look up its source markdown here instead of using rendered text.
class SourceMarkdownRegistry {
  SourceMarkdownRegistry._();

  static final SourceMarkdownRegistry instance = SourceMarkdownRegistry._();

  // Use Expando for object-identity mapping. We also keep an identity set of
  // currently attached source render objects as a fallback for selection paths
  // where Flutter gives us a SelectionContainer selectable instead of the leaf
  // RenderParagraph. RenderSourceAware.unregisters on detach so this does not
  // retain dead render objects indefinitely.
  final Expando<MarkdownSourceAttachment> _registry =
      Expando<MarkdownSourceAttachment>();
  final Set<RenderObject> _registered = HashSet<RenderObject>.identity();

  /// Register source markdown for a RenderObject
  void register(
      RenderObject renderObject, MarkdownSourceAttachment attachment) {
    _registry[renderObject] = attachment;
    _registered.add(renderObject);
    debugLog(() =>
        '📝 Registered ${renderObject.runtimeType} hash=${renderObject.hashCode} '
        'nodeType=${attachment.blockNode?.type}');
  }

  void unregister(RenderObject renderObject) {
    _registered.remove(renderObject);
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

  /// Fallback for selectables that are not descendants of the source-aware
  /// render object exposed to us by Flutter's selection system. Match the
  /// selected global rect to the nearest/intersecting SourceAware block rect.
  MarkdownSourceAttachment? findAttachmentNearRect(Rect globalRect) {
    MarkdownSourceAttachment? best;
    double bestScore = double.infinity;
    final center = globalRect.center;

    for (final match in findAttachmentsInRect(globalRect)) {
      final rect = match.rect;
      // Prefer the smallest intersecting source block, then nearest center.
      final score =
          rect.size.longestSide + (rect.center - center).distance / 1000.0;
      if (score < bestScore) {
        bestScore = score;
        best = match.attachment;
      }
    }

    return best;
  }

  List<MarkdownSourceMatch> findAttachmentsInRect(Rect globalRect) {
    final center = globalRect.center;
    final matches = <MarkdownSourceMatch>[];

    for (final renderObject in _registered.toList(growable: false)) {
      if (!renderObject.attached) {
        _registered.remove(renderObject);
        continue;
      }
      final attachment = _registry[renderObject];
      if (attachment == null || renderObject is! RenderBox) {
        continue;
      }

      final rect = MatrixUtils.transformRect(
        renderObject.getTransformTo(null),
        Offset.zero & renderObject.size,
      );

      if (rect.overlaps(globalRect) || rect.contains(center)) {
        matches.add(MarkdownSourceMatch(attachment: attachment, rect: rect));
      }
    }

    matches.sort((a, b) {
      final y = a.rect.top.compareTo(b.rect.top);
      if (y != 0) return y;
      return a.rect.left.compareTo(b.rect.left);
    });
    return matches;
  }

  void clear() {
    _registered.clear();
  }
}
