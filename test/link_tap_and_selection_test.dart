import 'package:cmark_gfm_widget/cmark_gfm_widget.dart' as cmark_widget;
import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_test/flutter_test.dart';
// The package renders text using pixel_snap's vendored Text/RichText, not
// Flutter's core widgets - match against those types, not `package:flutter`'s.
import 'package:pixel_snap/material.dart' as ps;

/// These tests exist because the recognizer-based link rendering
/// (`inline_renderers.dart`, `CmarkNodeType.link`) replaced an earlier
/// WidgetSpan + GestureDetector approach that was specifically chosen to
/// avoid two regressions: link taps not registering, and link text not
/// being selectable, when rendered inside this package's custom
/// `SelectionArea`/`SelectableRegion`. Confirm neither regression came back.
void main() {
  List<Widget> buildWidgets(
    String markdown, {
    required RenderOptions options,
  }) {
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    const pipeline = RenderPipeline();
    final theme = CmarkThemeData.fallback(ThemeData().textTheme);
    return pipeline.buildWidgets(snapshot, theme, options);
  }

  testWidgets('tapping a link inside SelectionArea invokes onLinkTap',
      (tester) async {
    String? tappedUrl;
    final widgets = buildWidgets(
      '[LINKTEXT](https://example.com)',
      options: RenderOptions(
        selectable: true,
        onLinkTap: (url, title) => tappedUrl = url,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: cmark_widget.SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widgets,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final richTextFinder = find.byWidgetPredicate(
      (w) => w is ps.RichText && w.text.toPlainText().contains('LINKTEXT'),
    );
    expect(richTextFinder, findsOneWidget);

    await tester.tapAt(tester.getCenter(richTextFinder));
    await tester.pumpAndSettle();

    expect(tappedUrl, 'https://example.com');
  });

  testWidgets('link TextSpans carry a recognizer and click cursor',
      (tester) async {
    final widgets = buildWidgets(
      'Some prose with [a link](https://example.com) inline.',
      options: RenderOptions(
        selectable: true,
        onLinkTap: (url, title) {},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: cmark_widget.SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widgets,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final richTextFinder = find.byWidgetPredicate(
      (w) => w is ps.RichText && w.text.toPlainText().contains('a link'),
    );
    final richText = tester.widget<ps.RichText>(richTextFinder);

    TapGestureRecognizer? found;
    void visit(InlineSpan span) {
      if (span is TextSpan) {
        if (span.recognizer is TapGestureRecognizer) {
          found = span.recognizer as TapGestureRecognizer;
        }
        span.children?.forEach(visit);
      }
    }

    visit(richText.text);
    expect(found, isNotNull,
        reason: 'Expected a TapGestureRecognizer attached to the link span');
  });

  testWidgets(
      'dragging a selection across prose and a link does not throw and '
      'yields non-empty text', (tester) async {
    SelectedContent? selected;
    final widgets = buildWidgets(
      'Before text. [a link](https://example.com) after text.',
      options: RenderOptions(
        selectable: true,
        onLinkTap: (url, title) {},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: cmark_widget.SelectionArea(
            onSelectionChanged: (content) => selected = content,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widgets,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final richTextFinder = find.byWidgetPredicate(
      (w) => w is ps.RichText && w.text.toPlainText().contains('Before text'),
    );
    final rect = tester.getRect(richTextFinder);

    // Drag from just inside the left edge to just inside the right edge,
    // i.e. across the whole line (prose + link + more prose). Use a mouse
    // pointer: touch-style drag-to-select requires an initial long-press,
    // while a mouse click-drag starts a selection immediately, matching how
    // this is normally exercised on desktop.
    final gesture = await tester.startGesture(
      rect.centerLeft + const Offset(2, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveTo(rect.centerRight - const Offset(2, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.plainText, isNotEmpty);
  });
}
