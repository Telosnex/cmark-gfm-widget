import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

import '../parser/document_snapshot.dart';
import '../theme/cmark_theme.dart';
import 'block_renderers.dart' show BlockRenderResult;
import 'render_pipeline.dart' show RenderOptions, RenderPipeline;

/// Keeps the widgets from the last [RenderPipeline.render] call, so blocks
/// that did not change keep their widget instances.
///
/// Flutter does not rebuild a child whose widget is the same instance as in
/// the last frame. While a document streams, only its last blocks change, so
/// the other blocks skip rendering, building and layout.
///
/// A block keeps its widget when it has the same ID as a block of the last
/// render, its node has the same content ([CmarkNode.contentEquals]), and it
/// gets the same leading spans. The cache is cleared when the theme or the
/// render's `cacheKey` changes.
///
/// Builders in [RenderOptions] are not called for a block that keeps its
/// widget. Their output must depend only on the node they get and on values
/// in `cacheKey`. A builder that needs changing data, such as footnote
/// sources that stream in, can return a widget that reads the data from an
/// [InheritedWidget].
class BlockRenderCache {
  CmarkThemeData? _theme;
  Object? _key;
  Map<String, _CachedBlock> _blocks = const {};

  /// Removes all rendered blocks.
  void clear() => _blocks = const {};
}

class _CachedBlock {
  const _CachedBlock(this.node, this.leadingSpans, this.result);

  final CmarkNode node;
  final List<InlineSpan> leadingSpans;
  final BlockRenderResult result;
}

/// Renders each top-level block of [snapshot] with [renderBlock], and keeps
/// the results of blocks that [cache] already has.
///
/// [renderBlock] gets the block and the leading spans for it, and returns
/// null for a block that shows nothing. Only the first shown block gets
/// [leadingSpans].
List<BlockRenderResult> renderTopLevelBlocks(
  DocumentSnapshot snapshot,
  List<InlineSpan> leadingSpans, {
  required CmarkThemeData theme,
  required BlockRenderCache? cache,
  required Object? cacheKey,
  required Widget? Function(CmarkNode block, List<InlineSpan> leadingSpans)
      renderBlock,
}) {
  var previous = const <String, _CachedBlock>{};
  if (cache != null &&
      identical(theme, cache._theme) &&
      cacheKey == cache._key) {
    previous = cache._blocks;
  }
  final next = <String, _CachedBlock>{};
  final results = <BlockRenderResult>[];
  var remainingLeadingSpans = leadingSpans;

  for (final block in snapshot.blocks) {
    final id =
        DocumentSnapshot.metadataFor(block)?.id ?? 'block-${results.length}';
    var entry = previous[id];
    if (entry == null ||
        !listEquals(entry.leadingSpans, remainingLeadingSpans) ||
        !entry.node.contentEquals(block)) {
      final widget = renderBlock(block, remainingLeadingSpans);
      if (widget == null) continue;
      entry = _CachedBlock(
        block,
        remainingLeadingSpans,
        BlockRenderResult(id: id, widget: widget),
      );
    }
    // Leading spans only go to the first shown block.
    remainingLeadingSpans = const [];
    next[id] = entry;
    results.add(entry.result);
  }

  if (cache != null) {
    cache
      .._theme = theme
      .._key = cacheKey
      .._blocks = next;
  }
  return results;
}
