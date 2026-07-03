import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter/material.dart' hide SelectionArea;
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_snap/material.dart' as ps;

void main() {
  Widget wrap(String markdown) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CmarkMarkdownColumn(data: markdown),
        ),
      ),
    );
  }

  Finder codeBlockFinder() => find.byWidgetPredicate(
        (widget) => widget is RepaintBoundary && widget.child is ps.Container,
      );

  testWidgets('code block renders one paragraph per line', (tester) async {
    await tester.pumpWidget(wrap('```dart\nfinal a = 1;\nfinal b = 2;\n```'));
    final richTexts = find.descendant(
      of: codeBlockFinder(),
      matching: find.byType(ps.RichText),
    );
    expect(richTexts, findsNWidgets(2));
  });

  testWidgets('blank lines occupy the same height as text lines',
      (tester) async {
    await tester.pumpWidget(wrap('```\na\n\nb\n```'));
    final withBlank = tester.getSize(codeBlockFinder().first);

    await tester.pumpWidget(wrap('```\na\nx\nb\n```'));
    final withoutBlank = tester.getSize(codeBlockFinder().first);

    expect(withBlank.height, withoutBlank.height);
  });

  testWidgets('streaming appends keep earlier line spans identical',
      (tester) async {
    await tester.pumpWidget(wrap('```dart\nfinal a = 1;\nfinal b = 2;\n```'));
    final before = tester
        .widgetList<ps.RichText>(
          find.descendant(
            of: codeBlockFinder(),
            matching: find.byType(ps.RichText),
          ),
        )
        .toList();
    expect(before, hasLength(2));

    // Simulate a streamed chunk that completes line 2 and starts line 3.
    await tester.pumpWidget(
      wrap('```dart\nfinal a = 1;\nfinal b = 2;\nfinal c =\n```'),
    );
    final after = tester
        .widgetList<ps.RichText>(
          find.descendant(
            of: codeBlockFinder(),
            matching: find.byType(ps.RichText),
          ),
        )
        .toList();
    expect(after, hasLength(3));

    // Line 1 completed before the first frame: identical span instance means
    // RenderParagraph skips both updateRenderObject work and relayout.
    expect(identical(before[0].text, after[0].text), isTrue);
  });
}
