import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/material.dart';

import '../theme/cmark_theme.dart';

/// Context object passed to inline renderers.
class InlineRenderContext {
  InlineRenderContext({required this.theme, required this.textScaleFactor});

  final CmarkThemeData theme;
  final double textScaleFactor;
}

/// Renders all inline children of [parent] using [baseStyle].
List<InlineSpan> renderInlineChildren(
  CmarkNode parent,
  InlineRenderContext context,
  TextStyle baseStyle,
) {
  final spans = <InlineSpan>[];
  var child = parent.firstChild;
  while (child != null) {
    final span = _renderInlineNode(child, context, baseStyle);
    spans.add(span);
    child = child.next;
  }
  return _mergeAdjacentTextSpans(spans);
}

InlineSpan _renderInlineNode(
  CmarkNode node,
  InlineRenderContext context,
  TextStyle baseStyle,
) {
  switch (node.type) {
    case CmarkNodeType.text:
      return TextSpan(text: node.content.toString(), style: baseStyle);
    case CmarkNodeType.softbreak:
      return const TextSpan(text: '\n');
    case CmarkNodeType.linebreak:
      return const TextSpan(text: '\n');
    case CmarkNodeType.code:
      return TextSpan(
        text: node.content.toString(), // Inline code uses content, not codeData
        style: baseStyle.merge(context.theme.codeSpanTextStyle),
      );
    case CmarkNodeType.htmlInline:
      return TextSpan(text: node.content.toString(), style: baseStyle);
    case CmarkNodeType.emph:
      final merged = baseStyle.merge(context.theme.emphasisTextStyle);
      return TextSpan(
        style: merged,
        children: renderInlineChildren(node, context, merged),
      );
    case CmarkNodeType.strong:
      final merged = baseStyle.merge(context.theme.strongTextStyle);
      return TextSpan(
        style: merged,
        children: renderInlineChildren(node, context, merged),
      );
    case CmarkNodeType.strikethrough:
      final merged = baseStyle.merge(context.theme.strikethroughTextStyle);
      return TextSpan(
        style: merged,
        children: renderInlineChildren(node, context, merged),
      );
    case CmarkNodeType.link:
      final merged = baseStyle.merge(context.theme.linkTextStyle);
      final children = renderInlineChildren(node, context, merged);
      if (children.isEmpty) {
        return TextSpan(text: node.linkData.url, style: merged);
      }
      return TextSpan(style: merged, children: children);
    case CmarkNodeType.image:
      final alt = _collectPlainText(node) ?? node.linkData.title;
      final url = node.linkData.url;
      if (url.isEmpty) {
        return TextSpan(text: alt, style: baseStyle);
      }
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Image.network(
          url,
          semanticLabel: alt,
          errorBuilder: (context, _, __) =>
              Text(alt.isEmpty ? url : alt, style: baseStyle),
        ),
      );
    case CmarkNodeType.footnoteReference:
      final label = node.footnoteReferenceIndex;
      return TextSpan(
        text: '[${label == 0 ? node.content.toString() : label}]',
        style: baseStyle,
      );
    default:
      return TextSpan(
        style: baseStyle,
        children: renderInlineChildren(node, context, baseStyle),
      );
  }
}

String? _collectPlainText(CmarkNode node) {
  final buffer = StringBuffer();
  var child = node.firstChild;
  while (child != null) {
    if (child.type == CmarkNodeType.text) {
      buffer.write(child.content.toString());
    } else {
      final nested = _collectPlainText(child);
      if (nested != null) {
        buffer.write(nested);
      }
    }
    child = child.next;
  }
  if (buffer.isEmpty) {
    return null;
  }
  return buffer.toString();
}

List<InlineSpan> _mergeAdjacentTextSpans(List<InlineSpan> spans) {
  if (spans.isEmpty) {
    return spans;
  }

  final merged = <InlineSpan>[];
  TextSpan? pending;

  void flush() {
    if (pending != null) {
      merged.add(pending!);
      pending = null;
    }
  }

  for (final span in spans) {
    if (span is TextSpan && span.children == null && span.recognizer == null) {
      if (pending == null) {
        pending = span;
      } else {
        if (pending!.style == span.style) {
          pending = TextSpan(
            text: (pending!.text ?? '') + (span.text ?? ''),
            style: span.style,
          );
        } else {
          flush();
          pending = span;
        }
      }
    } else {
      flush();
      merged.add(span);
    }
  }

  flush();
  return merged;
}
