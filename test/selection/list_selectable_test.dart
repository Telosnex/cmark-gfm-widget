import 'package:flutter_test/flutter_test.dart';

import 'package:cmark_gfm_widget/src/parser/parser_controller.dart';
import 'package:cmark_gfm_widget/src/selection/markdown_selectable_list.dart';
import 'package:cmark_gfm_widget/src/widgets/source_markdown_registry.dart';
import 'package:cmark_gfm_widget/src/selection/selection_serializer.dart';

void main() {
  test('MarkdownSelectableList returns partial markdown selection', () {
    const markdown = '- Item **one**\n- Item two\n- Item three';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.first;

    final attachment = MarkdownSourceAttachment(
      fullSource: markdown,
      blockNode: listNode,
    );

    final delegate = MarkdownListSelectionDelegate(attachment: attachment);
    final markdownResult = delegate.markdownForRanges(
      const [SelectionRange(3, 14)],
    );

    expect(markdownResult, isNotNull);
    expect(markdownResult, contains('**one**'));
  });

  test('MarkdownSelectableList expands selection to list item boundaries', () {
    const markdown = 'Intro\n- Bullet **one**\n- Bullet two';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.elementAt(1);

    final attachment = MarkdownSourceAttachment(
      fullSource: markdown,
      blockNode: listNode,
    );

    final delegate = MarkdownListSelectionDelegate(attachment: attachment);
    final partialIndex = markdown.indexOf('Bullet **one**') + 3;
    final markdownResult = delegate.markdownForRanges(
      [SelectionRange(partialIndex, partialIndex + 2)],
    );

    expect(markdownResult, isNotNull);
    expect(markdownResult!.trim(), '- Bullet **one**');
  });
}
