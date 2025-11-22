import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:cmark_gfm_widget/src/parser/parser_controller.dart';
import 'package:cmark_gfm_widget/src/selection/markdown_selection_model.dart';
import 'package:cmark_gfm_widget/src/selection/selection_serializer.dart';
import 'package:cmark_gfm_widget/src/selection/leaf_text_registry.dart';
import 'package:cmark_gfm_widget/src/widgets/source_markdown_registry.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

SelectionFragment _fragmentForNode(
  CmarkNode node, {
  required Rect rect,
  SelectionRange? range,
  MarkdownSourceAttachment? attachment,
  String? plainTextOverride,
}) {
  final model = MarkdownSelectionModel(node);
  final plain = plainTextOverride ?? model.plainText;
  return SelectionFragment(
    rect: rect,
    plainText: plain,
    contentLength: plain.length,
    attachment: attachment ??
        MarkdownSourceAttachment(
          fullSource: plain,
          blockNode: node,
        ),
    range: range ?? SelectionRange(0, plain.length),
  );
}

CmarkNode _paragraphNode(String text) {
  final paragraph = CmarkNode(CmarkNodeType.paragraph);
  final textNode = CmarkNode(CmarkNodeType.text)..content.write(text);
  paragraph.appendChild(textNode);
  return paragraph;
}

void main() {
  setUp(TableLeafRegistry.instance.clear);
  test('fully selected list item emits marker', () {
    final controller = ParserController();
    final snapshot = controller.parse('- First item');
    final listNode = snapshot.blocks.first;
    final paragraphNode = listNode.firstChild!.firstChild!;

    final fragment = _fragmentForNode(
      paragraphNode,
      rect: const Rect.fromLTWH(0, 0, 10, 10),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    expect(result.trim(), '- First item');
  });

  test('partial list selection does not emit marker', () {
    final controller = ParserController();
    final snapshot = controller.parse('- First item');
    final paragraphNode = snapshot.blocks.first.firstChild!.firstChild!;
    final model = MarkdownSelectionModel(paragraphNode);
    final plain = model.plainText;

    final fragment = SelectionFragment(
      rect: const Rect.fromLTWH(0, 0, 10, 10),
      plainText: plain,
      contentLength: plain.length,
      attachment: MarkdownSourceAttachment(
        fullSource: plain,
        blockNode: paragraphNode,
      ),
      range: SelectionRange(2, plain.length),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    expect(result, plain.substring(2));
  });

  test('multiple table cells serialize with pipes', () {
    final controller = ParserController();
    final snapshot = controller.parse('''
| A | B |
| --- | --- |
| X | Y |
''');
    final tableNode = snapshot.blocks.first;
    final bodyRow = tableNode.firstChild!.next!; // second row (first body row)
    final firstCell = bodyRow.firstChild!;
    final secondCell = firstCell.next!;

    final fragmentA = _fragmentForNode(
      firstCell,
      rect: const Rect.fromLTWH(0, 0, 10, 10),
    );
    final modelB = MarkdownSelectionModel(secondCell);
    final fragmentB = SelectionFragment(
      rect: const Rect.fromLTWH(50, 0, 10, 10),
      plainText: modelB.plainText,
      contentLength: modelB.plainText.length,
      attachment: MarkdownSourceAttachment(
        fullSource: modelB.plainText,
        blockNode: secondCell,
      ),
      range: null,
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragmentA, fragmentB]);
    expect(result.trim(), '| X | Y |');
  });

  test('single table cell selection stays plain text', () {
    final controller = ParserController();
    final snapshot = controller.parse('''
| A | B |
| --- | --- |
| X | Y |
''');
    final tableNode = snapshot.blocks.first;
    final bodyRow = tableNode.firstChild!.next!;
    final firstCell = bodyRow.firstChild!;

    final fragment = _fragmentForNode(
      firstCell,
      rect: const Rect.fromLTWH(0, 0, 10, 10),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    expect(result.trim(), 'X');
  });

  test('duplicate full fragments are skipped', () {
    final controller = ParserController();
    final snapshot = controller.parse('Plain paragraph');
    final paragraphNode = snapshot.blocks.first;
    final plain = MarkdownSelectionModel(paragraphNode).plainText;

    final attachment = MarkdownSourceAttachment(
      fullSource: plain,
      blockNode: paragraphNode,
    );

    SelectionFragment makeFragment() => SelectionFragment(
          rect: const Rect.fromLTWH(0, 0, 10, 10),
          plainText: plain,
          contentLength: plain.length,
          attachment: attachment,
          range: SelectionRange(0, plain.length),
        );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([makeFragment(), makeFragment()]);
    expect(result, plain);
  });

  test('vertical spacing inserts newline between fragments', () {
    final controller = ParserController();
    final snapshot = controller.parse('Line one\n\nLine two');
    final first = snapshot.blocks.first;
    final second = first.next!;

    final fragA = _fragmentForNode(
      first,
      rect: const Rect.fromLTWH(0, 0, 10, 10),
    );
    final fragB = _fragmentForNode(
      second,
      rect: const Rect.fromLTWH(0, 20, 10, 10),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragA, fragB]);
    expect(result, contains('\n'));
  });

  test('ordered lists retain numbering', () {
    final controller = ParserController();
    final snapshot = controller.parse('1. First\n2. Second');
    final firstParagraph = snapshot.blocks.first.firstChild!.firstChild!;
    final fragment = _fragmentForNode(
      firstParagraph,
      rect: const Rect.fromLTWH(0, 0, 10, 10),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    expect(result.trim(), '1. First');
  });

  test('ordered lists keep numbering for later items', () {
    final controller = ParserController();
    final snapshot = controller.parse('1. First\n2. Second');
    final secondParagraph = snapshot.blocks.first.firstChild!.next!.firstChild!;
    final fragment = _fragmentForNode(
      secondParagraph,
      rect: const Rect.fromLTWH(0, 0, 10, 10),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    expect(result.trim(), '2. Second');
  });

  test('loose list items indent subsequent blocks', () {
    final controller = ParserController();
    final snapshot = controller.parse('- First paragraph\n\n  Second');
    final list = snapshot.blocks.first;
    final item = list.firstChild!;
    final firstParagraph = item.firstChild!;
    final secondParagraph = firstParagraph.next!;

    final fragA = _fragmentForNode(
      firstParagraph,
      rect: const Rect.fromLTWH(0, 0, 10, 10),
    );
    final fragB = _fragmentForNode(
      secondParagraph,
      rect: const Rect.fromLTWH(0, 12, 10, 10),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragA, fragB]);
    expect(result, contains('\n  Second'));
  });

  test('nested list selection preserves hierarchy', () {
    final controller = ParserController();
    final snapshot = controller.parse('- Parent\n  - Child A\n  - Child B');
    final list = snapshot.blocks.first;
    final parentItem = list.firstChild!;
    final parentParagraph = parentItem.firstChild!; // paragraph "Parent"
    final nestedList = parentParagraph.next!;

    final parentFragment = _fragmentForNode(
      parentParagraph,
      rect: const Rect.fromLTWH(0, 0, 10, 10),
    );
    final childAParagraph = nestedList.firstChild!.firstChild!;
    final childAFragment = _fragmentForNode(
      childAParagraph,
      rect: const Rect.fromLTWH(0, 12, 10, 10),
    );
    final childBParagraph = nestedList.firstChild!.next!.firstChild!;
    final childBFragment = _fragmentForNode(
      childBParagraph,
      rect: const Rect.fromLTWH(0, 24, 10, 10),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize(
      [parentFragment, childAFragment, childBFragment],
    );

    expect(
      result.trim(),
      '- Parent\n  - Child A\n  - Child B',
    );
  });

  test('nested list without parent text still emits bullet', () {
    final controller = ParserController();
    final snapshot = controller.parse('-\n  - Child');
    final list = snapshot.blocks.first;
    final parentItem = list.firstChild!;
    final nestedList = parentItem.firstChild!; // list node
    final childParagraph = nestedList.firstChild!.firstChild!;

    final parentFragment = _fragmentForNode(
      nestedList,
      rect: const Rect.fromLTWH(0, 0, 10, 10),
      plainTextOverride: '',
      range: const SelectionRange(0, 0),
    );
    final childFragment = _fragmentForNode(
      childParagraph,
      rect: const Rect.fromLTWH(0, 12, 10, 10),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([parentFragment, childFragment]);

    expect(result.trim(), '-\n  - Child');
  });

  test('table selections spanning rows emit pipe rows with newline', () {
    const markdown = '''
| A | B | C |
| --- | --- | --- |
| X | Y | Z |
''';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final table = snapshot.blocks.first;
    final headerRow = table.firstChild!; // header row
    final bodyRow = headerRow.next!; // first body row

    SelectionFragment cellFragment(CmarkNode cell, Rect rect) =>
        _fragmentForNode(cell, rect: rect);

    final headerFragments = <SelectionFragment>[];
    var cell = headerRow.firstChild;
    var column = 0;
    while (cell != null) {
      if (cell.type == CmarkNodeType.tableCell) {
        headerFragments.add(cellFragment(cell, Rect.fromLTWH(column * 40.0, 0, 30, 10)));
        column += 1;
      }
      cell = cell.next;
    }

    final bodyFragments = <SelectionFragment>[];
    cell = bodyRow.firstChild;
    column = 0;
    while (cell != null) {
      if (cell.type == CmarkNodeType.tableCell) {
        bodyFragments.add(cellFragment(cell, Rect.fromLTWH(column * 40.0, 20, 30, 10)));
        column += 1;
      }
      cell = cell.next;
    }

    final serializer = SelectionSerializer();
    final result = serializer.serialize([...headerFragments, ...bodyFragments]);

    expect(
      result.trim(),
      '| A | B | C |\n| X | Y | Z |',
    );
  });

  test('ordered nested list covers numbering and indentation cases', () {
    final outerList = CmarkNode(CmarkNodeType.list)
      ..listData.listType = CmarkListType.bullet;
    final parentItem = CmarkNode(CmarkNodeType.item);
    outerList.appendChild(parentItem);

    final parentParagraph = _paragraphNode('Parent bullet');
    parentItem.appendChild(parentParagraph);

    final nestedList = CmarkNode(CmarkNodeType.list)
      ..listData.listType = CmarkListType.ordered
      ..listData.start = 3;
    parentItem.appendChild(nestedList);

    final childA = CmarkNode(CmarkNodeType.item);
    nestedList.appendChild(childA);
    final childAParagraph = _paragraphNode('Child A');
    childA.appendChild(childAParagraph);

    final childB = CmarkNode(CmarkNodeType.item);
    nestedList.appendChild(childB);
    final childBParagraphOne = _paragraphNode('Child B first');
    final childBParagraphTwo = _paragraphNode('Child B second');
    childB
      ..appendChild(childBParagraphOne)
      ..appendChild(childBParagraphTwo);

    final grandList = CmarkNode(CmarkNodeType.list)
      ..listData.listType = CmarkListType.bullet;
    final grandItem = CmarkNode(CmarkNodeType.item);
    grandList.appendChild(grandItem);
    final grandParagraph = _paragraphNode('Grand child');
    grandItem.appendChild(grandParagraph);
    childB.appendChild(grandList);

    final childC = CmarkNode(CmarkNodeType.item);
    nestedList.appendChild(childC); // Empty item exercises guard path.

    final fragments = <SelectionFragment>[
      _fragmentForNode(
        parentParagraph,
        rect: const Rect.fromLTWH(0, 0, 10, 10),
      ),
      _fragmentForNode(
        childAParagraph,
        rect: const Rect.fromLTWH(0, 12, 10, 10),
      ),
      _fragmentForNode(
        childBParagraphOne,
        rect: const Rect.fromLTWH(0, 24, 10, 10),
      ),
      _fragmentForNode(
        childBParagraphTwo,
        rect: const Rect.fromLTWH(0, 36, 10, 10),
      ),
      _fragmentForNode(
        grandParagraph,
        rect: const Rect.fromLTWH(0, 48, 10, 10),
      ),
    ];

    final serializer = SelectionSerializer();
    final result = serializer.serialize(fragments);

    expect(
      result.trim(),
      '- Parent bullet\n  3. Child A\n  4. Child B first\n    Child B second\n    - Grand child',
    );
  });

  test('plain fragments without attachments fall back to text', () {
    final fragment = SelectionFragment(
      rect: const Rect.fromLTWH(0, 0, 10, 10),
      plainText: 'Loose',
      contentLength: 5,
    );
    final serializer = SelectionSerializer();
    expect(serializer.serialize([fragment]), 'Loose');
  });

  test('full-range fragments without models use full source', () {
    final attachment = MarkdownSourceAttachment(fullSource: '**bold**');
    final fragment = SelectionFragment(
      rect: const Rect.fromLTWH(0, 0, 10, 10),
      plainText: 'bold',
      contentLength: 4,
      attachment: attachment,
      range: const SelectionRange(0, 4),
    );

    final serializer = SelectionSerializer();
    expect(serializer.serialize([fragment]), '**bold**');
  });

  test('partial fragments without models fall back to text', () {
    final attachment = MarkdownSourceAttachment(fullSource: '**bold**');
    final fragment = SelectionFragment(
      rect: const Rect.fromLTWH(0, 0, 10, 10),
      plainText: 'bold',
      contentLength: 4,
      attachment: attachment,
      range: const SelectionRange(0, 2),
    );

    final serializer = SelectionSerializer();
    expect(serializer.serialize([fragment]), 'bold');
  });

  test('table registry converts aggregated text to markdown', () {
    const markdown = '''
| A | B |
| --- | --- |
| X | Y |
''';

    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final table = snapshot.blocks.first;

    TableLeafRegistry.instance.clear();
    TableLeafRegistry.instance.beginTable(table);

    var row = table.firstChild;
    while (row != null) {
      if (row.type == CmarkNodeType.tableRow) {
        TableLeafRegistry.instance.beginRow(row);
        var cell = row.firstChild;
        while (cell != null) {
          if (cell.type == CmarkNodeType.tableCell) {
            final model = MarkdownSelectionModel(cell);
            TableLeafRegistry.instance.addCell(cell, model.plainText);
          }
          cell = cell.next;
        }
        TableLeafRegistry.instance.endRow();
      }
      row = row.next;
    }
    TableLeafRegistry.instance.endTable();

    final group = TableLeafRegistry.instance.groups.first;
    final aggregated = group.concatenatedText;

    final markdownOutput = TableLeafRegistry.instance.toMarkdown(aggregated);
    expect(markdownOutput?.trim(), '| A | B |\n| X | Y |');
  });

  test('non-matching aggregated text stays unchanged', () {
    TableLeafRegistry.instance.clear();
    expect(TableLeafRegistry.instance.toMarkdown('Not a table'), isNull);
  });
}
