import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:cmark_gfm_widget/src/flutter/selectable_region.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    hide SelectableRegion, SelectableRegionState, SelectionArea;

/// A lazy scrollable disposes selectables that scroll out of its cache
/// extent. The selection edge in such a selectable has a null
/// [SelectionPoint], but the other edge can still be in view, so the context
/// menu stays open. The menu rebuilds its anchors on every frame. Before the
/// fix, the glyph-height getters threw a null-check error on each of those
/// frames.
void main() {
  final String codeBlock = [
    '```dart',
    for (var i = 0; i < 20; i++) 'final line$i = $i;',
    '```',
  ].join('\n');

  List<Widget> buildWidgets(String markdown) {
    final snapshot = ParserController().parse(markdown);
    return const RenderPipeline().buildWidgets(
      snapshot,
      CmarkThemeData.fallback(ThemeData().textTheme),
      const RenderOptions(selectable: true),
    );
  }

  testWidgets(
      'open context menu does not throw when one selection edge is '
      'scrolled out of a lazy list', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: ListView.builder(
              controller: scrollController,
              itemCount: 30,
              itemBuilder: (context, index) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: buildWidgets(codeBlock),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );

    // Select every built code block and open the context menu.
    region.selectAll(SelectionChangedCause.toolbar);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(region.selectionOverlay?.toolbarIsVisible, isTrue);

    // The first code block (the start edge) leaves the cache extent and is
    // disposed. The end edge is still in view, so the menu stays open.
    scrollController.jumpTo(1000);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(region.selectionOverlay?.toolbarIsVisible, isTrue);

    // Both edges are disposed: the menu closes without an error.
    scrollController.jumpTo(3000);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(region.selectionOverlay?.toolbarIsVisible, isNot(isTrue));
  });
}
