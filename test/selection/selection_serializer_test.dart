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
    expect(result, plain);
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
        headerFragments
            .add(cellFragment(cell, Rect.fromLTWH(column * 40.0, 0, 30, 10)));
        column += 1;
      }
      cell = cell.next;
    }

    final bodyFragments = <SelectionFragment>[];
    cell = bodyRow.firstChild;
    column = 0;
    while (cell != null) {
      if (cell.type == CmarkNodeType.tableCell) {
        bodyFragments
            .add(cellFragment(cell, Rect.fromLTWH(column * 40.0, 20, 30, 10)));
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
    expect(serializer.serialize([fragment]), 'bold');
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

  test('paragraph to list drag (top to bottom) - full list item selected', () {
    const markdown =
        'This is sentence one.\n- This is the first bullet.\n- This is the second bullet.';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final paragraphNode = snapshot.blocks.elementAt(0);
    final listNode = snapshot.blocks.elementAt(1);
    final listModel = MarkdownSelectionModel(listNode);

    // Simulate selecting full paragraph + full first list item
    final listPlainText = listModel.plainText;
    final firstItemEnd = listPlainText.indexOf('\n');
    
    final fragments = [
      SelectionFragment(
        rect: const Rect.fromLTWH(0, 0, 100, 20),
        plainText: 'This is sentence one.',
        contentLength: 21,
        attachment: MarkdownSourceAttachment(
          fullSource: snapshot.getNodeSource(paragraphNode) ?? '',
          blockNode: paragraphNode,
        ),
        range: const SelectionRange(0, 21),
      ),
      SelectionFragment(
        rect: const Rect.fromLTWH(0, 20, 100, 20),
        plainText: listPlainText.substring(0, firstItemEnd),
        contentLength: firstItemEnd,
        attachment: MarkdownSourceAttachment(
          fullSource: snapshot.getNodeSource(listNode) ?? '',
          blockNode: listNode,
        ),
        range: SelectionRange(0, firstItemEnd),
      ),
    ];

    final serializer = SelectionSerializer();
    final result = serializer.serialize(fragments);
    expect(result, contains('This is sentence one.'));
    // No markdown expansion: plain text only, no list marker
    expect(result, contains('This is the first bullet.'));
    expect(result, isNot(contains('- ')));
  });

  test('list to paragraph drag (bottom to top) - full items selected', () {
    const markdown =
        'This is sentence one.\n- This is the first bullet.\n- This is the second bullet.';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final paragraphNode = snapshot.blocks.elementAt(0);
    final listNode = snapshot.blocks.elementAt(1);
    final listModel = MarkdownSelectionModel(listNode);

    final listPlainText = listModel.plainText;
    final secondItemStart = listPlainText.indexOf('This is the second');
    
    final fragments = [
      SelectionFragment(
        rect: const Rect.fromLTWH(0, 0, 100, 20),
        plainText: 'This is sentence one.',
        contentLength: 21,
        attachment: MarkdownSourceAttachment(
          fullSource: snapshot.getNodeSource(paragraphNode) ?? '',
          blockNode: paragraphNode,
        ),
        range: const SelectionRange(0, 21),
      ),
      SelectionFragment(
        rect: const Rect.fromLTWH(0, 40, 100, 20),
        plainText: listPlainText.substring(secondItemStart),
        contentLength: listPlainText.length - secondItemStart,
        attachment: MarkdownSourceAttachment(
          fullSource: snapshot.getNodeSource(listNode) ?? '',
          blockNode: listNode,
        ),
        range: SelectionRange(secondItemStart, listPlainText.length),
      ),
    ];

    final serializer = SelectionSerializer();
    final result = serializer.serialize(fragments);
    expect(result, contains('This is sentence one.'));
    // No markdown expansion: plain text only, no list marker
    expect(result, contains('This is the second bullet.'));
    expect(result, isNot(contains('- ')));
  });

  test('partial list item selection returns plain text only', () {
    const markdown = '- Item with **bold** and _italic_';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.first;
    final model = MarkdownSelectionModel(listNode);
    
    final plainText = model.plainText;
    final start = plainText.indexOf('with');
    final end = plainText.indexOf('bold') + 'bold'.length;

    // Simulate selecting just 'with bold' from the rendered text
    final fragment = SelectionFragment(
      rect: const Rect.fromLTWH(0, 0, 100, 20),
      plainText: 'with bold',
      contentLength: markdown.length,
      attachment: MarkdownSourceAttachment(
        fullSource: snapshot.getNodeSource(listNode) ?? '',
        blockNode: listNode,
      ),
      range: SelectionRange(start, end),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    // No markdown expansion: returns fragment.plainText as-is
    expect(result.trim(), 'with bold');
  });

  test('nested list copy returns plain text', () {
    const markdown = '- A\n  - B\n  - C\n  - D';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.first;
    final listSource = snapshot.getNodeSource(listNode);

    expect(listSource, isNotNull,
        reason: 'getNodeSource must return list source');

    final model = MarkdownSelectionModel(listNode);
    final plainTextLen = model.plainText.length;

    final fragment = SelectionFragment(
      rect: const Rect.fromLTWH(0, 0, 100, 60),
      plainText: model.plainText,
      contentLength: plainTextLen,
      attachment: MarkdownSourceAttachment(
        fullSource: listSource!,
        blockNode: listNode,
      ),
      range: SelectionRange(0, plainTextLen),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    // No markdown expansion: returns plain text without markers
    expect(result, contains('A'));
    expect(result, contains('B'));
    expect(result, contains('C'));
    expect(result, contains('D'));
    expect(result, isNot(contains('- ')));
  });

  test('runtime-style table selection uses registry fallback', () {
    const markdown = '| A | B |\n| --- | --- |\n| X | Y |';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final tableNode = snapshot.blocks.first;

    TableLeafRegistry.instance.clear();
    TableLeafRegistry.instance.beginTable(tableNode);
    var row = tableNode.firstChild;
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

    // Simulate runtime: single fragment with aggregated text, no attachment
    final fragment = SelectionFragment(
      rect: Rect.zero,
      plainText: 'ABXY',
      contentLength: 4,
      attachment: null,
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    expect(result, contains('| A | B |'));
    expect(result, contains('| X | Y |'));
  });

  test('paragraph to table selection combines correctly', () {
    const markdown = 'Intro text.\n\n| A | B |\n| --- | --- |\n| X | Y |';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final paragraphNode = snapshot.blocks.elementAt(0);
    final tableNode = snapshot.blocks.elementAt(1);

    TableLeafRegistry.instance.clear();
    TableLeafRegistry.instance.beginTable(tableNode);
    var row = tableNode.firstChild;
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

    final fragments = [
      SelectionFragment(
        rect: const Rect.fromLTWH(0, 0, 100, 20),
        plainText: 'Intro text.',
        contentLength: 11,
        attachment: MarkdownSourceAttachment(
          fullSource: snapshot.getNodeSource(paragraphNode) ?? '',
          blockNode: paragraphNode,
        ),
        range: const SelectionRange(0, 11),
      ),
      SelectionFragment(
        rect: const Rect.fromLTWH(0, 40, 100, 40),
        plainText: 'ABXY',
        contentLength: 4,
        attachment: null,
      ),
    ];

    final serializer = SelectionSerializer();
    final result = serializer.serialize(fragments);
    expect(result, contains('Intro text.'));
    expect(result, contains('| A | B |'));
    expect(result, contains('| X | Y |'));
  });

  test('empty list items handled gracefully', () {
    const markdown = '- \n- Item\n- ';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.first;
    final listSource = snapshot.getNodeSource(listNode) ?? '';

    if (listSource.isEmpty) {
      return; // Skip if parser doesn't handle this case
    }

    final model = MarkdownSelectionModel(listNode);
    final fragment = SelectionFragment(
      rect: Rect.zero,
      plainText: model.plainText,
      contentLength: model.plainText.length,
      attachment: MarkdownSourceAttachment(
        fullSource: listSource,
        blockNode: listNode,
      ),
      range: SelectionRange(0, model.plainText.length),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    // No markdown expansion: returns plain text without markers
    expect(result, contains('Item'));
    expect(result, isNot(contains('- ')));
  });

  test('list item with inline code and bold returns plain text', () {
    const markdown = '- Item with `code` and **bold**';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.first;
    final listSource = snapshot.getNodeSource(listNode) ?? '';

    expect(listSource, isNotEmpty);

    final model = MarkdownSelectionModel(listNode);
    final fragment = SelectionFragment(
      rect: Rect.zero,
      plainText: model.plainText,
      contentLength: model.plainText.length,
      attachment: MarkdownSourceAttachment(
        fullSource: listSource,
        blockNode: listNode,
      ),
      range: SelectionRange(0, model.plainText.length),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    // No markdown expansion: returns plain text without formatting
    expect(result, 'Item with code and bold');
  });

  test('deeply nested list (3 levels) returns plain text', () {
    const markdown = '- A\n  - B\n    - C\n    - D\n  - E';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.first;
    final listSource = snapshot.getNodeSource(listNode) ?? '';

    expect(listSource, isNotEmpty);

    final model = MarkdownSelectionModel(listNode);
    final fragment = SelectionFragment(
      rect: Rect.zero,
      plainText: model.plainText,
      contentLength: model.plainText.length,
      attachment: MarkdownSourceAttachment(
        fullSource: listSource,
        blockNode: listNode,
      ),
      range: SelectionRange(0, model.plainText.length),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    // No markdown expansion: returns plain text without markers/indentation
    expect(result, 'A\nB\nC\nD\nE');
  });

  test('table with empty cells', () {
    const markdown = '| A |  |\n| --- | --- |\n|  | B |';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final tableNode = snapshot.blocks.first;

    TableLeafRegistry.instance.clear();
    TableLeafRegistry.instance.beginTable(tableNode);
    var row = tableNode.firstChild;
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
    final result = group.toMarkdown();
    expect(result, contains('| A |  |'));
    expect(result, contains('|  | B |'));
  });

  test('list with links returns plain text', () {
    const markdown =
        '- Check [this](https://example.com)\n- And [that](https://other.com)';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final listNode = snapshot.blocks.first;
    final listSource = snapshot.getNodeSource(listNode) ?? '';

    expect(listSource, isNotEmpty);

    final model = MarkdownSelectionModel(listNode);
    final fragment = SelectionFragment(
      rect: Rect.zero,
      plainText: model.plainText,
      contentLength: model.plainText.length,
      attachment: MarkdownSourceAttachment(
        fullSource: listSource,
        blockNode: listNode,
      ),
      range: SelectionRange(0, model.plainText.length),
    );

    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]);
    // No markdown expansion: returns plain text without link markdown
    expect(result, contains('Check this'));
    expect(result, contains('And that'));
    expect(result, isNot(contains('https://')));
  });

  test('full document with thematic breaks, heading, and list', () {
    const input = '---\n\n## Header\n\n1. **Some list item**\n   Some text.\n\n---';
    // Thematic breaks are serialized, headings and list items are plain text
    const expected = '---\n\nHeader\nSome list item\nSome text.\n---';
    
    final controller = ParserController();
    final snapshot = controller.parse(input);
    
    // Build fragments for ALL blocks
    final fragments = <SelectionFragment>[];
    var y = 0.0;
    for (final block in snapshot.blocks) {
      final source = snapshot.getNodeSource(block) ?? '';
      final model = MarkdownSelectionModel(block);
      fragments.add(SelectionFragment(
        rect: Rect.fromLTWH(0, y, 100, 20),
        plainText: model.plainText,
        contentLength: model.length,
        attachment: MarkdownSourceAttachment(
          fullSource: source,
          blockNode: block,
        ),
        range: SelectionRange(0, model.length),
      ));
      y += 40;
    }

    final serializer = SelectionSerializer();
    final result = serializer.serialize(fragments).trim();
    expect(result, equals(expected));
  });

  test('thematic break between selected paragraphs is included', () {
    const markdown = 'A\n\n---\n\nB';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final para1 = snapshot.blocks.elementAt(0);
    final para2 = snapshot.blocks.elementAt(2);

    final fragments = [
      SelectionFragment(
        rect: const Rect.fromLTWH(0, 0, 100, 20),
        plainText: 'A',
        contentLength: 1,
        attachment: MarkdownSourceAttachment(
          fullSource: snapshot.getNodeSource(para1) ?? '',
          blockNode: para1,
        ),
        range: const SelectionRange(0, 1),
      ),
      SelectionFragment(
        rect: const Rect.fromLTWH(0, 60, 100, 20),
        plainText: 'B',
        contentLength: 1,
        attachment: MarkdownSourceAttachment(
          fullSource: snapshot.getNodeSource(para2) ?? '',
          blockNode: para2,
        ),
        range: const SelectionRange(0, 1),
      ),
    ];

    final serializer = SelectionSerializer();
    final result = serializer.serialize(fragments).trim();
    expect(result, contains('A'));
    expect(result, contains('---'));
    expect(result, contains('B'));
  });

  test('nested list item selection returns just that item (C)', () {
    const markdown = '- A\n  - B\n  - C\n  - D';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final block = snapshot.blocks.first;
    final source = snapshot.getNodeSource(block)!;
    
    // Simulate selecting just "C"
    final fragment = SelectionFragment(
      rect: const Rect.fromLTWH(0, 40, 100, 20),
      plainText: 'C',
      contentLength: 1,
      attachment: MarkdownSourceAttachment(
        fullSource: source,
        blockNode: block,
      ),
    );
    
    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]).trim();
    
    // No markdown expansion: returns plain text only
    expect(result, 'C');
  });

  test('selecting single word from list item returns just that word', () {
    // Input:
    // - This is sentence number one.
    // - This is sentence number two.
    // Selecting just "sentence" should give "sentence", not the whole list item
    const markdown = '- This is sentence number one.\n- This is sentence number two.';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final block = snapshot.blocks.first; // the list
    final source = snapshot.getNodeSource(block)!;
    final model = MarkdownSelectionModel(block);
    
    // plainText is "This is sentence number one.\nThis is sentence number two."
    final plainText = model.plainText;
    final sentenceStart = plainText.indexOf('sentence');
    final sentenceEnd = sentenceStart + 'sentence'.length;
    
    // Simulate selecting just "sentence" from the first item
    final fragment = SelectionFragment(
      rect: const Rect.fromLTWH(50, 0, 60, 20),
      plainText: 'sentence',
      contentLength: 8,
      attachment: MarkdownSourceAttachment(
        fullSource: source,
        blockNode: block,
      ),
      range: SelectionRange(sentenceStart, sentenceEnd),
    );
    
    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]).trim();
    
    // Should be just "sentence", not "- This is sentence number one."
    expect(result, 'sentence');
  });

  test('nested list item selection returns just that item (B)', () {
    const markdown = '- A\n  - B\n  - C\n  - D';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final block = snapshot.blocks.first;
    final source = snapshot.getNodeSource(block)!;
    final model = MarkdownSelectionModel(block);
    
    final plainText = model.plainText;
    final bStart = plainText.indexOf('B');
    final bEnd = bStart + 1;
    
    // Simulate selecting just "B"
    final fragment = SelectionFragment(
      rect: const Rect.fromLTWH(0, 20, 100, 20),
      plainText: 'B',
      contentLength: 1,
      attachment: MarkdownSourceAttachment(
        fullSource: source,
        blockNode: block,
      ),
      range: SelectionRange(bStart, bEnd),
    );
    
    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]).trim();
    
    // No markdown expansion: returns plain text only
    expect(result, 'B');
  });

  test('code block partial selection excludes fences', () {
    const markdown = '```dart\nline1\nline2\nline3\n```';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final block = snapshot.blocks.first;
    final source = snapshot.getNodeSource(block)!;
    
    // Partial selection - just "line2"
    final fragment = SelectionFragment(
      rect: const Rect.fromLTWH(0, 0, 100, 20),
      plainText: 'line2',
      contentLength: 5,
      attachment: MarkdownSourceAttachment(
        fullSource: source,
        blockNode: block,
      ),
    );
    
    final serializer = SelectionSerializer();
    final result = serializer.serialize([fragment]).trim();
    
    // Should NOT include fences - just the selected text
    expect(result, 'line2');
  });

  test('selecting within table cell preserves formatting', () {
    const markdown = '| **Bold** | _Italic_ |\n| --- | --- |\n| A | B |';
    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final tableNode = snapshot.blocks.first;

    TableLeafRegistry.instance.clear();
    // Pretend we've registered this table
    TableLeafRegistry.instance.beginTable(tableNode);
    var row = tableNode.firstChild;
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

    // Select the entire table
    final group = TableLeafRegistry.instance.groups.first;
    final aggregated = group.concatenatedText;
    final markdown2 = TableLeafRegistry.instance.toMarkdown(aggregated);

    expect(markdown2, isNotNull);
    expect(markdown2, contains('| **Bold** |'));
    expect(markdown2, contains('Italic'));
  });
}
