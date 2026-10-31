import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_snap_fork/material.dart';

// Block spacing goes between blocks. No block adds space after itself, so
// the last block of a document, quote or list item ends at its content.

const _spacing = 10.0;
const _listItemSpacing = 6.0;

CmarkThemeData _theme() {
  final base = CmarkThemeData.fallback(Typography.englishLike2021);
  return base.copyWith(
    blockSpacing: _spacing,
    listItemSpacing: _listItemSpacing,
    blockQuotePadding: EdgeInsets.zero,
    codeBlockPadding: EdgeInsets.zero,
    orderedListBulletTextStyle: base.paragraphTextStyle,
    unorderedListBulletTextStyle: base.paragraphTextStyle,
  );
}

Future<double> _pumpHeight(
  WidgetTester tester,
  String markdown, {
  bool selectable = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CmarkTheme(
            data: _theme(),
            child: CmarkMarkdownColumn(
              data: markdown,
              selectable: selectable,
            ),
          ),
        ),
      ),
    ),
  );
  return tester.getSize(find.byType(CmarkMarkdownColumn)).height;
}

/// Height of the one paragraph whose text is exactly [text].
double _textHeight(WidgetTester tester, String text) {
  final matches = tester.allRenderObjects
      .whereType<RenderParagraph>()
      .where((p) => p.text.toPlainText() == text)
      .toSet()
      .toList();
  expect(matches, hasLength(1), reason: 'one paragraph with "$text"');
  return matches.single.size.height;
}

void main() {
  for (final selectable in [false, true]) {
    group('selectable: $selectable', () {
      testWidgets('one paragraph adds no space', (tester) async {
        final height = await _pumpHeight(tester, 'alpha', selectable: selectable);
        expect(height, _textHeight(tester, 'alpha'));
      });

      testWidgets('spacing goes only between top-level blocks',
          (tester) async {
        final height = await _pumpHeight(
          tester,
          'alpha\n\n# beta\n\ngamma',
          selectable: selectable,
        );
        expect(
          height,
          _textHeight(tester, 'alpha') +
              _textHeight(tester, 'beta') +
              _textHeight(tester, 'gamma') +
              2 * _spacing,
        );
      });

      testWidgets('one code block adds no space', (tester) async {
        final height =
            await _pumpHeight(tester, '```\ncode\n```', selectable: selectable);
        expect(height, _textHeight(tester, 'code'));
      });

      testWidgets('one table adds no space', (tester) async {
        final height = await _pumpHeight(
          tester,
          '| h |\n| - |\n| c |',
          selectable: selectable,
        );
        final table = tester.renderObject<RenderBox>(find.byType(Table));
        // The table renderer puts 4 dp above a table with a header row.
        expect(height, table.size.height + 4);
      });

      testWidgets('one thematic break adds no space', (tester) async {
        final height = await _pumpHeight(tester, '---', selectable: selectable);
        final theme = _theme();
        expect(
          height,
          theme.thematicBreakThickness + theme.thematicBreakVerticalPadding,
        );
      });

      testWidgets('a quote has spacing between its blocks, not after them',
          (tester) async {
        final height = await _pumpHeight(
          tester,
          '> alpha\n>\n> beta',
          selectable: selectable,
        );
        expect(
          height,
          _textHeight(tester, 'alpha') + _textHeight(tester, 'beta') + _spacing,
        );
      });

      testWidgets('a loose list has item spacing between items, not after',
          (tester) async {
        final height = await _pumpHeight(
          tester,
          '- alpha\n\n- beta',
          selectable: selectable,
        );
        expect(
          height,
          _textHeight(tester, 'alpha') +
              _textHeight(tester, 'beta') +
              _listItemSpacing,
        );
      });

      testWidgets('a list item adds no space after its last block',
          (tester) async {
        final height = await _pumpHeight(
          tester,
          '- alpha\n\n  ```\n  code\n  ```',
          selectable: selectable,
        );
        // listItemBlockSpacing is 0 by default.
        expect(
          height,
          _textHeight(tester, 'alpha') + _textHeight(tester, 'code'),
        );
      });
    });
  }
}
