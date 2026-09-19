import 'dart:io';

import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_snap/material.dart';

const _markdown = '''
|  | Default chip | String-label button |
| --- | --- | --- |
| Horizontal spacing | 4 / 4 / 4 | 8 / 8 / 8 |
| Text style | labelSmall | labelLarge |
| Default icon size | labelSmall.fontSize | bodyLarge.fontSize |
| Minimum surface size, after density | 8 × 8; content usually exceeds this | No minimum width; theme-scaled minimum height |
| Icon input | `IconData` | Arbitrary widget |
| Label input | String | String or custom foreground |
| Content changes | Animated size; icon cross-fade | No built-in content transition |
| Selection | selected boolean; owns controller | Caller can supply a states controller |
| Loading pulse | Built in through isAnimating | Separate MonetElevatedButtonAnimated |
''';

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('Serif', 'test/fonts/IMFellGreatPrimer-Regular.ttf');
    await _loadFont('Mono', 'test/fonts/JetBrainsMono-Regular.ttf');
  });

  testWidgets('code-only table cell uses the table row line box',
      (tester) async {
    const body = TextStyle(fontFamily: 'Serif', fontSize: 16, height: 1.25);
    final theme = CmarkThemeData.fallback(
      Typography.englishLike2021.merge(Typography.blackMountainView),
    ).copyWith(
      tableHeaderTextStyle: body.copyWith(fontWeight: FontWeight.bold),
      tableBodyTextStyle: body,
      codeSpanTextStyle: const TextStyle(fontFamily: 'Mono'),
      inlineCodeFontScale: 0.8,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CmarkTheme(
            data: theme,
            child: const CmarkMarkdownColumn(
              data: _markdown,
              selectable: true,
            ),
          ),
        ),
      ),
    );

    final paragraphs = tester.allRenderObjects.whereType<RenderParagraph>();
    final code = paragraphs.firstWhere(
      (paragraph) => paragraph.text.toPlainText() == 'IconData',
    );
    final prose = paragraphs.firstWhere(
      (paragraph) => paragraph.text.toPlainText() == 'Arbitrary widget',
    );

    Rect globalRect(RenderParagraph paragraph) =>
        paragraph.paintBounds.shift(paragraph.localToGlobal(Offset.zero));

    expect(
      globalRect(code).center.dy,
      moreOrLessEquals(globalRect(prose).center.dy, epsilon: 0.01),
      reason: 'A code-only cell should be vertically aligned to the same line '
          'box as prose cells in its table row.',
    );
  });
}
