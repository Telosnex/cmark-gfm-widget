import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:cmark_gfm_widget/src/flutter/selectable_region.dart' as region;
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart' hide SelectionArea;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Product contract: ordinary Copy copies selected displayed text, not Markdown.
// Formatting/export policy must not creep back into extraction bug fixes.
void main() {
  late String? copied;
  late String? reported;
  late String? shared;
  setUp(() {
    copied = null;
    reported = null;
    shared = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      if (call.method == 'Share.invoke') shared = call.arguments as String;
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget content(String markdown) {
    final snapshot = ParserController().parse(markdown);
    final theme = CmarkThemeData.fallback(ThemeData().textTheme);
    final widgets = const RenderPipeline().buildWidgets(
      snapshot,
      theme,
      RenderOptions(
          selectable: true,
          codeBlockWrapper: (child, _) => SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: child)),
    );
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  Widget area(Widget child, {double width = 760}) {
    return MaterialApp(
        home: Scaffold(
            body: SelectionArea(
      onSelectionChanged: (value) => reported = value?.plainText,
      child: SingleChildScrollView(child: SizedBox(width: width, child: child)),
    )));
  }

  Widget harness(String markdown, {double width = 760}) =>
      area(content(markdown), width: width);

  Future<void> shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();
  }

  final cases = <(String, String, String, String, bool)>[
    (
      'ordered partial',
      '7. Alpha selected words omega.',
      'Alpha selected words omega.',
      'selected words',
      false
    ),
    (
      'repeated word in second list item',
      '1. First sentence here.\n2. Second sentence here.',
      'Second sentence here.',
      'sentence',
      false
    ),
    (
      'partial heading',
      '## Alpha selected words omega.',
      'Alpha selected words omega.',
      'selected words',
      false
    ),
    (
      'partial strong',
      'Alpha **selected words** omega.',
      'Alpha selected words omega.',
      'selected',
      false
    ),
    (
      'partial code',
      'Use `IconData` here.',
      'Use IconData here.',
      'Icon',
      false
    ),
    (
      'partial link',
      'Visit [useful destination](https://example.com/path) now.',
      'Visit useful destination now.',
      'useful',
      false
    ),
    (
      'repeated plain token after code',
      'Use `token` then token again.',
      'Use token then token again.',
      'token',
      true
    ),
    (
      'nested item',
      '- Parent\n  - Child selected words here.',
      'Child selected words here.',
      'selected words',
      false
    ),
    (
      'formatted table cell',
      '| A | B |\n| --- | --- |\n| **selected words** | elsewhere |',
      'selected words',
      'selected',
      false
    ),
    ('literal backtick', 'Use `` ` `` here.', 'Use ` here.', '`', false),
    (
      'plain control',
      'Alpha selected words omega.',
      'Alpha selected words omega.',
      'selected words',
      false
    ),
  ];
  for (final reverse in [false, true]) {
    for (final (name, markdown, paragraphText, selected, last) in cases) {
      testWidgets('$name (${reverse ? "backward" : "forward"})',
          (tester) async {
        await tester.pumpWidget(harness(markdown));
        await tester.pumpAndSettle();
        final paragraph = tester.allRenderObjects
            .whereType<RenderParagraph>()
            .firstWhere((p) => p.text.toPlainText() == paragraphText);
        final start = last
            ? paragraphText.lastIndexOf(selected)
            : paragraphText.indexOf(selected);
        final selection = TextSelection(
            baseOffset: start, extentOffset: start + selected.length);
        final boxes = paragraph.getBoxesForSelection(selection);
        final from = paragraph.localToGlobal(Offset(boxes.first.left + 0.1,
            (boxes.first.top + boxes.first.bottom) / 2));
        final to = paragraph.localToGlobal(Offset(
            boxes.last.right - 0.1, (boxes.last.top + boxes.last.bottom) / 2));
        final gesture = await tester.startGesture(reverse ? to : from,
            kind: PointerDeviceKind.mouse);
        for (var step = 1; step <= 8; step++) {
          await gesture.moveTo(
              Offset.lerp(reverse ? to : from, reverse ? from : to, step / 8)!);
          await tester.pump();
        }
        await gesture.up();
        await tester.pump();
        final highlighted = paragraph.selections
            .map((s) => paragraphText.substring(s.start, s.end))
            .join();
        expect(highlighted, selected,
            reason: 'Verify actual highlight, not just the requested range.');
        await shortcut(tester, LogicalKeyboardKey.keyC);
        expect(copied, selected);
        expect(reported, selected,
            reason: 'Callbacks and Copy share the displayed-text contract.');
      });
    }
  }

  for (final (name, markdown, expected) in <(String, String, String)>[
    (
      'nonsequential list',
      '4. Four\n8. Eight\n12. Twelve',
      '4. Four\n8. Eight\n12. Twelve'
    ),
    ('full table', '| A | B |\n| --- | --- |\n| X | Y |', 'A\tB\nX\tY'),
    (
      'empty middle cell',
      '| A | B | C |\n| --- | --- | --- |\n| X | | Z |',
      'A\tB\tC\nX\t\tZ'
    ),
    (
      'mixed source',
      '## Heading\n\n**bold** and `code`.\n\n```dart\nprint(1);\n```\n\n> Quote',
      'Heading\n\nbold and code.\n\nprint(1);\n\nQuote'
    ),
    (
      'code blank lines and indentation',
      '```\nfirst\n\n  third\n\n\nlast\n```',
      'first\n\n  third\n\n\nlast'
    ),
    (
      'literal punctuation',
      r'Literal \*stars\* and \#tag and `| - 1. ~~`.',
      'Literal *stars* and #tag and | - 1. ~~.'
    ),
    ('math alternative', r'Before $x^2$ after.', 'Before x^2 after.'),
    (
      'tall math stays inline',
      r'Before $\frac{a}{b}$ after $y^2$ end.',
      r'Before \frac{a}{b} after y^2 end.'
    ),
    (
      'table math stays in its cell',
      '| A | B |\n| --- | --- |\n'
          r'| Before $\frac{a}{b}$ after | Second |',
      'A\tB\n' r'Before \frac{a}{b} after' '\tSecond'
    ),
    (
      'empty table edges',
      '| A | B | C |\n| --- | --- | --- |\n| | Y | |\n| P | Q | R |',
      'A\tB\tC\n\tY\t\nP\tQ\tR'
    ),
    (
      'list continuation paragraph',
      '- First.\n\n  Second.\n\n- Third.',
      '• First.\n\nSecond.\n• Third.'
    ),
    (
      'nested list',
      '- Parent\n  - Child\n- Next',
      '• Parent\n  • Child\n• Next'
    ),
    ('blockquote paragraphs', '> First.\n>\n> Second.', 'First.\n\nSecond.'),
    ('thematic boundary', 'Before\n\n---\n\nAfter', 'Before\n\nAfter'),
  ]) {
    testWidgets(name, (tester) async {
      await tester.pumpWidget(harness(markdown));
      await tester.pumpAndSettle();
      final first = tester.allRenderObjects.whereType<RenderParagraph>().first;
      await tester.tapAt(first.localToGlobal(const Offset(2, 2)));
      await shortcut(tester, LogicalKeyboardKey.keyA);
      await shortcut(tester, LogicalKeyboardKey.keyC);
      expect(copied, expected);
      expect(reported, expected);
    });
  }

  testWidgets('soft wrapping never adds newlines', (tester) async {
    const text =
        'Some very long text with **bold** words and more text that wraps.';
    await tester.pumpWidget(harness(text, width: 160));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await shortcut(tester, LogicalKeyboardKey.keyA);
    await shortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied,
        'Some very long text with bold words and more text that wraps.');
  });

  testWidgets('Ctrl+C uses the same displayed-text contract', (tester) async {
    await tester.pumpWidget(harness('## **Selected** `code`'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(2, 2));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    expect(copied, 'Selected code');
  });

  for (final action in [
    ContextMenuButtonType.copy,
    ContextMenuButtonType.share
  ]) {
    testWidgets('toolbar $action uses the same displayed-text contract',
        (tester) async {
      await tester.pumpWidget(harness('## **Selected** `code`'));
      await tester.pumpAndSettle();
      final state = tester.state<region.SelectableRegionState>(
          find.byType(region.SelectableRegion));
      state.selectAll(SelectionChangedCause.toolbar);
      await tester.pump();
      expect(reported, 'Selected code');
      state.contextMenuButtonItems
          .firstWhere((item) => item.type == action)
          .onPressed!();
      await tester.pump();
      expect(action == ContextMenuButtonType.copy ? copied : shared,
          'Selected code');
    });
  }

  testWidgets('wrapped inline math preserves text order and no soft newline',
      (tester) async {
    const text =
        r'Before some words $\frac{a}{b}$ then more words $x^2$ after.';
    await tester.pumpWidget(harness(text, width: 160));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(2, 2));
    await shortcut(tester, LogicalKeyboardKey.keyA);
    await shortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied, r'Before some words \frac{a}{b} then more words x^2 after.');
  });

  testWidgets('inline widget text alternatives retain paragraph order',
      (tester) async {
    final node =
        ParserController().parse('Before reference after.').blocks.first;
    await tester.pumpWidget(area(SourceAwareWidget(
      attachment: MarkdownSourceAttachment(blockNode: node),
      child: const Text.rich(TextSpan(children: [
        TextSpan(text: 'Before reference ', style: TextStyle(fontSize: 28)),
        WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: Text('1', style: TextStyle(fontSize: 10))),
        TextSpan(text: ' after.', style: TextStyle(fontSize: 28)),
      ])),
    )));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(2, 2));
    await shortcut(tester, LogicalKeyboardKey.keyA);
    await shortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied, 'Before reference 1 after.');
  });

  testWidgets('Select All stays scoped; drag-copy still crosses messages',
      (tester) async {
    await tester.pumpWidget(area(Column(children: [
      SelectionScope(child: content('First **message**.')),
      SelectionScope(child: content('Second `message`.')),
    ])));
    await tester.pumpAndSettle();
    final paragraphs = tester.allRenderObjects.whereType<RenderParagraph>();
    final first =
        paragraphs.firstWhere((p) => p.text.toPlainText() == 'First message.');
    final second =
        paragraphs.firstWhere((p) => p.text.toPlainText() == 'Second message.');
    await tester.tapAt(second.localToGlobal(const Offset(2, 2)));
    await shortcut(tester, LogicalKeyboardKey.keyA);
    await shortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied, 'Second message.');

    Offset edge(RenderParagraph p, TextSelection selection, bool end) {
      final boxes = p.getBoxesForSelection(selection);
      final box = end ? boxes.last : boxes.first;
      return p.localToGlobal(Offset(
          end ? box.right - 0.1 : box.left + 0.1, (box.top + box.bottom) / 2));
    }

    final from = edge(
        first, const TextSelection(baseOffset: 6, extentOffset: 14), false);
    final to =
        edge(second, const TextSelection(baseOffset: 0, extentOffset: 6), true);
    final gesture =
        await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 8)!);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    await shortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied, 'message.\n\nSecond');
    expect(reported, copied);
  });
}
