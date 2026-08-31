import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:pixel_snap/material.dart';

void main() {
  testWidgets('inline math falls back to text on unknown Unicode symbols',
      (tester) async {
    const literal = 'bad ❌ ⏰';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: CmarkMarkdownColumn(
              data: r'Before $bad ❌ ⏰$ after.',
            ),
          ),
        ),
      ),
    );

    final paragraph = tester.widgetList<Text>(find.byType(Text)).singleWhere(
          (widget) =>
              widget.textSpan?.toPlainText().contains('Before') ?? false,
        );
    final rootSpan = paragraph.textSpan! as TextSpan;
    final widgetSpan = rootSpan.children!.whereType<WidgetSpan>().single;
    final inlineMath = widgetSpan.child as InlineMathSelectable;
    final scrollView = inlineMath.child as SingleChildScrollView;
    final ignorePointer = scrollView.child! as IgnorePointer;
    final math = ignorePointer.child as Math;

    expect(inlineMath.literal, literal);
    expect(math.parseError?.message, contains('unknownSymbol'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('block math falls back to text on unknown Unicode symbols',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CmarkMarkdownColumn(
            data: r'''
$$
bad ❌ ⏰
$$
''',
          ),
        ),
      ),
    );

    final math = tester.widget<Math>(find.byType(Math));

    expect(math.parseError?.message, contains('unknownSymbol'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('street-lit luminance markdown renders third equation as LaTeX',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: CmarkMarkdownColumn(
              parserOptions: CmarkParserOptions(
                enableMath: true,
                mathOptions: CmarkMathOptions(
                  allowBracketDelimiters: true,
                ),
              ),
              data: r'''
If your D65 white is normalized to:

\[
Y = 100
\]

and represents, say, **100 cd/m²**, then a street-lit surface at **0.3 cd/m²** has:

\[
Y_{relative} = 0.3
\]

on that 0–100 scale.

So under a street lamp, visible surfaces might often be around:

\[
Y \approx 0.1 \text{ to } 5 \text{ cd/m²}
\]

with many ordinary night street scenes around **0.2–2 cd/m²**.
''',
            ),
          ),
        ),
      ),
    );

    final mathWidgets = tester.widgetList<Math>(find.byType(Math)).toList();

    expect(mathWidgets, hasLength(3));
    expect(mathWidgets[2].parseError, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiline bracket math keeps a standalone plus in LaTeX',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CmarkMarkdownColumn(
            parserOptions: CmarkParserOptions(
              enableMath: true,
              mathOptions: CmarkMathOptions(
                allowBracketDelimiters: true,
              ),
            ),
            data: r'''
\[
oldOutputCost = T_{out} \times oldOutputPrice
\]

\[
oldInputCacheCost = publishedCost - oldOutputCost
\]

\[
newCost \approx
oldOutputCost \frac{newOutputPrice}{oldOutputPrice}
+
oldInputCacheCost \frac{newInputPrice}{oldInputPrice}
\]
''',
          ),
        ),
      ),
    );

    final mathWidgets = tester.widgetList<Math>(find.byType(Math)).toList();

    expect(mathWidgets, hasLength(3));
    expect(mathWidgets.map((math) => math.parseError), everyElement(isNull));
    expect(tester.takeException(), isNull);
  });
}
