import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:cmark_gfm_widget/src/render/block_renderers.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'test_helpers.dart';

/// Font size of each inline-code span whose text is in [codes], read from the
/// laid-out paragraphs (covers Text.rich, RichText, and pixel_snap variants).
Map<String, double?> _codeSpanSizes(WidgetTester tester, List<String> codes) {
  final sizes = <String, double?>{};
  for (final paragraph
      in tester.allRenderObjects.whereType<RenderParagraph>()) {
    paragraph.text.visitChildren((span) {
      if (span is TextSpan && codes.contains(span.text)) {
        sizes[span.text!] = span.style?.fontSize;
      }
      return true;
    });
  }
  return sizes;
}

void main() {
  testWidgets(
      'inline code size resolves per context: heading, paragraph, and table cell each pass their own style',
      (tester) async {
    const scaleByFamily = {'Heading': 1.5, 'Body': 0.5, 'Cell': 0.25};
    final seenFamilies = <String?>{};
    final fallback = CmarkThemeData.fallback(ThemeData().textTheme);
    final theme = fallback.copyWith(
      paragraphTextStyle: const TextStyle(fontFamily: 'Body', fontSize: 20),
      headingTextStyles: List.filled(
        6,
        const TextStyle(fontFamily: 'Heading', fontSize: 40),
      ),
      tableHeaderTextStyle: const TextStyle(fontFamily: 'Cell', fontSize: 16),
      tableBodyTextStyle: const TextStyle(fontFamily: 'Cell', fontSize: 16),
      codeSpanTextStyle: const TextStyle(fontFamily: 'Mono'),
      inlineCodeFontScale: 0.85,
      inlineCodeFontSize: (surrounding) {
        seenFamilies.add(surrounding.fontFamily);
        final scale = scaleByFamily[surrounding.fontFamily];
        return scale == null ? null : surrounding.fontSize! * scale;
      },
    );

    final snapshot = ParserController().parse('''
# Title `inHeading`

Body `inBody` text.

| Column |
|---|
| `inCell` |
''');
    final blocks = renderDocumentBlocks(
      snapshot,
      const [],
      createTestBlockContext(theme: theme),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [for (final b in blocks) b.widget]),
      ),
    ));

    expect(seenFamilies, containsAll(<String>['Heading', 'Body', 'Cell']));
    expect(
      _codeSpanSizes(tester, ['inHeading', 'inBody', 'inCell']),
      {'inHeading': 60.0, 'inBody': 10.0, 'inCell': 4.0},
    );
  });
}
