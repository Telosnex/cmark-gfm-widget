import 'dart:io';

import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_snap/material.dart';

const _markdown = '''
So my top three would be:

1. `chat_search` + `bm25`
2. `json`
3. `data_structures`
''';

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    // Real fonts with real (differing) ascent/descent metrics. The default
    // FlutterTest font has identical metrics for every family, which hides
    // baseline misalignment between prose and monospace runs.
    await _loadFont('Serif', 'test/fonts/IMFellGreatPrimer-Regular.ttf');
    await _loadFont('Mono', 'test/fonts/JetBrainsMono-Regular.ttf');
  });

  testWidgets('inline code baselines align with list numbers consistently',
      (tester) async {
    const body = TextStyle(fontFamily: 'Serif', fontSize: 16);
    final theme = CmarkThemeData.fallback(Typography.englishLike2021.merge(
      Typography.blackMountainView,
    )).copyWith(
      paragraphTextStyle: body,
      orderedListBulletTextStyle: body,
      unorderedListBulletTextStyle: body,
      // Mirrors the production setup: mono family, no explicit fontSize so
      // the renderer scales relative to the surrounding text.
      codeSpanTextStyle: const TextStyle(fontFamily: 'Mono'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: CmarkTheme(
              data: theme,
              child: const CmarkMarkdownColumn(data: _markdown),
            ),
          ),
        ),
      ),
    );

    final paragraphs =
        tester.allRenderObjects.whereType<RenderParagraph>().toList();

    RenderParagraph paragraphContaining(String needle) {
      final matches = paragraphs
          .where((p) => p.text.toPlainText().contains(needle))
          .toList();
      expect(matches, isNotEmpty, reason: 'no paragraph contains "$needle"');
      return matches.first;
    }

    // Global rect of a substring's glyph boxes within a paragraph.
    Rect globalRectOf(RenderParagraph paragraph, String needle) {
      final plain = paragraph.text.toPlainText();
      final start = plain.indexOf(needle);
      expect(start, isNot(-1), reason: 'expected "$needle" in "$plain"');
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + needle.length),
      );
      expect(boxes, isNotEmpty);
      final local = boxes.first.toRect();
      final origin = paragraph.localToGlobal(Offset.zero);
      return local.shift(origin);
    }

    // For each item, measure where the inline-code glyphs sit vertically
    // relative to the top of that item's bullet ("1. ", "2. ", ...).
    double codeTopRelativeToBullet(String bullet, String code) {
      final bulletParagraph = paragraphContaining(bullet);
      final bulletTop = bulletParagraph.localToGlobal(Offset.zero).dy;
      final codeRect = globalRectOf(paragraphContaining(code), code);
      return codeRect.top - bulletTop;
    }

    final item1 = codeTopRelativeToBullet('1. ', 'chat_search');
    final item2 = codeTopRelativeToBullet('2. ', 'json');
    final item3 = codeTopRelativeToBullet('3. ', 'data_structures');

    // The monospace runs should sit at the same vertical offset relative to
    // their list numbers on every item, regardless of whether the item also
    // contains plain (full-size) text like item 1's " + ".
    expect(item2, moreOrLessEquals(item1, epsilon: 0.01),
        reason: 'item 2 code offset $item2 != item 1 code offset $item1');
    expect(item3, moreOrLessEquals(item1, epsilon: 0.01),
        reason: 'item 3 code offset $item3 != item 1 code offset $item1');
  });
}
