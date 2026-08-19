import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:cmark_gfm_widget/src/html_inline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_snap/material.dart' as ps;

const _toolUsageTable = '''
| Most-used tools |
| --- |
| `read_multiple_files` **20.5034**<br>`search_filenames` **17.4871**<br>`search_files_for_text` **14.4547**<br>`reverse_geocode` **13.3454**<br>`write_file` **13.0177** |
''';

void main() {
  test('only bare HTML br tag variants become newlines', () {
    for (final tag in const ['<br>', '<br/>', '<br />', '<BR>']) {
      expect(inlineHtmlPlainText(tag), '\n');
    }

    expect(inlineHtmlPlainText('<br class="spacer">'), '<br class="spacer">');
    expect(inlineHtmlPlainText('<span>'), '<span>');
  });

  testWidgets('HTML br tags render as line breaks inside table cells',
      (tester) async {
    await tester.pumpWidget(
      const ps.MaterialApp(
        home: ps.Scaffold(
          body: CmarkMarkdownColumn(data: _toolUsageTable),
        ),
      ),
    );

    final cellText = tester
        .widgetList<ps.RichText>(find.byType(ps.RichText))
        .map((widget) => widget.text.toPlainText())
        .singleWhere((text) => text.contains('read_multiple_files'));

    expect(
      cellText,
      'read_multiple_files 20.5034\n'
      'search_filenames 17.4871\n'
      'search_files_for_text 14.4547\n'
      'reverse_geocode 13.3454\n'
      'write_file 13.0177',
    );
    expect(cellText, isNot(contains('<br>')));
  });
}
