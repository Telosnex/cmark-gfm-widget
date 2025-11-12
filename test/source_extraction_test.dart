/// Tests for source markdown extraction and preservation.
///
/// Note: These tests verify that source markdown is correctly extracted and
/// attached to rendered blocks. They do NOT test the actual copy/paste gesture
/// behavior, which is difficult to test and has been verified manually in the app.
library;

import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  group('Source Extraction', () {
    test('Nested list - all items extracted (parse)', () {
      const markdown = '''- A
  - B
  - C''';

      final controller = ParserController();
      final snapshot = controller.parse(markdown); // Uses finish()

      final sources = snapshot.blocks
          .map((b) => snapshot.getNodeSource(b))
          .whereType<String>()
          .toList();

      expect(sources.length, 1, reason: 'Should have 1 list block');

      final listSource = sources.first;
      expect(listSource, contains('- A'));
      expect(listSource, contains('- B'));
      expect(listSource, contains('- C'));
    });

    test('Nested list - all items extracted (parseChunks streaming)', () {
      final controller = ParserController();
      // Simulate streaming: feed line by line
      final snapshot = controller.parseChunks(['- A\n', '  - B\n', '  - C']);

      final sources = snapshot.blocks
          .map((b) => snapshot.getNodeSource(b))
          .whereType<String>()
          .toList();

      expect(sources, isNotEmpty, reason: 'Should extract source');

      final listSource = sources.first;
      expect(listSource, contains('- A'), reason: 'Must contain A');
      expect(listSource, contains('- B'), reason: 'Must contain B');
      expect(listSource, contains('- C'),
          reason: 'Must contain C (streaming bug)');

      // ignore: avoid_print
      print(
          '✅ Streaming extraction works: "${listSource.replaceAll('\n', '\\n')}"');
    });

    test('Headers include ## prefix (parse)', () {
      const markdown = '''## Hello World

### Subsection''';

      final controller = ParserController();
      final snapshot = controller.parse(markdown);

      final sources = snapshot.blocks
          .map((b) => snapshot.getNodeSource(b))
          .whereType<String>()
          .toList();

      final headers = sources.where((s) => s.startsWith('#')).toList();
      expect(headers.length, 2);
      expect(headers[0], '## Hello World');
      expect(headers[1], '### Subsection');
    });

    test('Headers include ## prefix (parseChunks streaming)', () {
      const markdown = '## Hello World\n\n### Subsection';

      final controller = ParserController();
      // Feed character by character like AI streaming
      final snapshot = controller.parseChunks(markdown.split(''));

      final sources = snapshot.blocks
          .map((b) => snapshot.getNodeSource(b))
          .whereType<String>()
          .toList();

      final headers = sources.where((s) => s.startsWith('#')).toList();
      expect(headers.length, 2);
      expect(headers[0], '## Hello World');
      expect(headers[1], '### Subsection');
    });

    test('Math blocks include closing delimiters', () {
      const markdown = r'''$$
x = 5
$$''';

      final controller = ParserController();
      final snapshot = controller.parse(markdown);

      final sources = snapshot.blocks
          .map((b) => snapshot.getNodeSource(b))
          .whereType<String>()
          .toList();

      // Find math block
      final mathSources = sources.where((s) => s.contains('x = 5')).toList();

      if (mathSources.isNotEmpty) {
        expect(mathSources.first, startsWith(r'$$'));
        expect(mathSources.first, endsWith(r'$$'));
      }
    });

    test('Thematic breaks extract correctly', () {
      const markdown = '''Before

---

After''';

      final controller = ParserController();
      final snapshot = controller.parse(markdown);

      final sources = snapshot.blocks
          .map((b) => snapshot.getNodeSource(b))
          .whereType<String>()
          .toList();

      expect(sources, contains('---'));
      expect(sources, contains('Before'));
      expect(sources, contains('After'));
    });

    testWidgets('BlockRenderResults include source markdown',
        (WidgetTester tester) async {
      const markdown = '''## Header

- Item 1
- Item 2

**Bold text**''';

      final results = renderMarkdownBlocks(markdown, selectable: true);

      // Every block should have source
      for (final result in results) {
        expect(result.sourceMarkdown, isNotNull,
            reason: 'Block ${result.id} should have source');
      }

      // Verify specific content is preserved
      final allSources =
          results.map((r) => r.sourceMarkdown).whereType<String>().join('|');

      expect(allSources, contains('## Header'),
          reason: 'Headers should have ##');
      expect(allSources, contains('- Item'),
          reason: 'Lists should have bullets');
      expect(allSources, contains('**Bold text**'),
          reason: 'Bold should be preserved');
    });

    testWidgets('Complex document preserves all formatting',
        (WidgetTester tester) async {
      const markdown = r'''# Title

*Italic* and **bold** and `code`.

- List item 1
  - Nested item
- List item 2

Inline math: $x^2$

Block math:

$$
y = mx + b
$$

Done.''';

      final results = renderMarkdownBlocks(markdown, selectable: true);
      final allSources =
          results.map((r) => r.sourceMarkdown).whereType<String>().join('\n');

      // Verify all markdown elements are preserved
      expect(allSources, contains('# Title'));
      expect(allSources, contains('*Italic*'));
      expect(allSources, contains('**bold**'));
      expect(allSources, contains('`code`'));
      expect(allSources, contains('- List item 1'));
      expect(allSources, contains('  - Nested item'));
      expect(allSources, contains(r'$x^2')); // Inline math
      expect(allSources, contains(r'$$')); // Block math delimiters
      expect(allSources, contains('y = mx + b'));
    });
  });
}
