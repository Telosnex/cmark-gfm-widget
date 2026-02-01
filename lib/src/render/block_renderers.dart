import 'dart:math' as math;

import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:cmark_gfm_widget/src/selection/markdown_selectable_paragraph.dart';
import 'package:cmark_gfm_widget/src/widgets/source_markdown_registry.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:pixel_snap/material.dart';

import '../flutter/debug_log.dart';
import '../parser/document_snapshot.dart';
import '../theme/cmark_theme.dart';
import '../highlight/highlight_adapter.dart';
import '../widgets/source_aware_widget.dart';
import '../selection/leaf_text_registry.dart';
import '../selection/markdown_selectable_list.dart';
import 'inline_renderers.dart';
import 'render_pipeline.dart';

/// Controls whether to wrap paragraphs and lists in custom [SelectionContainer]s
/// (MarkdownSelectableParagraph, MarkdownSelectableList).
///
/// Default is FALSE because custom selection containers break cross-boundary drags:
/// - Dragging from a paragraph into a list captures partial text ("Th" instead of full bullet)
/// - Bullet markers render in separate widgets outside the SelectionContainer
/// - Visual highlight and clipboard content mismatch
///
/// With this disabled, we rely on Flutter's default selection and use
/// [SelectionSerializer] to aggregate fragments and reconstruct markdown at copy time.
///
/// Can be enabled via: --dart-define=CMARK_USE_MARKDOWN_SELECTABLES=true
const bool kUseMarkdownSelectables = bool.fromEnvironment(
  'CMARK_USE_MARKDOWN_SELECTABLES',
  defaultValue: false,
);

final HighlightAdapter _highlightAdapter = HighlightAdapter();

class BlockRenderResult {
  BlockRenderResult(
      {required this.id, required this.widget, this.sourceMarkdown});

  final String id;
  final Widget widget;

  /// Original markdown source for this block (if available)
  final String? sourceMarkdown;
}

typedef BlockMathWidgetBuilder = Widget Function(
  CmarkNode node,
  BlockRenderContext context,
);

class BlockRenderContext {
  BlockRenderContext({
    required this.theme,
    required this.inlineContext,
    required this.selectable,
    required this.textScaleFactor,
    required this.renderFootnoteDefinitions,
    this.leadingSpans = const [],
    required this.tableOptions,
    required this.codeBlockWrapper,
    this.mathBlockBuilder,
    this.onLinkTap,
  });

  final CmarkThemeData theme;
  final InlineRenderContext inlineContext;
  final bool selectable;
  final double textScaleFactor;
  final bool renderFootnoteDefinitions;
  final TableRenderOptions tableOptions;
  final CodeBlockWrapperBuilder? codeBlockWrapper;
  final BlockMathWidgetBuilder? mathBlockBuilder;
  /// Optional tap handler for links (Markdown links).
  final LinkTapHandler? onLinkTap;
  
  /// Optional leading spans to prepend to the first text block.
  final List<InlineSpan> leadingSpans;
}

List<BlockRenderResult> renderDocumentBlocks(
  DocumentSnapshot snapshot,
  List<InlineSpan> leadingSpans,
  BlockRenderContext context,
) {
  final results = <BlockRenderResult>[];
  var remainingLeadingSpans = leadingSpans;
  
  for (final block in snapshot.blocks) {
    // Pass leading spans to first text block, then clear
    final blockContext = remainingLeadingSpans.isNotEmpty
        ? BlockRenderContext(
            theme: context.theme,
            inlineContext: context.inlineContext,
            selectable: context.selectable,
            textScaleFactor: context.textScaleFactor,
            renderFootnoteDefinitions: context.renderFootnoteDefinitions,
            leadingSpans: remainingLeadingSpans,
            tableOptions: context.tableOptions,
            codeBlockWrapper: context.codeBlockWrapper,
            mathBlockBuilder: context.mathBlockBuilder,
            onLinkTap: context.onLinkTap,
          )
        : context;
    
    var widget = _renderBlock(block, blockContext);
    if (widget == null) continue;
    
    // Clear leading spans after first block - they only apply to the first block
    if (remainingLeadingSpans.isNotEmpty) {
      remainingLeadingSpans = const [];
    }

    final metadata = DocumentSnapshot.metadataFor(block);
    final id = metadata?.id ?? 'block-${results.length}';
    final sourceMarkdown = snapshot.getNodeSource(block);

    // Wrap with source metadata so the serializer can use AST attachments.
    // This happens EVEN when custom selectables are disabled (kUseMarkdownSelectables=false)
    // because SelectionSerializer needs the attachments to reconstruct markdown from
    // Flutter's raw text fragments.
    if (context.selectable && sourceMarkdown != null) {
      final attachment = MarkdownSourceAttachment(
        fullSource: sourceMarkdown,
        blockNode: block,
      );
      debugLog(() =>
          '🔧 Creating SourceAwareWidget for ${block.type} block=$id '
          'sourceLen=${sourceMarkdown.length} '
          'preview="${sourceMarkdown.substring(0, math.min(50, sourceMarkdown.length)).replaceAll('\n', '\\n')}"');
      widget = SourceAwareWidget(
        attachment: attachment,
        child: widget,
      );

      // Optionally wrap with custom selectables for paragraphs/lists.
      if (kUseMarkdownSelectables) {
        switch (block.type) {
          case CmarkNodeType.paragraph:
            widget = MarkdownSelectableParagraph(
              attachment: attachment,
              child: widget,
            );
            break;
          case CmarkNodeType.list:
            widget = MarkdownSelectableList(
              attachment: attachment,
              child: widget,
            );
            break;
          default:
            break;
        }
      }
    }

    results.add(BlockRenderResult(
        id: id, widget: widget, sourceMarkdown: sourceMarkdown));
  }
  return results;
}

Widget? _renderBlock(
  CmarkNode node,
  BlockRenderContext context, {
  int listLevel = 0,
}) {
  // Use listItemBlockSpacing when inside a list to avoid excessive padding
  final effectiveBlockSpacing = listLevel > 0
      ? context.theme.listItemBlockSpacing
      : context.theme.blockSpacing;
  final theme = context.theme;
  switch (node.type) {
    case CmarkNodeType.paragraph:
      return _buildTextualBlock(node, context, style: theme.paragraphTextStyle, blockSpacing: effectiveBlockSpacing);
    case CmarkNodeType.heading:
      return _buildTextualBlock(
        node,
        context,
        style: theme.headingTextStyle(node.headingData.level),
        blockSpacing: effectiveBlockSpacing,
      );
    case CmarkNodeType.blockQuote:
      return _buildBlockQuote(node, context, listLevel: listLevel);
    case CmarkNodeType.codeBlock:
      return _buildCodeBlock(node, context);
    case CmarkNodeType.thematicBreak:
      if (context.selectable) {
        // Use a Text widget that looks like a divider and copies as ===
        return _wrapWithSpacing(
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: theme.thematicBreakVerticalPadding / 2,
            ),
            child: Container(
              height: theme.thematicBreakThickness,
              color: theme.thematicBreakColor,
              alignment: Alignment.centerLeft,
              child: const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '\r---\r',
                      style: TextStyle(color: Colors.transparent, fontSize: 0),
                    ),
                    TextSpan(
                      text: '\r',
                      style: TextStyle(fontSize: 0),
                    ),
                  ],
                ),
              ),
            ),
          ),
          theme.blockSpacing,
        );
      }

      // Non-selectable: use regular Divider
      final verticalPadding =
          (theme.thematicBreakVerticalPadding / 2).clamp(0.0, double.infinity);
      final divider = Divider(
        color: theme.thematicBreakColor,
        thickness: theme.thematicBreakThickness,
        height: theme.thematicBreakThickness,
      );
      final paddedDivider = Padding(
        padding: EdgeInsets.only(
          top: verticalPadding,
          bottom: verticalPadding,
        ),
        child: divider,
      );
      return _wrapWithSpacing(paddedDivider, theme.blockSpacing);
    case CmarkNodeType.list:
      return _buildList(node, context, level: listLevel + 1);
    case CmarkNodeType.table:
      return _buildTable(node, context);
    case CmarkNodeType.htmlBlock:
      return _buildTextualBlock(
        node,
        context,
        style: theme.paragraphTextStyle,
        literal: node.content.toString(),
        blockSpacing: effectiveBlockSpacing,
      );
    case CmarkNodeType.footnoteDefinition:
      return _buildFootnoteDefinition(node, context, listLevel: listLevel);
    case CmarkNodeType.mathBlock:
      return _buildMathBlock(node, context);
    case CmarkNodeType.customBlock:
      return _buildTextualBlock(
        node,
        context,
        style: theme.paragraphTextStyle,
        literal: node.customData.onEnter,
        blockSpacing: effectiveBlockSpacing,
      );
    default:
      return _renderCompositeBlock(node, context, listLevel: listLevel);
  }
}

Widget? _renderCompositeBlock(
  CmarkNode node,
  BlockRenderContext context, {
  required int listLevel,
}) {
  final children = <Widget>[];
  var child = node.firstChild;
  while (child != null) {
    final rendered = _renderBlock(child, context, listLevel: listLevel);
    if (rendered != null) {
      children.add(rendered);
    }
    child = child.next;
  }
  if (children.isEmpty) {
    return null;
  }
  return _wrapWithSpacing(
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    context.theme.blockSpacing,
  );
}

Widget _buildTextualBlock(
  CmarkNode node,
  BlockRenderContext context, {
  required TextStyle style,
  String? literal,
  EdgeInsets? blockSpacing,
}) {
  final effectiveSpacing = blockSpacing ?? context.theme.blockSpacing;
  TextSpan textSpan;
  if (literal != null) {
    textSpan = TextSpan(text: literal, style: style);
  } else {
    final children = renderInlineChildren(node, context.inlineContext, style);
    if (children.isEmpty) {
      textSpan = TextSpan(text: '', style: style);
    } else {
      textSpan = TextSpan(style: style, children: children);
    }
  }

  // Prepend leading spans if provided
  final effectiveSpan = context.leadingSpans.isNotEmpty
      ? TextSpan(children: [...context.leadingSpans, textSpan])
      : textSpan;

  // Use pixel_snap's Text.rich for both selectable and non-selectable
  // SelectableRegion (from SelectionArea) makes it selectable automatically
  final widget = Text.rich(
    effectiveSpan,
    textScaler: TextScaler.linear(context.textScaleFactor),
  );

  return _wrapWithSpacing(widget, effectiveSpacing);
}

Widget _buildBlockQuote(
  CmarkNode node,
  BlockRenderContext context, {
  required int listLevel,
}) {
  final children = <Widget>[];
  var child = node.firstChild;
  while (child != null) {
    final rendered = _renderBlock(child, context, listLevel: listLevel);
    if (rendered != null) {
      children.add(rendered);
    }
    child = child.next;
  }

  return Container(
    decoration: BoxDecoration(
      color: context.theme.blockQuoteBackgroundColor,
      border: Border(
        left: BorderSide(color: context.theme.blockQuoteBorderColor, width: 4),
      ),
    ),
    padding: context.theme.blockQuotePadding,
    margin: context.theme.blockSpacing,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

Widget _buildCodeBlock(CmarkNode node, BlockRenderContext context) {
  final literal = node.codeData.literal;
  final highlightConfig = context.theme.codeHighlightTheme;
  final language = _resolveCodeBlockLanguage(
    node.codeData.info,
    highlightConfig,
  );

  // `node.codeData.literal` does not contain the Markdown code block fences.
  // Therefore, Highlight cannot auto-detect the language.
  // Therefore, we use the language from `node.codeData.info` here, and only
  // ask highlight to auto-detect if we cannot determine a language.
  final textSpan = _highlightAdapter.build(
    code: literal,
    baseStyle: context.theme.codeBlockTextStyle,
    theme: highlightConfig.theme,
    // Autodetection is expensive, error-prone, and throws exceptions as a
    // regular part of its operation, resulting in prints without attribution.
    // Therefore, we rely on parsing from the fence, or just use plain text.
    autoDetectLanguage: false,
    language: language,
    fallbackStyle: context.theme.codeBlockTextStyle,
    tabSize: highlightConfig.tabSize,
  );

  final child = context.selectable
      ? Text.rich(
          textSpan,
          softWrap: false,
          textScaler: TextScaler.linear(context.textScaleFactor),
        )
      : RichText(
          text: textSpan,
          softWrap: false,
          textScaler: TextScaler.linear(context.textScaleFactor),
        );

  // If we wrap in a [SingleChildScrollView], its impossible for clients to
  // do things like have the codeblock in a container that applys a "fade"
  // effect at the edges. Therefore, we do not do that here.
  Widget result = Container(
    padding: context.theme.codeBlockPadding,
    margin: context.theme.blockSpacing,
    color: context.theme.codeBlockBackgroundColor,
    child: child,
  );

  // Let client wrap with additional UI (e.g., copy button)
  final wrapper = context.codeBlockWrapper;
  if (wrapper != null) {
    final metadata = CodeBlockMetadata(
      node: node,
      info: node.codeData.info,
      literal: node.codeData.literal,
    );
    result = wrapper(result, metadata);
  }

  return result;
}

Widget _buildMathBlock(CmarkNode node, BlockRenderContext context) {
  final builder = context.mathBlockBuilder ?? _defaultMathBlockBuilder;
  final widget = builder(node, context);
  return _wrapWithSpacing(widget, context.theme.blockSpacing);
}

Widget _buildList(
  CmarkNode node,
  BlockRenderContext context, {
  required int level,
}) {
  final data = node.listData;
  final ordered = data.listType == CmarkListType.ordered;
  final bullets = <Widget>[];
  var item = node.firstChild;
  var index = 0;
  while (item != null) {
    index += 1;
    // Use each item's original number (listData.start) instead of calculating
    final itemNumber = ordered ? item.listData.start : index;
    bullets.add(
      _buildListItem(
        item,
        context,
        ordered: ordered,
        index: itemNumber == 0 ? index : itemNumber,
        tight: data.tight,
        level: level,
      ),
    );

    item = item.next;
  }
  return _wrapWithSpacing(
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: bullets),
    context.theme.blockSpacing,
  );
}

Widget _buildListItem(
  CmarkNode item,
  BlockRenderContext context, {
  required bool ordered,
  required int index,
  required bool tight,
  required int level,
}) {
  final bulletText = ordered ? '$index. ' : '\u2022 ';
  final children = <Widget>[];
  var child = item.firstChild;
  while (child != null) {
    final rendered = _renderBlock(child, context, listLevel: level);
    if (rendered != null) {
      children.add(rendered);
    }
    child = child.next;
  }
  final column = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );

  final resolvedLevel = level < 1 ? 1 : level;

  final rowChildren = <Widget>[
    Text(
      bulletText,
      style: ordered
          ? context.theme.orderedListBulletTextStyle
          : context.theme.unorderedListBulletTextStyle,
      textAlign: TextAlign.right,
    ),
    SizedBox(width: context.theme.listBulletGap),
  ];

  rowChildren.add(Expanded(child: column));

  return Padding(
    padding: EdgeInsets.only(
      left: ordered
          ? context.theme.orderedListIndent(resolvedLevel)
          : context.theme.unorderedListIndent(resolvedLevel),
      bottom: tight ? 0 : context.theme.listItemSpacing,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rowChildren,
    ),
  );
}

Widget _buildTable(CmarkNode node, BlockRenderContext context) {
  TableLeafRegistry.instance.beginTable(node);
  final cellRows = <List<Widget>>[];
  final columnAlignments = <CmarkTableAlign>[];
  final dataRows = <List<String>>[];
  List<String>? headerRow;

  var rowNode = node.firstChild;
  var isHeaderProcessed = false;
  var maxColumns = 0;
  while (rowNode != null) {
    if (rowNode.type != CmarkNodeType.tableRow) {
      rowNode = rowNode.next;
      continue;
    }
    TableLeafRegistry.instance.beginRow(rowNode);
    final cells = <Widget>[];
    final cellTexts = <String>[];
    var cellNode = rowNode.firstChild;
    var columnIndex = 0;
    while (cellNode != null) {
      if (cellNode.type != CmarkNodeType.tableCell) {
        cellNode = cellNode.next;
        continue;
      }
      if (columnAlignments.length <= columnIndex) {
        columnAlignments.add(cellNode.tableCellData.align);
      } else {
        final existing = columnAlignments[columnIndex];
        if (existing == CmarkTableAlign.none &&
            cellNode.tableCellData.align != CmarkTableAlign.none) {
          columnAlignments[columnIndex] = cellNode.tableCellData.align;
        }
      }

      final baseStyle = rowNode.tableRowData.isHeader
          ? context.theme.tableHeaderTextStyle
          : context.theme.tableBodyTextStyle;
      final cellChildren = renderInlineChildren(
        cellNode,
        context.inlineContext,
        baseStyle,
      );
      final textSpan = TextSpan(
        style: baseStyle,
        children: cellChildren.isEmpty ? null : cellChildren,
        text: cellChildren.isEmpty ? '' : null,
      );

      final textAlign = _textAlignForCell(columnAlignments[columnIndex]);
      final plainText = textSpan.toPlainText();
      Widget alignedChild = context.selectable
          ? Text.rich(
              textSpan,
              textAlign: textAlign,
              textScaler: TextScaler.linear(context.textScaleFactor),
            )
          : RichText(
              text: textSpan,
              textAlign: textAlign,
              textScaler: TextScaler.linear(context.textScaleFactor),
            );

      if (context.selectable) {
        alignedChild = SourceAwareWidget(
          attachment: MarkdownSourceAttachment(
            fullSource: plainText,
            blockNode: cellNode,
          ),
          child: alignedChild,
        );
      }

      TableLeafRegistry.instance.addCell(cellNode, plainText);

      cells.add(
        Align(
          alignment: _alignmentForCell(columnAlignments[columnIndex]),
          child: Padding(
            padding: context.theme.tableCellPadding,
            child: alignedChild,
          ),
        ),
      );
      cellTexts.add(_collectPlainText(cellNode));
      columnIndex += 1;
      cellNode = cellNode.next;
    }
    maxColumns = cells.length > maxColumns ? cells.length : maxColumns;
    cellRows.add(cells);
    TableLeafRegistry.instance.endRow();
    if (rowNode.tableRowData.isHeader) {
      isHeaderProcessed = true;
      headerRow = cellTexts;
    } else {
      dataRows.add(cellTexts);
    }
    rowNode = rowNode.next;
  }

  if (cellRows.isEmpty) {
    TableLeafRegistry.instance.endTable();
    return const SizedBox.shrink();
  }

  for (final cells in cellRows) {
    if (cells.length < maxColumns) {
      cells.addAll(
        List<Widget>.generate(
          maxColumns - cells.length,
          (_) => const SizedBox.shrink(),
        ),
      );
    }
  }

  final rows = cellRows.map((cells) => TableRow(children: cells)).toList();

  final defaultColumnWidth =
      context.tableOptions.defaultColumnWidth ?? const IntrinsicColumnWidth();

  final table = Table(
    defaultVerticalAlignment: TableCellVerticalAlignment.top,
    defaultColumnWidth: defaultColumnWidth,
    columnWidths: context.tableOptions.columnWidths,
    border: context.theme.tableBorder,
    children: rows,
  );

  Widget result = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [if (isHeaderProcessed) const SizedBox(height: 4), table],
  );

  final wrapper = context.tableOptions.wrapper;
  if (wrapper != null) {
    final metadata = TableRenderMetadata(
      node: node,
      alignments: columnAlignments,
      header: headerRow,
      rows: dataRows,
    );
    final wrapperContext = TableWrapperContext(
      theme: context.theme,
      selectable: context.selectable,
      textScaleFactor: context.textScaleFactor,
    );
    result = wrapper(result, metadata, wrapperContext);
  }
  final wrapped = _wrapWithSpacing(result, context.theme.blockSpacing);
  TableLeafRegistry.instance.endTable();
  return wrapped;
}

Widget _buildFootnoteDefinition(
  CmarkNode node,
  BlockRenderContext context, {
  required int listLevel,
}) {
  final label = node.footnoteReferenceIndex;
  final children = <Widget>[];
  var child = node.firstChild;
  while (child != null) {
    final rendered = _renderBlock(child, context, listLevel: listLevel);
    if (rendered != null) {
      children.add(rendered);
    }
    child = child.next;
  }
  if (!context.renderFootnoteDefinitions) {
    return const SizedBox.shrink();
  }

  return _wrapWithSpacing(
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('[$label]', style: context.theme.footnoteLabelTextStyle),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    ),
    context.theme.blockSpacing,
  );
}

Alignment _alignmentForCell(CmarkTableAlign align) {
  switch (align) {
    case CmarkTableAlign.center:
      return Alignment.center;
    case CmarkTableAlign.right:
      return Alignment.centerRight;
    case CmarkTableAlign.left:
    case CmarkTableAlign.none:
      return Alignment.centerLeft;
  }
}

TextAlign _textAlignForCell(CmarkTableAlign align) {
  switch (align) {
    case CmarkTableAlign.center:
      return TextAlign.center;
    case CmarkTableAlign.right:
      return TextAlign.right;
    case CmarkTableAlign.left:
    case CmarkTableAlign.none:
      return TextAlign.left;
  }
}

Widget _wrapWithSpacing(Widget child, EdgeInsets padding) {
  if (padding == EdgeInsets.zero) {
    return child;
  }
  return Padding(padding: padding, child: child);
}

Widget _defaultMathBlockBuilder(
  CmarkNode node,
  BlockRenderContext context,
) {
  final literal = node.mathData.literal;
  if (literal.isEmpty) {
    return const SizedBox.shrink();
  }

  Widget child = Math.tex(
    literal,
    mathStyle: MathStyle.display,
    textStyle: context.theme.paragraphTextStyle,
    onErrorFallback: (error) => Text(
      literal,
      style: context.theme.paragraphTextStyle,
    ),
  );

  child = SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: child,
    ),
  );

  // Stack with invisible LaTeX source for copy/paste when selectable
  if (context.selectable) {
    child = Stack(
      children: [
        // Invisible text with LaTeX source - this gets selected/copied
        Positioned.fill(
          child: Text(
            literal,
            style: const TextStyle(color: Colors.transparent),
            overflow: TextOverflow.clip,
          ),
        ),
        // Visible Math widget - ignores pointer events
        IgnorePointer(child: child),
      ],
    );
  }

  return child;
}

String _collectPlainText(CmarkNode node) {
  final buffer = StringBuffer();

  void visit(CmarkNode current) {
    if (current.type == CmarkNodeType.text ||
        current.type == CmarkNodeType.code) {
      buffer.write(current.content.toString());
    } else if (current.type == CmarkNodeType.softbreak ||
        current.type == CmarkNodeType.linebreak) {
      buffer.write('\n');
    }

    var child = current.firstChild;
    while (child != null) {
      visit(child);
      child = child.next;
    }
  }

  visit(node);
  return buffer.toString();
}

String? _resolveCodeBlockLanguage(String info, CodeHighlightTheme config) {
  final trimmed = info.trim();
  if (trimmed.isEmpty) {
    return config.defaultLanguage;
  }
  final spaceIndex = trimmed.indexOf(RegExp(r'\s'));
  final token = spaceIndex == -1 ? trimmed : trimmed.substring(0, spaceIndex);
  return token.isEmpty ? config.defaultLanguage : token.toLowerCase();
}
