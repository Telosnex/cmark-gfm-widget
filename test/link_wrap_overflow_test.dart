import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_snap/material.dart' as ps;

import 'test_helpers.dart';

/// Regression test for a bug where a link whose visible text is a long bare
/// URL (e.g. `[https://.../very/long/path](...)`) would visually overflow
/// into whatever Markdown block rendered below it.
///
/// Root cause: links are rendered as a `WidgetSpan` wrapping a nested
/// `Text.rich`, so that a `GestureDetector` can handle taps (see
/// `inline_renderers.dart`). From the perspective of the *outer* paragraph's
/// line-breaking algorithm, a WidgetSpan is a single atomic inline box. If
/// that nested Text.rich were allowed to soft-wrap, a long link label could
/// make the WidgetSpan many lines tall. Meanwhile, `_buildTextualBlock`
/// renders every textual block with `strutStyle: forceStrutHeight: true`
/// (so inline code aligns consistently across mixed prose/code lines);
/// that setting forces *every* line box in the outer paragraph to the
/// strut's single-line height, ignoring taller inline content. The net
/// effect: a multi-line link WidgetSpan would report/measure fine on its
/// own, but the outer paragraph would only reserve one line's worth of
/// vertical space for it, so the excess height painted downward directly on
/// top of the next block.
///
/// The fix constrains the link's nested Text.rich to a single line
/// (ellipsis instead of wrapping) with a matching forced strut, so its
/// measured height always equals exactly one line of the surrounding
/// paragraph - it can never spill into content below.
void main() {
  /// Returns the global top offset and height of every `RichText` (as
  /// rendered by the pixel_snap package, which vendors its own `RichText`/
  /// `RenderParagraph`) in the current widget tree, in paint order.
  List<({double top, double height, String text})> richTextGeometry(
    WidgetTester tester,
  ) {
    final results = <({double top, double height, String text})>[];
    void visit(Element element) {
      final widget = element.widget;
      if (widget is ps.RichText) {
        final renderObject = element.renderObject;
        if (renderObject is RenderBox && renderObject.hasSize) {
          final topLeft = renderObject.localToGlobal(Offset.zero);
          results.add((
            top: topLeft.dy,
            height: renderObject.size.height,
            text: widget.text.toPlainText(),
          ));
        }
      }
      element.visitChildren(visit);
    }

    visit(tester.binding.rootElement!);
    return results;
  }

  testWidgets('long link label does not overlap following content',
      (tester) async {
    // A link whose visible label is a long bare URL - previously this could
    // wrap across many lines inside its WidgetSpan and bleed into the
    // paragraph below.
    const markdown =
        '[https://example.com/some/very/long/path/that/will/definitely/wrap/across/several/lines/of/text/in/a/narrow/column](https://example.com/some/very/long/path)\n\n'
        'MARKER_PARAGRAPH_BELOW';

    final results = renderMarkdownBlocks(markdown);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: results.map((r) => r.widget).toList(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final geometry = richTextGeometry(tester);

    final linkGeometry =
        geometry.firstWhere((g) => g.text.contains('example.com'));
    final markerGeometry =
        geometry.firstWhere((g) => g.text == 'MARKER_PARAGRAPH_BELOW');

    // The link's rendered box must not extend past where the following
    // paragraph begins.
    final linkBottom = linkGeometry.top + linkGeometry.height;
    expect(
      linkBottom,
      lessThanOrEqualTo(markerGeometry.top + 0.5), // small layout tolerance
      reason: 'Long link label overflowed into the following paragraph '
          '(link bottom=$linkBottom, marker top=${markerGeometry.top})',
    );
  });

  testWidgets('short link label still aligns with surrounding text',
      (tester) async {
    const markdown = 'See [this link](https://example.com) for more.';

    final results = renderMarkdownBlocks(markdown);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: results.map((r) => r.widget).toList(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final geometry = richTextGeometry(tester);
    final heights = geometry.map((g) => g.height).toSet();

    // All RichText boxes in this single-line paragraph (the outer paragraph
    // placeholder box and the nested link box) should report the exact same
    // line height - no residual mismatch from the link's own strut metrics.
    expect(heights.length, 1,
        reason: 'Expected all line boxes to share one height, got: $geometry');
  });
}
