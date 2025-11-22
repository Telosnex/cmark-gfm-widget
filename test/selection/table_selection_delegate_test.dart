import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:cmark_gfm_widget/src/parser/parser_controller.dart';
import 'package:cmark_gfm_widget/src/widgets/table_selection_delegate.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('table delegate returns pipe markdown for multi-cell selection', () {
    const markdown = '''
| A | B | C |
| --- | --- | --- |
| X | Y | Z |
''';

    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final table = snapshot.blocks.first;

    // Collect cell nodes in row-major order.
    final cellNodes = <CmarkNode>[];
    var row = table.firstChild;
    while (row != null) {
      if (row.type == CmarkNodeType.tableRow) {
        var cell = row.firstChild;
        while (cell != null) {
          if (cell.type == CmarkNodeType.tableCell) {
            cellNodes.add(cell);
          }
          cell = cell.next;
        }
      }
      row = row.next;
    }

    expect(cellNodes.length, 6); // 2 rows * 3 columns

    final delegate = TableSelectionContainerDelegate(
      tableNode: table,
      cellNodes: cellNodes,
      columnCount: 3,
    );

    // Create mock selectables that report selected content.
    final selectables = <_MockSelectable>[];
    for (var i = 0; i < cellNodes.length; i++) {
      final node = cellNodes[i];
      final text = _collectText(node);
      selectables.add(_MockSelectable(text: text, selected: true));
    }

    // Inject the selectables into the delegate.
    delegate.setSelectables(selectables);

    final content = delegate.getSelectedContent();
    expect(content, isNotNull);
    expect(
      content!.plainText.trim(),
      '| A | B | C |\n| X | Y | Z |',
    );
  });

  test('table delegate returns plain text for single cell', () {
    const markdown = '''
| A | B |
| --- | --- |
| X | Y |
''';

    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final table = snapshot.blocks.first;

    final cellNodes = <CmarkNode>[];
    var row = table.firstChild;
    while (row != null) {
      if (row.type == CmarkNodeType.tableRow) {
        var cell = row.firstChild;
        while (cell != null) {
          if (cell.type == CmarkNodeType.tableCell) {
            cellNodes.add(cell);
          }
          cell = cell.next;
        }
      }
      row = row.next;
    }

    final delegate = TableSelectionContainerDelegate(
      tableNode: table,
      cellNodes: cellNodes,
      columnCount: 2,
    );

    // Only the first cell (A) is selected.
    final selectables = <_MockSelectable>[];
    for (var i = 0; i < cellNodes.length; i++) {
      final node = cellNodes[i];
      final text = _collectText(node);
      selectables.add(_MockSelectable(text: text, selected: i == 0));
    }

    delegate.setSelectables(selectables);

    final content = delegate.getSelectedContent();
    expect(content, isNotNull);
    expect(content!.plainText.trim(), 'A');
  });

  test('table delegate handles cells with null selection range', () {
    const markdown = '''
| A | B |
| --- | --- |
| C | D |
''';

    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final table = snapshot.blocks.first;

    final cellNodes = <CmarkNode>[];
    var row = table.firstChild;
    while (row != null) {
      if (row.type == CmarkNodeType.tableRow) {
        var cell = row.firstChild;
        while (cell != null) {
          if (cell.type == CmarkNodeType.tableCell) {
            cellNodes.add(cell);
          }
          cell = cell.next;
        }
      }
      row = row.next;
    }

    final delegate = TableSelectionContainerDelegate(
      tableNode: table,
      cellNodes: cellNodes,
      columnCount: 2,
    );

    // Build selectables for all cells, select first header cell,
    // but give second header cell a null range.
    final selectables = <_MockSelectable>[];
    for (var i = 0; i < cellNodes.length; i++) {
      final text = _collectText(cellNodes[i]);
      if (i == 0) {
        selectables.add(_MockSelectable(text: text, selected: true));
      } else if (i == 1) {
        selectables
            .add(_MockSelectable(text: text, selected: true, nullRange: true));
      } else {
        selectables.add(_MockSelectable(text: text, selected: false));
      }
    }

    delegate.setSelectables(selectables);

    final content = delegate.getSelectedContent();
    expect(content, isNotNull);
    expect(content!.plainText.trim(), 'A');
  });

  test('single-cell selections in different rows each get newline', () {
    const markdown = '''
| A |
| --- |
| B |
| C |
''';

    final controller = ParserController();
    final snapshot = controller.parse(markdown);
    final table = snapshot.blocks.first;

    final cellNodes = <CmarkNode>[];
    var row = table.firstChild;
    while (row != null) {
      if (row.type == CmarkNodeType.tableRow) {
        var cell = row.firstChild;
        while (cell != null) {
          if (cell.type == CmarkNodeType.tableCell) {
            cellNodes.add(cell);
          }
          cell = cell.next;
        }
      }
      row = row.next;
    }

    final delegate = TableSelectionContainerDelegate(
      tableNode: table,
      cellNodes: cellNodes,
      columnCount: 1,
    );

    final selectables = <_MockSelectable>[
      _MockSelectable(text: 'A', selected: true),
      _MockSelectable(text: 'B', selected: true),
      _MockSelectable(text: 'C', selected: true),
    ];

    delegate.setSelectables(selectables);

    final content = delegate.getSelectedContent();
    expect(content, isNotNull);
    expect(content!.plainText, 'A\nB\nC');
  });
}

String _collectText(CmarkNode node) {
  final buffer = StringBuffer();
  var child = node.firstChild;
  while (child != null) {
    if (child.type == CmarkNodeType.text) {
      buffer.write(child.content.toString());
    } else {
      buffer.write(_collectText(child));
    }
    child = child.next;
  }
  return buffer.toString();
}

class _MockSelectable extends Fake implements Selectable {
  _MockSelectable({
    required this.text,
    this.selected = false,
    this.nullRange = false,
  });

  final String text;
  final bool selected;
  final bool nullRange;

  @override
  SelectedContent? getSelectedContent() {
    if (!selected) {
      return null;
    }
    return SelectedContent(plainText: text);
  }

  @override
  SelectedContentRange? getSelection() {
    if (!selected || nullRange) {
      return null;
    }
    return SelectedContentRange(startOffset: 0, endOffset: text.length);
  }

  @override
  int get contentLength => text.length;
}

/// Extension to inject selectables for testing (since we can't access the
/// protected field directly).
extension TableSelectionContainerDelegateTestExt
    on TableSelectionContainerDelegate {
  void setSelectables(List<Selectable> s) {
    selectables
      ..clear()
      ..addAll(s);
  }
}
