import 'dart:io';

import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_snap/material.dart';

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('Serif', 'test/fonts/IMFellGreatPrimer-Regular.ttf');
  });

  testWidgets('inline math is vertically centered in the surrounding line',
      (tester) async {
    const paragraphStyle = TextStyle(
      fontFamily: 'Serif',
      fontSize: 20,
      height: 1.2,
    );
    final theme = CmarkThemeData.fallback(
      Typography.englishLike2021.merge(Typography.blackMountainView),
    ).copyWith(paragraphTextStyle: paragraphStyle);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CmarkTheme(
            data: theme,
            child: const CmarkMarkdownColumn(
              data: r'can be solved by recognizing that $1048576 = 2^{20}$',
            ),
          ),
        ),
      ),
    );

    final paragraph =
        tester.allRenderObjects.whereType<RenderParagraph>().firstWhere(
              (renderObject) =>
                  renderObject.text.toPlainText().contains('can be solved'),
            );
    final plainText = paragraph.text.toPlainText();
    final placeholderOffset = plainText.indexOf('\uFFFC');
    expect(placeholderOffset, isNot(-1));

    final placeholderBox = paragraph
        .getBoxesForSelection(
          TextSelection(
            baseOffset: placeholderOffset,
            extentOffset: placeholderOffset + 1,
          ),
        )
        .single
        .toRect();

    expect(
      placeholderBox.center.dy,
      moreOrLessEquals(paragraph.size.height / 2, epsilon: 0.1),
      reason: 'Inline math should be visually centered in the prose line, not '
          'hung from the alphabetic baseline with its bottom at the baseline.',
    );
  });
}
