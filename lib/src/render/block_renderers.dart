import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/material.dart';

import '../parser/document_snapshot.dart';
import '../theme/cmark_theme.dart';
import '../highlight/highlight_adapter.dart';
import 'inline_renderers.dart';

final HighlightAdapter _highlightAdapter = HighlightAdapter();

class BlockRenderResult {
  BlockRenderResult({required this.id, required this.widget});

  final String id;
  final Widget widget;
}

class BlockRenderContext {
  BlockRenderContext({
    required this.theme,
    required this.inlineContext,
    required this.selectable,
    required this.textScaleFactor,
  });

  final CmarkThemeData theme;
  final InlineRenderContext inlineContext;
  final bool selectable;
  final double textScaleFactor;
}

List<BlockRenderResult> renderDocumentBlocks(
  DocumentSnapshot snapshot,
  BlockRenderContext context,
) {
  final results = <BlockRenderResult>[];
  for (final block in snapshot.blocks) {
    final widget = _renderBlock(block, context);
    if (widget == null) continue;
    final metadata = DocumentSnapshot.metadataFor(block);
    final id = metadata?.id ?? 'block-${results.length}';
    results.add(BlockRenderResult(id: id, widget: widget));
  }
  return results;
}

Widget? _renderBlock(
  CmarkNode node,
  BlockRenderContext context, {
  int listLevel = 0,
}) {
  final theme = context.theme;
  switch (node.type) {
    case CmarkNodeType.paragraph:
      return _buildTextualBlock(node, context, style: theme.paragraphTextStyle);
    case CmarkNodeType.heading:
      return _buildTextualBlock(
        node,
        context,
        style: theme.headingTextStyle(node.headingData.level),
      );
    case CmarkNodeType.blockQuote:
      return _buildBlockQuote(node, context, listLevel: listLevel);
    case CmarkNodeType.codeBlock:
      return _buildCodeBlock(node, context);
    case CmarkNodeType.thematicBreak:
      return Divider(
        color: theme.thematicBreakColor,
        thickness: theme.thematicBreakThickness,
        height: theme.thematicBreakThickness + theme.blockSpacing.bottom,
      );
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
      );
    case CmarkNodeType.footnoteDefinition:
      return _buildFootnoteDefinition(node, context, listLevel: listLevel);
    case CmarkNodeType.customBlock:
      return _buildTextualBlock(
        node,
        context,
        style: theme.paragraphTextStyle,
        literal: node.customData.onEnter,
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
}) {
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

  final widget = context.selectable
      ? SelectableText.rich(
          textSpan,
          textScaler: TextScaler.linear(context.textScaleFactor),
        )
      : RichText(
          text: textSpan,
          textScaler: TextScaler.linear(context.textScaleFactor),
        );

  return _wrapWithSpacing(widget, context.theme.blockSpacing);
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
    autoDetectLanguage: language == null ||
        language.isEmpty ||
        language == highlightConfig.defaultLanguage,
    language: language,
    fallbackStyle: context.theme.codeBlockTextStyle,
    tabSize: highlightConfig.tabSize,
  );

  final child = context.selectable
      ? SelectableText.rich(
          textSpan,
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
  return Container(
    padding: context.theme.codeBlockPadding,
    margin: context.theme.blockSpacing,
    color: context.theme.codeBlockBackgroundColor,
    child: child,
  );
}

Widget _buildList(
  CmarkNode node,
  BlockRenderContext context, {
  required int level,
}) {
  final data = node.listData;
  final ordered = data.listType == CmarkListType.ordered;
  final start = ordered ? (data.start == 0 ? 1 : data.start) : 1;
  final bullets = <Widget>[];
  var item = node.firstChild;
  var index = 0;
  while (item != null) {
    index += 1;
    bullets.add(
      _buildListItem(
        item,
        context,
        ordered: ordered,
        index: ordered ? start + index - 1 : index,
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
  final bulletText = ordered ? '$index.' : '\u2022';
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

  return Padding(
    padding: EdgeInsets.only(
      left: ordered
          ? context.theme.orderedListIndent(resolvedLevel)
          : context.theme.unorderedListIndent(resolvedLevel),
      bottom: tight ? 0 : context.theme.listItemSpacing,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: context.theme.listBulletWidth,
          child: Text(
            bulletText,
            style: ordered
                ? context.theme.orderedListBulletTextStyle
                : context.theme.unorderedListBulletTextStyle,
            textAlign: TextAlign.right,
          ),
        ),
        SizedBox(width: context.theme.listBulletGap),
        Expanded(child: column),
      ],
    ),
  );
}

Widget _buildTable(CmarkNode node, BlockRenderContext context) {
  final rows = <TableRow>[];
  var rowNode = node.firstChild;
  var isHeaderProcessed = false;
  while (rowNode != null) {
    if (rowNode.type != CmarkNodeType.tableRow) {
      rowNode = rowNode.next;
      continue;
    }
    final cells = <Widget>[];
    var cellNode = rowNode.firstChild;
    while (cellNode != null) {
      if (cellNode.type != CmarkNodeType.tableCell) {
        cellNode = cellNode.next;
        continue;
      }
      final cellChildren = renderInlineChildren(
        cellNode,
        context.inlineContext,
        rowNode.tableRowData.isHeader
            ? context.theme.tableHeaderTextStyle
            : context.theme.tableBodyTextStyle,
      );
      final textSpan = TextSpan(
        style: rowNode.tableRowData.isHeader
            ? context.theme.tableHeaderTextStyle
            : context.theme.tableBodyTextStyle,
        children: cellChildren.isEmpty ? null : cellChildren,
        text: cellChildren.isEmpty ? '' : null,
      );
      cells.add(
        Padding(
          padding: context.theme.tableCellPadding,
          child: context.selectable
              ? SelectableText.rich(
                  textSpan,
                  textScaler: TextScaler.linear(context.textScaleFactor),
                )
              : RichText(
                  text: textSpan,
                  textScaler: TextScaler.linear(context.textScaleFactor),
                ),
        ),
      );
      cellNode = cellNode.next;
    }
    rows.add(TableRow(children: cells));
    if (rowNode.tableRowData.isHeader) {
      isHeaderProcessed = true;
    }
    rowNode = rowNode.next;
  }

  final table = Table(
    defaultVerticalAlignment: TableCellVerticalAlignment.top,
    border: context.theme.tableBorder,
    children: rows,
  );

  return _wrapWithSpacing(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [if (isHeaderProcessed) const SizedBox(height: 4), table],
    ),
    context.theme.blockSpacing,
  );
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

Widget _wrapWithSpacing(Widget child, EdgeInsets padding) {
  if (padding == EdgeInsets.zero) {
    return child;
  }
  return Padding(padding: padding, child: child);
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
