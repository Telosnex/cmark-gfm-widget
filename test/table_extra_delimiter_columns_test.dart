import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:cmark_gfm_dart/cmark_gfm_dart.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_snap_fork/material.dart';

/// Real-world LLM output: 3 header cells, but the delimiter row has 4
/// columns. Strict GFM rejects this as a table; cmark_gfm's
/// `allowExtraTableDelimiters` (default on) ignores the extra column.
const _extraDelimiterTable = '''
### Unlocking an already signed-in device

| Device | Before | Proposed |
|---|---|---|---|
| Existing | “Check the account before continuing.” | **Unlock your other device?** |
| Receiving | “Check the account before continuing.” | **Unlock encrypted data?** |
| Both | “Unlock encrypted data for this account” | Show **[email]** clearly below the heading. |
| Both | **Compare to unlock encrypted data** | **Continue** |
| Both | “This does not transfer a key or change your account yet.” | “Next, compare the symbols on both devices. Nothing is approved yet.” |
''';

void main() {
  testWidgets(
      'extra delimiter columns are ignored: renders header-width table with all cells',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            child: CmarkMarkdownColumn(data: _extraDelimiterTable),
          ),
        ),
      ),
    );

    final table = tester.widget<Table>(find.byType(Table));
    expect(table.children, hasLength(6));
    for (final row in table.children) {
      expect(row.children, hasLength(3));
    }
    const expectedRows = [
      ['Device', 'Before', 'Proposed'],
      [
        'Existing',
        '“Check the account before continuing.”',
        'Unlock your other device?'
      ],
      [
        'Receiving',
        '“Check the account before continuing.”',
        'Unlock encrypted data?'
      ],
      [
        'Both',
        '“Unlock encrypted data for this account”',
        'Show [email] clearly below the heading.'
      ],
      ['Both', 'Compare to unlock encrypted data', 'Continue'],
      [
        'Both',
        '“This does not transfer a key or change your account yet.”',
        '“Next, compare the symbols on both devices. Nothing is approved yet.”'
      ],
    ];
    for (var row = 0; row < expectedRows.length; row++) {
      for (var column = 0; column < 3; column++) {
        final cell = table.children[row].children[column];
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
              of: find.byWidget(cell), matching: find.byType(RichText)),
        );
        expect(paragraph.text.toPlainText(), expectedRows[row][column],
            reason: 'row $row, column $column');
      }
    }
    final paragraphs = tester.allRenderObjects
        .whereType<RenderParagraph>()
        .map((paragraph) => paragraph.text.toPlainText())
        .toList();
    expect(paragraphs, contains('Unlocking an already signed-in device'));
    expect(paragraphs, contains('Unlock your other device?'));
    expect(paragraphs, contains('Unlock encrypted data?'));
    expect(paragraphs, contains('Show [email] clearly below the heading.'));
    expect(
        paragraphs,
        contains(
            '“Next, compare the symbols on both devices. Nothing is approved yet.”'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'extra delimiter column table renders at phone width without overflow',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 390,
              child: CmarkMarkdownColumn(data: _extraDelimiterTable),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Table), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'streamed in chunks, extra delimiter columns never throw and end as a table',
      (tester) async {
    final parser = CmarkParser();
    final registry = StableIdRegistry();
    final markdown = _extraDelimiterTable.trimRight();
    var revision = 0;
    for (var offset = 0; offset < markdown.length; offset += 17) {
      parser.feed(
          markdown.substring(offset, (offset + 17).clamp(0, markdown.length)));
      final snapshot = DocumentSnapshot.fromRoot(
        root: parser.finishClone(),
        registry: registry,
        revision: ++revision,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CmarkMarkdownColumn(snapshot: snapshot),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    }
    expect(tester.widget<Table>(find.byType(Table)).children, hasLength(6));
  });
}
