import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:cmark_gfm_widget/src/render/inline_renderers.dart';
import 'package:cmark_gfm_widget/src/theme/cmark_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('heading with strong retains styling', () {
    const markdown = '## Canto\u202FIV – **THE RETURN TO THE FIRST LIGHT**  ';
    final parser = CmarkParser();
    parser.feed(markdown);
    final doc = parser.finish();
    final heading = doc.firstChild!;
    expect(heading.type, CmarkNodeType.heading);

    final theme = CmarkThemeData.fallback(const TextTheme());
    final inlineContext = InlineRenderContext(theme: theme, textScaleFactor: 1.0);
    final baseStyle = theme.headingTextStyle(heading.headingData.level);

    final spans = renderInlineChildren(heading, inlineContext, baseStyle);

    expect(spans.length, 2);
    expect(spans[0], isA<TextSpan>());
    expect((spans[0] as TextSpan).text, 'Canto\u202FIV – ');
    expect(spans[1], isA<TextSpan>());

    final strongSpan = spans[1] as TextSpan;
    expect(strongSpan.children, isNotNull);
    final nested = strongSpan.children!.single as TextSpan;
    expect(nested.text, 'THE RETURN TO THE FIRST LIGHT');
    expect(nested.style, isNotNull);
    expect(nested.style!.fontWeight, FontWeight.bold);
  });
}
