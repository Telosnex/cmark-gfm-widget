import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cmark_gfm_widget/src/parser/parser_controller.dart';
import 'package:cmark_gfm_widget/src/selection/markdown_selection_model.dart';
import 'package:cmark_gfm_widget/src/selection/selection_serializer.dart';
import 'package:cmark_gfm_widget/src/selection/leaf_text_registry.dart';
import 'package:cmark_gfm_widget/src/widgets/source_markdown_registry.dart';

void main() {
  setUp(() {
    TableLeafRegistry.instance.clear();
  });

  test('regression: partial list selection returns selected text only', () {
    // With the new semantic unit UX, partial selections return just the selected text,
    // not expanded full lines. Only complete semantic units get markdown structure.
    const markdown = '- Bullet one with word A\n'
        '- Bullet two with word B\n'
        '- Bullet three with word C\n';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.first;
    final model = MarkdownSelectionModel(listNode);
    
    // Model plainText: "Bullet one with word A\nBullet two with word B\nBullet three with word C"
    // Select from start of line 1 to end of line 2 (complete semantic units)
    final plainText = model.plainText;
    final endOfLine2 = plainText.indexOf('Bullet three') - 1; // before the \n

    final fragment = SelectionFragment(
      rect: Rect.zero,
      plainText: plainText.substring(0, endOfLine2),
      contentLength: endOfLine2,
      attachment: MarkdownSourceAttachment(
        fullSource: markdown,
        blockNode: listNode,
      ),
      range: SelectionRange(0, endOfLine2),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    // Complete lines selected → include markers
    expect(result, contains('- Bullet one with word A'));
    expect(result, contains('- Bullet two with word B'));
  });

  test('regression: mid-line partial selection returns just selected text', () {
    // With new semantic unit UX: selecting mid-line returns just that text
    const markdown = '''- Alpha one
- Beta two
- Gamma three
- Delta four
- Epsilon five
''';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.first;
    final model = MarkdownSelectionModel(listNode);
    
    // Model plainText: "Alpha one\nBeta two\nGamma three\nDelta four\nEpsilon five"
    // Select "mma three\nDelta four" - starts mid-line (not a complete semantic unit)
    final plainText = model.plainText;
    final start = plainText.indexOf('mma three');
    final end = plainText.indexOf('Delta four') + 'Delta four'.length;

    final fragment = SelectionFragment(
      rect: Rect.zero,
      plainText: plainText.substring(start, end),
      contentLength: end - start,
      attachment: MarkdownSourceAttachment(
        fullSource: markdown,
        blockNode: listNode,
      ),
      range: SelectionRange(start, end),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    // Mid-line selection → no markers, just selected text with inline formatting
    expect(result, contains('mma three'));
    expect(result, contains('Delta four'));
    // Should NOT have bullet markers since selection started mid-line
    expect(result.trim(), isNot(startsWith('-')));
  });
}
