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
    final ignorePointer = inlineMath.child as IgnorePointer;
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
}
