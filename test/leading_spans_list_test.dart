import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_snap/material.dart';

const _markdown = '''
1. Morning taps the window with a shy, bright hand.
2. A kettle clears its throat in the kitchen.
3. The floor remembers footsteps like a favorite song.
4. Dust dances where sunlight points.
5. Outside, a bird practices being fearless.
6. The day stretches, then smiles.

7. I step into the air like it’s a new story.
8. A breeze edits my thoughts, gently.
9. Somewhere, a bus sighs at the curb.
10. Someone laughs and it ripples down the block.
''';

void main() {
  testWidgets('leading glyph appears once before the first list number',
      (tester) async {
    const glyphKey = ValueKey('leading-glyph');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: CmarkMarkdownColumn(
              data: _markdown,
              leadingSpans: [
                WidgetSpan(
                  child: SizedBox(key: glyphKey, width: 12, height: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(glyphKey), findsOneWidget);

    final glyphX = tester.getTopLeft(find.byKey(glyphKey)).dx;
    final firstNumber = tester.allRenderObjects
        .whereType<RenderParagraph>()
        .firstWhere((paragraph) => paragraph.text.toPlainText() == '1. ');
    final firstNumberX = firstNumber.localToGlobal(Offset.zero).dx;
    expect(
      glyphX,
      lessThan(firstNumberX),
      reason: 'A document-leading glyph belongs before the list marker, not '
          'inside the first list item after its number.',
    );
  });
}
