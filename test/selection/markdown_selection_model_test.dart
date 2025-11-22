import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:cmark_gfm_widget/src/parser/parser_controller.dart';
import 'package:cmark_gfm_widget/src/selection/markdown_selection_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarkdownSelectionModel', () {
    test('heals partial strong selection', () {
      final model = _modelFor('**hello** world');

      // Select "ell" inside the strong span.
      expect(model.toMarkdown(1, 4), '**ell**');

      // Selecting entire block yields canonical markdown.
      expect(model.toMarkdown(0, model.length), '**hello** world');
    });

    test('preserves link destination for partial label selections', () {
      final model =
          _modelFor('Check [this link](https://example.com "Title").');
      final plain = model.plainText;
      final start = plain.indexOf('this');
      final end = start + 'this'.length;

      expect(
        model.toMarkdown(start, end),
        '[this](https://example.com "Title")',
      );
    });

    test('inline code containing backticks expands the fence', () {
      final model = _modelFor('Use `` ` `` for ticks.');
      final plain = model.plainText;
      final tickIndex = plain.indexOf('`');
      expect(tickIndex, isNonNegative);

      final result = model.toMarkdown(tickIndex, tickIndex + 1);
      expect(result, '`````');
    });

    test('strikethrough selections are wrapped with tildes', () {
      final model = _modelFor('This is ~~gone~~ now.');
      final plain = model.plainText;
      final start = plain.indexOf('gone');
      final end = start + 'gone'.length;

      expect(model.toMarkdown(start, end), '~~gone~~');
    });

    test('emphasis selections are wrapped with single asterisks', () {
      final model = _modelFor('Make *this* pop.');
      final plain = model.plainText;
      final start = plain.indexOf('this');
      final end = start + 'this'.length;

      expect(model.toMarkdown(start, end), '*this*');
    });

    test('inline math serializes with single dollar fences', () {
      final model = _modelFor(r'Value \(x+1\) ok.');
      final plain = model.plainText;
      final start = plain.indexOf('x+1');
      final end = start + 'x+1'.length;

      expect(model.toMarkdown(start, end), r'$x+1$');
    });

    test('display math uses double dollar fences', () {
      final model = _modelFor(r'Equation $$x^2$$ shown.');
      final plain = model.plainText;
      final start = plain.indexOf('x^2');
      final end = start + 'x^2'.length;

      expect(model.toMarkdown(start, end), r'$$x^2$$');
    });

    test('links with empty destinations fall back to label text', () {
      final model = _modelFor('[dangling]() and more');
      final plain = model.plainText;
      final start = plain.indexOf('dangling');
      final end = start + 'dangling'.length;

      expect(model.toMarkdown(start, end), 'dangling');
    });

    test('link fallback uses raw URL when label is empty', () {
      final paragraph = CmarkNode(CmarkNodeType.paragraph);
      final link = CmarkNode(CmarkNodeType.link)
        ..linkData.url = 'https://example.com/raw';
      paragraph.appendChild(link);

      final model = MarkdownSelectionModel(paragraph);
      final plain = model.plainText;
      expect(plain, 'https://example.com/raw');
      expect(model.toMarkdown(0, plain.length), 'https://example.com/raw');
    });

    test('footnote references are preserved as bracketed labels', () {
      final model = _modelFor('Use[^note].\n\n[^note]: details');
      final plain = model.plainText;
      final refIndex = plain.indexOf('[1]');
      expect(refIndex, isNonNegative);

      expect(model.toMarkdown(refIndex, refIndex + 3), '[1]');
    });

    test('image without alt text uses title fallback in projection', () {
      final model = _modelFor('![](https://img.test/foo.png "Screenshot")');
      expect(model.plainText.trim(), 'Screenshot');
    });

    test('image without title falls back to URL in projection', () {
      final model = _modelFor('![](https://img.test/foo.png)');
      expect(model.plainText.trim(), 'https://img.test/foo.png');
    });

    test('image alt text collects child text nodes verbatim', () {
      final model = _modelFor('![alt text](https://img.test/foo.png)');
      expect(model.plainText.contains('alt text'), isTrue);
    });

    test('image alt text collects nested formatting recursively', () {
      final model = _modelFor('![**Bold**](https://img.test/foo.png)');
      expect(model.plainText.contains('Bold'), isTrue);
    });

    test('soft breaks appear as newline characters in the projection', () {
      final model = _modelFor('first line\nsecond line');
      expect(model.plainText, 'first line\nsecond line');
    });
  });
}

final ParserController _parserController = ParserController(
  parserOptions: const CmarkParserOptions(
    enableMath: true,
    enableAutolinkExtension: true,
  ),
);

MarkdownSelectionModel _modelFor(String markdown) {
  final snapshot = _parserController.parse(markdown);
  final block = snapshot.blocks.first;
  return MarkdownSelectionModel(block);
}
