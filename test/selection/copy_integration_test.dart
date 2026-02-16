import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter/material.dart' hide SelectionArea;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Copy integration - real widget tree', () {
    late String? clipboardText;

    setUp(() {
      clipboardText = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map;
          clipboardText = args['text'] as String?;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<String?> selectAllAndCopy(WidgetTester tester) async {
      await tester.tapAt(const Offset(50, 50));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      return clipboardText;
    }

    Widget buildTestWidget(String markdown) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 800,
            child: CmarkMarkdownColumn(
              data: markdown,
              selectable: true,
            ),
          ),
        ),
      );
    }

    // === Lists ===

    testWidgets('ordered list', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        '1. First item\n2. Second item\n3. Third item',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        '1. First item\n2. Second item\n3. Third item',
      );
    });

    testWidgets('unordered list', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        '- Apple\n- Banana\n- Cherry',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        '\u2022 Apple\n\u2022 Banana\n\u2022 Cherry',
      );
    });

    testWidgets('nested list', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        '- Parent\n  - Child A\n  - Child B\n- Another parent',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        '\u2022 Parent\n\u2022 Child A\n\u2022 Child B\n\u2022 Another parent',
      );
    });

    testWidgets('ordered list numbering preserved across 10+', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        '1. One\n2. Two\n3. Three\n4. Four\n5. Five\n'
        '6. Six\n7. Seven\n8. Eight\n9. Nine\n10. Ten',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        '1. One\n2. Two\n3. Three\n4. Four\n5. Five\n'
        '6. Six\n7. Seven\n8. Eight\n9. Nine\n10. Ten',
      );
    });

    // === Inline formatting ===

    testWidgets('bold and italic are plain text', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        'This has **bold** and *italic* text.',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        'This has bold and italic text.',
      );
    });

    testWidgets('inline code is plain text', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        'Use the `printf()` function.',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        'Use the printf() function.',
      );
    });

    testWidgets('links are plain text', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        'Visit [Google](https://google.com) today.',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        'Visit Google today.',
      );
    });

    // === Code blocks ===

    testWidgets('fenced code block', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        '```dart\nvoid main() {\n  print("hello");\n}\n```',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        'void main() {\n  print("hello");\n}',
      );
    });

    testWidgets('paragraph then code block', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        'Some text.\n\n```\ncode here\n```\n\nMore text.',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        'Some text.\ncode here\nMore text.',
      );
    });

    // === Headings ===

    testWidgets('headings are plain text', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        '# Title\n\nParagraph.\n\n## Subtitle\n\nMore text.',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        'Title\nParagraph.\nSubtitle\nMore text.',
      );
    });

    // === Thematic breaks ===

    testWidgets('thematic break', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        'Above.\n\n---\n\nBelow.',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        'Above.\n---\nBelow.',
      );
    });

    // === Complex documents ===

    testWidgets('complex document', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        '## Header A\n\n1. **Item one**\n   Sub text.\n\n---\n\n'
        '## Header B\n\n1. **Item two**\n   More text.\n'
        '2. **Item three**\n   Even more.\n\n---\n\n*Footer*',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        'Header A\n'
        '1. Item one\nSub text.\n'
        '---\n'
        'Header B\n'
        '1. Item two\nMore text.\n'
        '2. Item three\nEven more.\n'
        '---\n'
        'Footer',
      );
    });

    // === Multiple paragraphs ===

    testWidgets('multiple paragraphs', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        'First paragraph.\n\nSecond paragraph.\n\nThird paragraph.',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        'First paragraph.\nSecond paragraph.\nThird paragraph.',
      );
    });

    // === Blockquote ===

    testWidgets('blockquote is plain text', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        '> This is a quote.\n\nNormal text.',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        'This is a quote.\nNormal text.',
      );
    });

    // === Regressions ===

    testWidgets('non-sequential ordered list numbers', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        '1. In n Out\n2. El Pollo Loco\n3. Pupuseria\n7. Dominican place\n10. Vons',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        '1. In n Out\n2. El Pollo Loco\n3. Pupuseria\n7. Dominican place\n10. Vons',
      );
    });

    testWidgets('strikethrough is plain text', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        'This is ~~deleted~~ text.',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        'This is deleted text.',
      );
    });

    testWidgets('ordered list items with bold content', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        '1. **Bold first**\n2. **Bold second**\n3. Plain third',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        '1. Bold first\n2. Bold second\n3. Plain third',
      );
    });

    testWidgets('multiple code blocks with text between', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        '```\nfirst\n```\n\nMiddle text.\n\n```\nsecond\n```',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        'first\nMiddle text.\nsecond',
      );
    });

    testWidgets('deeply nested list', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        '- Level 1\n  - Level 2\n    - Level 3',
      ));
      await tester.pumpAndSettle();
      expect(await selectAllAndCopy(tester),
        '\u2022 Level 1\n\u2022 Level 2\n\u2022 Level 3',
      );
    });
  });
}
