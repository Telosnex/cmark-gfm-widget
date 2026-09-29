import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_snap/material.dart' as ps;


const _parserOptions = CmarkParserOptions(enableMath: true);

const _reply = '# Streaming\n'
    '\n'
    'First paragraph with **bold**, a [link](https://example.com) and a '
    'note[^1].\n'
    '\n'
    '- one\n'
    '- [x] two\n'
    '\n'
    '| a | b |\n'
    '|---|:-:|\n'
    '| 1 | 2 |\n'
    '\n'
    '```dart\n'
    'void main() {}\n'
    '```\n'
    '\n'
    '> A quote with \$x^2\$ and another note[^1].\n'
    '\n'
    'Last paragraph.\n'
    '\n'
    '[^1]: https://example.com/source\n';

/// Snapshots of [text] streamed in [chunkSize] pieces into one parser, as a
/// streaming client makes them.
List<DocumentSnapshot> _streamedSnapshots(String text, {int chunkSize = 7}) {
  final parser = CmarkParser(options: _parserOptions);
  final registry = StableIdRegistry();
  final snapshots = <DocumentSnapshot>[];
  for (var i = 0; i < text.length; i += chunkSize) {
    final end = i + chunkSize < text.length ? i + chunkSize : text.length;
    parser.feed(text.substring(i, end));
    snapshots.add(
      DocumentSnapshot.fromRoot(
        root: parser.finishClone(),
        registry: registry,
        revision: snapshots.length,
      ),
    );
  }
  return snapshots;
}

DocumentSnapshot _snapshot(String text, [StableIdRegistry? registry]) =>
    ParserController(registry: registry, parserOptions: _parserOptions)
        .parse(text);

/// Pumps [results] and describes the built tree: each widget's type, and
/// each paragraph's spans.
Future<String> _describe(
  WidgetTester tester,
  List<BlockRenderResult> results,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Column(children: [for (final r in results) r.widget]),
    ),
  );
  final buffer = StringBuffer();
  void visit(Element element) {
    final widget = element.widget;
    buffer.writeln(widget.toStringShort());
    if (widget is ps.RichText) buffer.writeln(widget.text.toStringDeep());
    element.visitChildren(visit);
  }

  tester.binding.rootElement!.visitChildren(visit);
  // Drop identity hashes, such as those of keys and widget spans.
  return buffer.toString().replaceAll(RegExp('#[0-9a-f]{5}'), '');
}

void main() {
  final theme = CmarkThemeData.fallback(ThemeData().textTheme);
  const pipeline = RenderPipeline();
  const options = RenderOptions(selectable: true);

  group('BlockRenderCache', () {
    testWidgets('streamed renders equal renders without a cache',
        (tester) async {
      final cache = BlockRenderCache();
      var reused = 0;
      List<BlockRenderResult>? previous;
      for (final snapshot in _streamedSnapshots(_reply)) {
        final cached = pipeline.render(snapshot, theme, options, cache: cache);
        final fresh = pipeline.render(snapshot, theme, options);
        expect(
          await _describe(tester, cached),
          await _describe(tester, fresh),
          reason: 'after revision ${snapshot.revision}',
        );
        if (previous != null) {
          final before = {for (final r in previous) r.id: r.widget};
          reused +=
              cached.where((r) => identical(before[r.id], r.widget)).length;
        }
        previous = cached;
      }
      expect(reused, greaterThan(0));
    });

    test('unchanged blocks keep their widgets while text streams', () {
      final cache = BlockRenderCache();
      final registry = StableIdRegistry();
      final first = pipeline.render(
        _snapshot('# Title\n\nOne\n\nTw', registry),
        theme,
        options,
        cache: cache,
      );
      final second = pipeline.render(
        _snapshot('# Title\n\nOne\n\nTwo', registry),
        theme,
        options,
        cache: cache,
      );
      expect(second, hasLength(3));
      expect(second[0].widget, same(first[0].widget));
      expect(second[1].widget, same(first[1].widget));
      expect(second[2].widget, isNot(same(first[2].widget)));
    });

    test('a changed block at the same position gets a new widget', () {
      final cache = BlockRenderCache();
      final registry = StableIdRegistry();
      final first = pipeline.render(
        _snapshot('A\n\nB\n\nC\n', registry),
        theme,
        options,
        cache: cache,
      );
      final second = pipeline.render(
        _snapshot('A\n\nX\n\nC\n', registry),
        theme,
        options,
        cache: cache,
      );
      expect(second[0].widget, same(first[0].widget));
      expect(second[1].widget, isNot(same(first[1].widget)));
      expect(second[2].widget, same(first[2].widget));
    });

    test('builders run only for blocks that are rendered again', () {
      final cache = BlockRenderCache();
      final registry = StableIdRegistry();
      var calls = 0;
      final withBuilder = RenderOptions(
        selectable: true,
        footnoteReferenceBuilder: (node, context, style) {
          calls++;
          return TextSpan(text: '[${node.footnoteRefIndex}]', style: style);
        },
      );
      const notes = 'A[^1]\n\nB[^1]\n\n[^1]: n\n';
      pipeline.render(
        _snapshot(notes, registry),
        theme,
        withBuilder,
        cache: cache,
      );
      expect(calls, 2);
      pipeline.render(
        _snapshot('${notes}C\n', registry),
        theme,
        withBuilder,
        cache: cache,
      );
      expect(calls, 2);
    });

    test('a new theme, flag or cache key renders every block again', () {
      final registry = StableIdRegistry();
      final snapshot = _snapshot('A\n\nB\n', registry);
      List<Widget> render(
        BlockRenderCache cache,
        CmarkThemeData theme,
        RenderOptions options, [
        Object? key,
      ]) =>
          pipeline
              .render(snapshot, theme, options, cache: cache, cacheKey: key)
              .map((r) => r.widget)
              .toList();

      final cache = BlockRenderCache();
      final first = render(cache, theme, options, 1);
      expect(render(cache, theme, options, 1), orderedEquals(first));

      final otherTheme = CmarkThemeData.fallback(ThemeData().textTheme);
      expect(render(cache, otherTheme, options, 1).first,
          isNot(same(first.first)));
      final withTheme = render(cache, otherTheme, options, 1);
      expect(
        render(cache, otherTheme, const RenderOptions(), 1).first,
        isNot(same(withTheme.first)),
      );
      final withFlag = render(cache, otherTheme, const RenderOptions(), 1);
      expect(
        render(cache, otherTheme, const RenderOptions(), 2).first,
        isNot(same(withFlag.first)),
      );
    });

    test('only the first block depends on leading spans', () {
      final cache = BlockRenderCache();
      final snapshot = _snapshot('A\n\nB\n');
      final first = pipeline.render(
        snapshot,
        theme,
        const RenderOptions(leadingSpans: [TextSpan(text: 'x ')]),
        cache: cache,
      );
      final same1 = pipeline.render(
        snapshot,
        theme,
        const RenderOptions(leadingSpans: [TextSpan(text: 'x ')]),
        cache: cache,
      );
      expect(same1[0].widget, same(first[0].widget));
      final changed = pipeline.render(
        snapshot,
        theme,
        const RenderOptions(leadingSpans: [TextSpan(text: 'y ')]),
        cache: cache,
      );
      expect(changed[0].widget, isNot(same(first[0].widget)));
      expect(changed[1].widget, same(first[1].widget));
    });

    test('repaintBoundaries puts each block behind a boundary', () {
      final results = pipeline.render(
        _snapshot('A\n\nB\n'),
        theme,
        const RenderOptions(repaintBoundaries: true),
      );
      expect(
          results.map((r) => r.widget), everyElement(isA<RepaintBoundary>()));
    });
  });

  testWidgets('CmarkMarkdownColumn keeps unchanged blocks while streaming',
      (tester) async {
    Future<void> pump(String data) => tester.pumpWidget(
          MaterialApp(
            home: CmarkMarkdownColumn(data: data, theme: theme),
          ),
        );
    await pump('# Title\n\nOne\n\nTw');
    final title = tester.widget(find.byType(KeyedSubtree).first);
    final heading = (title as KeyedSubtree).child;
    await pump('# Title\n\nOne\n\nTwo');
    expect(
      (tester.widget(find.byType(KeyedSubtree).first) as KeyedSubtree).child,
      same(heading),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is ps.RichText && w.text.toPlainText() == 'Two',
      ),
      findsOneWidget,
    );
  });
}
