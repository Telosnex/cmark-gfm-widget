import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/widgets.dart';

import '../parser/document_snapshot.dart';
import '../theme/cmark_theme.dart';
import 'block_render_cache.dart';
import 'block_renderers.dart';
import 'inline_renderers.dart';
import 'table_options.dart';

export 'block_render_cache.dart' show BlockRenderCache;
export 'block_renderers.dart' show BlockRenderResult;
export 'table_options.dart';

class RenderOptions {
  const RenderOptions({
    this.selectable = false,
    this.textScaleFactor = 1.0,
    this.footnoteReferenceBuilder,
    this.renderFootnoteDefinitions = true,
    this.tableOptions = const TableRenderOptions(),
    this.codeBlockWrapper,
    this.mathOptions = const MathRenderOptions(),
    this.leadingSpans = const [],
    this.onLinkTap,
    this.renderImages = false,
    this.repaintBoundaries = false,
  });

  final bool selectable;
  final double textScaleFactor;
  final FootnoteReferenceSpanBuilder? footnoteReferenceBuilder;
  final bool renderFootnoteDefinitions;
  final TableRenderOptions tableOptions;
  final CodeBlockWrapperBuilder? codeBlockWrapper;
  final MathRenderOptions mathOptions;

  /// Optional tap handler for links (Markdown links).
  final LinkTapHandler? onLinkTap;

  /// Whether to render images. When false, images are replaced with their
  /// alt text (or URL if no alt text is available). Defaults to true.
  final bool renderImages;

  /// Optional leading spans to prepend to the first rendered block. For a
  /// leading list, they appear before its first list marker.
  final List<InlineSpan> leadingSpans;

  /// Whether to put each top-level block behind a [RepaintBoundary].
  ///
  /// Then a change to one block repaints only that block. Use it with a
  /// [BlockRenderCache] for documents that update often, such as a streamed
  /// reply. Each boundary adds a compositing layer.
  final bool repaintBoundaries;
}

class MathRenderOptions {
  const MathRenderOptions({
    this.inlineBuilder,
    this.blockBuilder,
  });

  final InlineMathSpanBuilder? inlineBuilder;
  final BlockMathWidgetBuilder? blockBuilder;
}

/// Signature for wrapping code blocks with additional UI (e.g., copy button).
typedef CodeBlockWrapperBuilder = Widget Function(
  Widget codeBlock,
  CodeBlockMetadata metadata,
);

/// Metadata about a code block.
class CodeBlockMetadata {
  const CodeBlockMetadata({
    required this.node,
    required this.info,
    required this.literal,
  });

  final CmarkNode node;
  final String info;
  final String literal;
}

class RenderPipeline {
  const RenderPipeline();

  /// Renders each top-level block of [snapshot].
  ///
  /// With a [cache], blocks that did not change since the last call with the
  /// same cache keep their widgets. The cache already compares the theme's
  /// identity and the flags and numbers in [options]. [cacheKey] must change
  /// when a builder, table option or other value in [options] starts to give
  /// different widgets.
  List<BlockRenderResult> render(
    DocumentSnapshot snapshot,
    CmarkThemeData theme,
    RenderOptions options, {
    BlockRenderCache? cache,
    Object? cacheKey,
  }) {
    final inlineContext = InlineRenderContext(
      theme: theme,
      textScaleFactor: options.textScaleFactor,
      footnoteReferenceBuilder: options.footnoteReferenceBuilder,
      mathInlineBuilder: options.mathOptions.inlineBuilder,
      onLinkTap: options.onLinkTap,
      renderImages: options.renderImages,
    );
    final blockContext = BlockRenderContext(
      theme: theme,
      inlineContext: inlineContext,
      selectable: options.selectable,
      textScaleFactor: options.textScaleFactor,
      renderFootnoteDefinitions: options.renderFootnoteDefinitions,
      leadingSpans: const [], // Don't put leadingSpans in base context - handled separately
      tableOptions: options.tableOptions,
      codeBlockWrapper: options.codeBlockWrapper,
      mathBlockBuilder: options.mathOptions.blockBuilder,
    );

    return renderDocumentBlocks(
      snapshot,
      options.leadingSpans,
      blockContext,
      cache: cache,
      cacheKey: (
        cacheKey,
        options.selectable,
        options.textScaleFactor,
        options.renderFootnoteDefinitions,
        options.renderImages,
        options.repaintBoundaries,
      ),
      repaintBoundaries: options.repaintBoundaries,
    );
  }

  List<Widget> buildWidgets(
    DocumentSnapshot snapshot,
    CmarkThemeData theme,
    RenderOptions options, {
    BlockRenderCache? cache,
    Object? cacheKey,
  }) {
    final entries = render(
      snapshot,
      theme,
      options,
      cache: cache,
      cacheKey: cacheKey,
    );
    return entries
        .map(
          (entry) => KeyedSubtree(
            key: ValueKey<String>(entry.id),
            child: entry.widget,
          ),
        )
        .toList(growable: false);
  }
}
