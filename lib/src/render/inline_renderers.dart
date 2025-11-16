import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:pixel_snap/material.dart';

import '../theme/cmark_theme.dart';

/// Context object passed to inline renderers.
typedef FootnoteReferenceSpanBuilder = InlineSpan? Function(
  CmarkNode node,
  InlineRenderContext context,
  TextStyle baseStyle,
);

typedef InlineMathSpanBuilder = InlineSpan Function(
  CmarkNode node,
  InlineRenderContext context,
  TextStyle baseStyle,
);

class InlineRenderContext {
  InlineRenderContext({
    required this.theme,
    required this.textScaleFactor,
    this.footnoteReferenceBuilder,
    this.mathInlineBuilder,
  });

  final CmarkThemeData theme;
  final double textScaleFactor;
  final FootnoteReferenceSpanBuilder? footnoteReferenceBuilder;
  final InlineMathSpanBuilder? mathInlineBuilder;
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
      final merged = baseStyle.merge(context.theme.codeSpanTextStyle);
      // Keep the surrounding typography metrics (font size/height) so inline
      // code inside headings or other custom styles doesn't drop back to the
      // default body size when the theme supplies explicit values.
      final restored = merged.copyWith(
        fontSize: baseStyle.fontSize,
        height: baseStyle.height,
      );
      return TextSpan(
        text: node.content.toString(), // Inline code uses content, not codeData
        style: restored,
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
      final custom =
          context.footnoteReferenceBuilder?.call(node, context, baseStyle);
      if (custom != null) {
        return custom;
      }
      final label = node.footnoteReferenceIndex;
      return TextSpan(
        text: '[${label == 0 ? node.content.toString() : label}]',
        style: baseStyle,
      );
    case CmarkNodeType.math:
      final builder =
          context.mathInlineBuilder ?? _defaultInlineMathSpanBuilder;
      return builder(node, context, baseStyle);
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

InlineSpan _defaultInlineMathSpanBuilder(
  CmarkNode node,
  InlineRenderContext context,
  TextStyle baseStyle,
) {
  final literal = node.mathData.literal;
  if (literal.isEmpty) {
    return TextSpan(text: literal, style: baseStyle);
  }

  final display = node.mathData.display;
  final math = Math.tex(
    literal,
    mathStyle: display ? MathStyle.display : MathStyle.text,
    textStyle: baseStyle,
    onErrorFallback: (error) => Text(literal, style: baseStyle),
  );

  Widget child = math;
  if (display) {
    child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: math,
    );
  }

  child = SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: child,
  );

  return WidgetSpan(
    alignment:
        display ? PlaceholderAlignment.middle : PlaceholderAlignment.baseline,
    baseline: display ? null : TextBaseline.alphabetic,
    child: Stack(
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
    ),
  );
}
