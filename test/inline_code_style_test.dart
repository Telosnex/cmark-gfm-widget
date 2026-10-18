import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:material_ui/material_ui.dart';
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

  test('inline code resolver receives surrounding style and beats legacy scale',
      () {
    final controller = ParserController();
    final paragraph = controller.parse('`code`').root.firstChild!;
    final seen = <TextStyle>[];
    final theme = createTestBlockContext().theme.copyWith(
          codeSpanTextStyle: const TextStyle(fontFamily: 'monospace'),
          inlineCodeFontScale: 0.5,
          inlineCodeFontSize: (surrounding) {
            seen.add(surrounding);
            return surrounding.fontFamily == 'Display' ? 33 : 11;
          },
        );

    final span = renderInlineChildren(
      paragraph,
      InlineRenderContext(theme: theme, textScaleFactor: 1),
      const TextStyle(fontFamily: 'Display', fontSize: 40, height: 1.2),
    ).single as TextSpan;

    expect(seen.single.fontFamily, 'Display');
    expect(seen.single.fontSize, 40);
    expect(span.style!.fontSize, 33);
    expect(span.style!.fontFamily, 'monospace');
    expect(span.style!.height, 1.2);
  });

  test('explicit codeSpanTextStyle size beats the resolver', () {
    final controller = ParserController();
    final paragraph = controller.parse('`code`').root.firstChild!;
    var calls = 0;
    final theme = createTestBlockContext().theme.copyWith(
          codeSpanTextStyle:
              const TextStyle(fontFamily: 'monospace', fontSize: 13),
          inlineCodeFontSize: (_) {
            calls++;
            return 99;
          },
        );

    final span = renderInlineChildren(
      paragraph,
      InlineRenderContext(theme: theme, textScaleFactor: 1),
      const TextStyle(fontSize: 40),
    ).single as TextSpan;

    expect(span.style!.fontSize, 13);
    expect(calls, 0);
  });

  test('resolver returning null falls back to legacy scale', () {
    final controller = ParserController();
    final paragraph = controller.parse('`code`').root.firstChild!;
    final theme = createTestBlockContext().theme.copyWith(
          codeSpanTextStyle: const TextStyle(fontFamily: 'monospace'),
          inlineCodeFontScale: 0.5,
          inlineCodeFontSize: (_) => null,
        );

    final span = renderInlineChildren(
      paragraph,
      InlineRenderContext(theme: theme, textScaleFactor: 1),
      const TextStyle(fontSize: 40),
    ).single as TextSpan;

    expect(span.style!.fontSize, 20);
  });
}
