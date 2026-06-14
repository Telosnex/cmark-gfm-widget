import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  test('inline code respects explicit codeSpanTextStyle font size', () {
    const markdown = '`code`';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final paragraph = snapshot.root.firstChild!;
    final code = paragraph.firstChild!;
    final baseTheme = createTestBlockContext().theme;
    final theme = baseTheme.copyWith(
      codeSpanTextStyle: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      inlineCodeFontScale: 0.25,
    );

    final span = renderInlineChildren(
      paragraph,
      InlineRenderContext(theme: theme, textScaleFactor: 1),
      const TextStyle(fontSize: 40, height: 1.2),
    ).single as TextSpan;

    expect(code.type, CmarkNodeType.code);
    expect(span.text, 'code');
    expect(span.style!.fontSize, 13);
    expect(span.style!.height, 1.2);
  });

  test('inline code keeps legacy scale when no explicit code size is provided',
      () {
    const markdown = '`code`';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final paragraph = snapshot.root.firstChild!;
    final baseTheme = createTestBlockContext().theme;
    final theme = baseTheme.copyWith(
      codeSpanTextStyle: const TextStyle(fontFamily: 'monospace'),
      inlineCodeFontScale: 0.5,
    );

    final span = renderInlineChildren(
      paragraph,
      InlineRenderContext(theme: theme, textScaleFactor: 1),
      const TextStyle(fontSize: 40, height: 1.2),
    ).single as TextSpan;

    expect(span.text, 'code');
    expect(span.style!.fontSize, 20);
    expect(span.style!.height, 1.2);
  });
}
