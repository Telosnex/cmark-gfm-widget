import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:cmark_gfm_widget/src/render/inline_math_selectable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:pixel_snap/material.dart';

export 'gesture_recognizer_owner.dart' show GestureRecognizerOwner;

import '../theme/cmark_theme.dart';
import 'math_parser_settings.dart';

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

/// Callback for handling link taps. Receives the link URL and optional title.
typedef LinkTapHandler = void Function(String url, String? title);

class InlineRenderContext {
  InlineRenderContext({
    required this.theme,
    required this.textScaleFactor,
    this.footnoteReferenceBuilder,
    this.mathInlineBuilder,
    this.onLinkTap,
    this.renderImages = false,
    List<GestureRecognizer>? linkRecognizerSink,
  }) : _linkRecognizerSink = linkRecognizerSink;

  final CmarkThemeData theme;
  final double textScaleFactor;
  final FootnoteReferenceSpanBuilder? footnoteReferenceBuilder;
  final InlineMathSpanBuilder? mathInlineBuilder;
  final LinkTapHandler? onLinkTap;

  /// Whether to render images. When false, images are replaced with their
  /// alt text (or URL if no alt text is available).
  final bool renderImages;

  /// Where [TapGestureRecognizer]s created for links get appended, so the
  /// caller that owns this render pass can dispose them at the right time.
  /// See [withLinkRecognizerSink] and [GestureRecognizerOwner].
  final List<GestureRecognizer>? _linkRecognizerSink;

  /// Returns a shallow copy of this context whose link tap recognizers are
  /// appended to [sink] instead of being silently dropped (undisposed).
  ///
  /// Callers that build a single standalone paragraph of rich text (one
  /// `Text.rich`/`RichText` per call - see `_buildTextualBlock` and the
  /// table cell renderer in `block_renderers.dart`) should pass a fresh,
  /// empty list here and wrap the resulting widget in
  /// [GestureRecognizerOwner] with that same list, so the recognizers get
  /// disposed when the paragraph rebuilds or unmounts.
  InlineRenderContext withLinkRecognizerSink(List<GestureRecognizer> sink) {
    return InlineRenderContext(
      theme: theme,
      textScaleFactor: textScaleFactor,
      footnoteReferenceBuilder: footnoteReferenceBuilder,
      mathInlineBuilder: mathInlineBuilder,
      onLinkTap: onLinkTap,
      renderImages: renderImages,
      linkRecognizerSink: sink,
    );
  }
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
      final theme = context.theme;
      final merged = baseStyle.merge(theme.codeSpanTextStyle);
      // If the theme provides an explicit inline-code size, respect it. When
      // it does not, preserve the surrounding typography size and apply the
      // legacy scale factor for backwards compatibility.
      final explicitCodeFontSize = theme.codeSpanTextStyle.fontSize;
      double? resolvedFontSize = explicitCodeFontSize;
      if (resolvedFontSize == null) {
        resolvedFontSize = baseStyle.fontSize ?? merged.fontSize;
        if (resolvedFontSize != null) {
          resolvedFontSize *= theme.inlineCodeFontScale;
        }
      }
      final restored = merged.copyWith(
        fontSize: resolvedFontSize,
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
      final url = node.linkData.url;
      final title = node.linkData.title.isEmpty ? null : node.linkData.title;

      // If no children, show the URL as text
      final spanChildren = children.isEmpty
          ? <InlineSpan>[TextSpan(text: url, style: merged)]
          : children;

      // Attach the tap recognizer (when a handler is supplied) directly to
      // the link's own TextSpans, instead of wrapping them in a WidgetSpan +
      // GestureDetector + nested Text.rich.
      //
      // Why this matters: a WidgetSpan is an atomic inline "box" from the
      // surrounding paragraph's line-breaking algorithm - it can never be
      // split across lines. A nested Text.rich inside one can still soft-wrap
      // *internally*, but then the WidgetSpan's height may span several of
      // the outer paragraph's line boxes (e.g. a long bare URL used as link
      // text). The outer paragraph (see `_buildTextualBlock`) renders with
      // `forceStrutHeight: true` so inline code aligns across mixed
      // prose/code lines; that setting forces every outer line box to the
      // strut's single-line height regardless of taller inline content. A
      // multi-line WidgetSpan's excess height is therefore silently ignored
      // by the outer paragraph layout, and the link paints downward past its
      // allotted line, overlapping whatever content follows it.
      //
      // Attaching the recognizer directly to the TextSpan instead means the
      // link's characters are genuinely part of the *same* paragraph/line-
      // breaking pass as the rest of the prose: long link text wraps exactly
      // like ordinary text (including mid-token breaks in a long bare URL,
      // which has no spaces to wrap at otherwise), each real line respects
      // the outer forced strut height individually, and nothing can ever
      // measure taller than one line.
      //
      // TextSpan has no disposal hook of its own, so the recognizer we
      // create here must be tracked and disposed by whoever owns this call -
      // see [InlineRenderContext.withLinkRecognizerSink] and
      // [GestureRecognizerOwner], used by `_buildTextualBlock` and the table
      // cell renderer in block_renderers.dart.
      GestureRecognizer? recognizer;
      if (context.onLinkTap != null) {
        recognizer = TapGestureRecognizer()
          ..onTap = () => context.onLinkTap!(url, title);
        context._linkRecognizerSink?.add(recognizer);
      }

      final linkedChildren = _applyLinkBehavior(
        spanChildren,
        SystemMouseCursors.click,
        recognizer,
      );

      return TextSpan(style: merged, children: linkedChildren);
    case CmarkNodeType.image:
      final alt = _collectPlainText(node) ?? node.linkData.title;
      final url = node.linkData.url;
      if (url.isEmpty || !context.renderImages) {
        final label = alt.isNotEmpty ? alt : url;
        final display = label.isEmpty ? '[image]' : '[image: $label]';
        return TextSpan(text: display, style: baseStyle);
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

/// Recursively copies [spans], setting [cursor] and [recognizer] on all TextSpans.
List<InlineSpan> _applyLinkBehavior(
  List<InlineSpan> spans,
  MouseCursor cursor,
  GestureRecognizer? recognizer,
) {
  return spans.map((span) {
    if (span is TextSpan) {
      final childrenList = span.children;
      return TextSpan(
        text: span.text,
        style: span.style,
        children: childrenList != null
            ? _applyLinkBehavior(
                childrenList.cast<InlineSpan>(),
                cursor,
                recognizer,
              )
            : null,
        recognizer: recognizer,
        mouseCursor: cursor,
        locale: span.locale,
        spellOut: span.spellOut,
        semanticsLabel: span.semanticsLabel,
      );
    }
    // WidgetSpan etc - leave as-is
    return span;
  }).toList();
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
    settings: cmarkMathParserSettings,
    onErrorFallback: (error) => Text(literal, style: baseStyle),
  );

  Widget child = math;
  if (display) {
    child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: math,
    );
  }

  // Do NOT wrap in SingleChildScrollView here.
  // _RenderSingleChildViewport does not implement computeDryBaseline.
  // When this WidgetSpan appears inside a Table cell that uses
  // IntrinsicColumnWidth, the intrinsic-dimension computation calls
  // getDryBaseline on the WidgetSpan, which propagates through to
  // _RenderSingleChildViewport and crashes.

  return WidgetSpan(
    alignment:
        display ? PlaceholderAlignment.middle : PlaceholderAlignment.baseline,
    baseline: display ? null : TextBaseline.alphabetic,
    child: InlineMathSelectable(
      literal: literal,
      child: IgnorePointer(child: child),
    ),
  );
}
