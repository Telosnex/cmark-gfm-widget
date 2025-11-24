import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cmark_gfm_widget/src/parser/parser_controller.dart';
import 'package:cmark_gfm_widget/src/selection/selection_serializer.dart';
import 'package:cmark_gfm_widget/src/selection/leaf_text_registry.dart';
import 'package:cmark_gfm_widget/src/widgets/source_markdown_registry.dart';

void main() {
  setUp(() {
    TableLeafRegistry.instance.clear();
  });

  test('regression: partial list selection expands to full lines', () {
    const markdown = '- Bullet one with word A\n'
        '- Bullet two with word B\n'
        '- Bullet three with word C\n';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.first;

    const selectionText = 'with word A\n- Bullet two with word B';

    final fragment = SelectionFragment(
      rect: Rect.zero,
      plainText: selectionText,
      contentLength: selectionText.length,
      attachment: MarkdownSourceAttachment(
        fullSource: markdown,
        blockNode: listNode,
      ),
      range: const SelectionRange(0, selectionText.length),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    // Should expand to include full bullet lines
    expect(result, contains('- Bullet one with word A'));
    expect(result, contains('- Bullet two with word B'));
  });

  test('regression: partial selection with large list fragment expands to full lines', () {
    const markdown = '''- Alpha one
- Beta two
- Gamma three
- Delta four
- Epsilon five
''';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.first;

    // Partial text starting mid-way through Gamma
    const selectionText = 'mma three\n- Delta four';
    final startOffset = markdown.indexOf(selectionText);

    final fragment = SelectionFragment(
      rect: Rect.zero,
      plainText: selectionText,
      contentLength: markdown.length,
      attachment: MarkdownSourceAttachment(
        fullSource: markdown,
        blockNode: listNode,
      ),
      range: SelectionRange(startOffset, startOffset + selectionText.length),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    // Should expand to include full bullet lines
    expect(result, contains('- Gamma three'));
    expect(result, contains('- Delta four'));
  });
}
