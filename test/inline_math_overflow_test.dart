import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_snap/material.dart';

void main() {
  testWidgets('wide inline math does not overflow a narrow viewport',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: CmarkMarkdownColumn(
              data: r'Cost: $oldOutputCost '
                  r'\frac{newOutputPrice}{oldOutputPrice} + '
                  r'oldInputCacheCost '
                  r'\frac{newInputPrice}{oldInputPrice}$ done.',
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    final scrollView = find.byType(SingleChildScrollView);
    expect(scrollView, findsOneWidget);
    final scrollable = find.descendant(
      of: scrollView,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.drag(scrollView, const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
  });

  testWidgets('inline math scroll viewport supports intrinsic table layout',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CmarkMarkdownColumn(
            data: r'''
| Formula |
| --- |
| $x^{2}$ |
''',
          ),
        ),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
