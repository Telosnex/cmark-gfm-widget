import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' hide SelectionArea;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const repro = '''
**Chunk 4 — The optimization (0:30–0:40)**

*VO/caption:* "Before you open the door: Mentats, X-Cell, sleep for Well Rested — stack every XP buff. Then open with an explosive into the crowd. Simultaneous kills during a Savant streak is the highest XP-per-second moment in the game. Go."

*Visual prompt:* Vertical 9:16, motion-graphics checklist style: three item icons (pill tin, syringe, bed) stamping onto screen one by one with checkmarks, then cut to the tactical room diagram from before — an explosion ripple wipes all fifteen red dots at once and a cascade of green "+XP" numbers floods the screen, ending on a gold "LEVEL UP" counter rolling over.

---

Structure notes:
- Chunk 1 = hook via *contrarian claim*, chunk 2 = *why*, chunk 3 = *where*, chunk 4 = *how to maximize*. Each is one idea, which is what makes 10s chunks work.
- The consistent visual thread is the tactical-map/motion-graphics style instead of a character — much easier for AI generators to keep consistent than a protagonist, and it reads as "guide" not "cinematic slop."
- Record the VO yourself or use TTS; burned-in AI text will mangle words like "Idiot Savant."
''';

void main() {
  group('Cmd+C repro', () {
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

    Widget buildTestWidget(String markdown) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 800,
              child: CmarkMarkdownColumn(
                data: markdown,
                selectable: true,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('select all + copy on repro markdown', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestWidget(repro));
      await tester.pumpAndSettle();

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

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('Chunk 4'));
    });

    testWidgets('drag-select part of repro + copy', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestWidget(repro));
      await tester.pumpAndSettle();

      // Drag from near the top to far down the document with a mouse.
      final gesture = await tester.startGesture(
        const Offset(10, 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (var y = 50.0; y <= 1200; y += 50) {
        await gesture.moveTo(Offset(400, y));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      expect(clipboardText, isNotNull);
    });

    testWidgets('select all + copy on FULL repro markdown', (tester) async {
      tester.view.physicalSize = const Size(800, 8000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestWidget(fullRepro));
      await tester.pumpAndSettle();

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

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('Chunk 4'));
    });

    testWidgets('drag-select FULL repro + copy', (tester) async {
      tester.view.physicalSize = const Size(800, 8000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildTestWidget(fullRepro));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        const Offset(10, 10),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (var y = 50.0; y <= 4000; y += 100) {
        await gesture.moveTo(Offset(400, y));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('Chunk 4'));
    });
  testWidgets('STREAMED full repro, then select all + copy', (tester) async {
    tester.view.physicalSize = const Size(800, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Simulate streaming: pump with growing prefixes of the document,
    // like the app does during token streaming. Same widget identity, so
    // RenderObjects are reused across snapshot revisions.
    const chunkSize = 120;
    for (var end = chunkSize; end < fullRepro.length; end += chunkSize) {
      await tester.pumpWidget(
        buildTestWidget(fullRepro.substring(0, end)),
      );
      await tester.pump();
    }
    await tester.pumpWidget(buildTestWidget(fullRepro));
    await tester.pumpAndSettle();

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

    expect(clipboardText, isNotNull);
    expect(clipboardText, contains('Chunk 4'));
  });

  testWidgets('STREAMED full repro, then drag-select + copy', (tester) async {
    tester.view.physicalSize = const Size(800, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const chunkSize = 120;
    for (var end = chunkSize; end < fullRepro.length; end += chunkSize) {
      await tester.pumpWidget(
        buildTestWidget(fullRepro.substring(0, end)),
      );
      await tester.pump();
    }
    await tester.pumpWidget(buildTestWidget(fullRepro));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      const Offset(10, 10),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var y = 50.0; y <= 4000; y += 100) {
      await gesture.moveTo(Offset(400, y));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();

    expect(clipboardText, isNotNull);
    expect(clipboardText, contains('Chunk 4'));
  });
});
}

const fullRepro = '''
Fair hit. That storyboard was vibes with zero information — it doesn't teach the viewer the one thing that made this conversation useful: **interior cells aggro all at once, so packed interiors are the best kill-XP farms, and Idiot Savant's kill-streak turns a room-wipe into the best XP-per-second in the game.**

The real fix: in an info-TikTok, **the content lives in the voiceover/captions, not the footage**. AI video can't render accurate gameplay anyway, so the visuals are just B-roll while the script does the work. Here's the rebuild — each chunk now delivers one actual idea:

---

**Chunk 1 — The claim (0:00–0:10)**

*VO/caption:* "You're farming XP wrong in Fallout 4. Clearing outdoor zones like Quincy feels big, but enemies aggro in little clusters — you fight 3 guys at a time. The XP is in *interiors*."

*Visual prompt:* Vertical 9:16, stylized post-apocalyptic map view: a ruined town seen from above, small red enemy dots scattered far apart in separate clusters, camera slowly zooming across them. Muted colors, tactical UI aesthetic, thin white grid lines. One cluster highlights at a time with a small red pulse while the rest stay dim.

**Chunk 2 — The mechanic (0:10–0:20)**

*VO/caption:* "Interior cells are small enough that one gunshot pulls the *entire* population at once. That matters because Idiot Savant rank 3 gives bonus XP on every kill for a full minute after it procs — a room-wipe is its perfect use case."

*Visual prompt:* Vertical 9:16, same tactical map aesthetic: cutaway diagram of a small building interior, fifteen red dots packed in one room. A single white ping ripples out from the entrance and every red dot simultaneously flares bright red and converges. Clean motion-graphics style, dark background, green XP counters ticking rapidly upward on the right edge.

**Chunk 3 — The spot (0:20–0:30)**

*VO/caption:* "Best spot: the Combat Zone, five minutes from Goodneighbor. One theater, one room, fifteen raiders watching a cage fight — all hostile the moment you walk in. Bonus: you get Cait as a companion after."

*Visual prompt:* Vertical 9:16, gritty illustrated cutaway of a ruined vintage theater: caged fighting ring center stage, rows of red velvet seats filled with silhouetted figures, all marked with red hostile indicators. Camera pushes from the entrance doors down the aisle. Comic-book / graphic-novel style, red and black palette, location pin dropping onto the building at the end.

**Chunk 4 — The optimization (0:30–0:40)**

*VO/caption:* "Before you open the door: Mentats, X-Cell, sleep for Well Rested — stack every XP buff. Then open with an explosive into the crowd. Simultaneous kills during a Savant streak is the highest XP-per-second moment in the game. Go."

*Visual prompt:* Vertical 9:16, motion-graphics checklist style: three item icons (pill tin, syringe, bed) stamping onto screen one by one with checkmarks, then cut to the tactical room diagram from before — an explosion ripple wipes all fifteen red dots at once and a cascade of green "+XP" numbers floods the screen, ending on a gold "LEVEL UP" counter rolling over.

---

Structure notes:
- Chunk 1 = hook via *contrarian claim*, chunk 2 = *why*, chunk 3 = *where*, chunk 4 = *how to maximize*. Each is one idea, which is what makes 10s chunks work.
- The consistent visual thread is the tactical-map/motion-graphics style instead of a character — much easier for AI generators to keep consistent than a protagonist, and it reads as "guide" not "cinematic slop."
- Record the VO yourself or use TTS; burned-in AI text will mangle words like "Idiot Savant."
''';
