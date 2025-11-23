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

  test('regression: partial list selection stays literal', () {
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
    expect(result.trim(), selectionText);
  });

  test('regression: partial selection with large list fragment stays literal', () {
    const markdown = '''- Alpha one
- Beta two
- Gamma three
- Delta four
- Epsilon five
''';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.first;

    const selectionText = 'Gamma three\n- Delta four';

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
    expect(result.trim(), selectionText);
  });
}
