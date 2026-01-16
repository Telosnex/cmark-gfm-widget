import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/widgets.dart';

import '../parser/document_snapshot.dart';
import '../theme/cmark_theme.dart';
import 'block_renderers.dart';
import 'inline_renderers.dart';
import 'table_options.dart';

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
  
  /// Optional leading spans to prepend to the first text block.
  final List<InlineSpan> leadingSpans;
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

  List<BlockRenderResult> render(
    DocumentSnapshot snapshot,
    CmarkThemeData theme,
    RenderOptions options,
  ) {
    final inlineContext = InlineRenderContext(
      theme: theme,
      textScaleFactor: options.textScaleFactor,
      footnoteReferenceBuilder: options.footnoteReferenceBuilder,
      mathInlineBuilder: options.mathOptions.inlineBuilder,
      onLinkTap: options.onLinkTap,
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

    return renderDocumentBlocks(snapshot, options.leadingSpans, blockContext);
  }

  List<Widget> buildWidgets(
    DocumentSnapshot snapshot,
    CmarkThemeData theme,
    RenderOptions options,
  ) {
    final entries = render(snapshot, theme, options);
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
