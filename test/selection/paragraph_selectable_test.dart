import 'package:flutter_test/flutter_test.dart';

import 'package:cmark_gfm_widget/src/parser/parser_controller.dart';
import 'package:cmark_gfm_widget/src/selection/markdown_selectable_paragraph.dart';
import 'package:cmark_gfm_widget/src/widgets/source_markdown_registry.dart';
import 'package:cmark_gfm_widget/src/selection/selection_serializer.dart';

void main() {
  test('MarkdownSelectableParagraph returns partial markdown selection', () {
    const markdown = 'This is **bold** and _italic_ text.';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final paragraphNode = snapshot.blocks.first;

    final attachment = MarkdownSourceAttachment(
      blockNode: paragraphNode,
    );

    final delegate = MarkdownParagraphSelectionDelegate(attachment: attachment);
    final markdownResult = delegate.markdownForRanges(
      [const SelectionRange(3, 18)],
    );

    expect(markdownResult, isNotNull);
    expect(markdownResult, contains('**bold**'));
  });
}
