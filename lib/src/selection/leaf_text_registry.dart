import 'package:cmark_gfm/cmark_gfm.dart';

import '../flutter/debug_log.dart';
import 'markdown_selection_model.dart';

class TableLeafEntry {
  TableLeafEntry({
    required this.cellNode,
    required this.plainText,
  });

  final CmarkNode cellNode;
  final String plainText;
}

class TableRowEntry {
  TableRowEntry({required this.rowNode});

  final CmarkNode rowNode;
  final List<TableLeafEntry> cells = [];

  bool get isHeader => rowNode.tableRowData.isHeader;
  String get concatenatedText => cells.map((e) => e.plainText).join();
}

class TableLeafGroup {
  TableLeafGroup({required this.tableNode});

  final CmarkNode tableNode;
  final List<TableRowEntry> rows = [];
  TableRowEntry? _currentRow;

  void beginRow(CmarkNode rowNode) {
    _currentRow = TableRowEntry(rowNode: rowNode);
  }

  void addCell(CmarkNode cellNode, String plainText) {
    final current = _currentRow;
    if (current == null) return;
    current.cells.add(TableLeafEntry(cellNode: cellNode, plainText: plainText));
  }

  void endRow() {
    final current = _currentRow;
    if (current != null) {
      rows.add(current);
    }
    _currentRow = null;
  }

  String get concatenatedText =>
      rows.map((row) => row.concatenatedText).join();

  String toMarkdown() {
    final buffer = StringBuffer();
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final cells = <String>[];
      for (final cell in row.cells) {
        final model = MarkdownSelectionModel(cell.cellNode);
        final markdown = model.toMarkdown(0, model.length);
        cells.add(markdown.isEmpty ? cell.plainText : markdown);
      }
      buffer.write('| ${cells.join(' | ')} |');
      if (i != rows.length - 1) {
        buffer.writeln();
      }
    }
    return buffer.toString();
  }
}

class TableLeafRegistry {
  TableLeafRegistry._();

  static final TableLeafRegistry instance = TableLeafRegistry._();

  final List<TableLeafGroup> _groups = [];
  TableLeafGroup? _current;

  void clear() {
    _groups.clear();
    _current = null;
    debugLog(() => 'TableLeafRegistry: cleared');
  }

  void beginTable(CmarkNode tableNode) {
    _current = TableLeafGroup(tableNode: tableNode);
    debugLog(() => 'TableLeafRegistry: begin table ${tableNode.hashCode}');
  }

  void beginRow(CmarkNode rowNode) {
    final current = _current;
    if (current == null) return;
    current.beginRow(rowNode);
    debugLog(() => 'TableLeafRegistry: begin row ${rowNode.hashCode}');
  }

  void addCell(CmarkNode cellNode, String plainText) {
    final current = _current;
    if (current == null) return;
    current.addCell(cellNode, plainText);
    debugLog(() => 'TableLeafRegistry: add cell "${plainText.replaceAll('\n', '\\n')}"');
  }

  void endRow() {
    final current = _current;
    if (current == null) return;
    current.endRow();
    debugLog(() => 'TableLeafRegistry: end row');
  }

  void endTable() {
    final current = _current;
    if (current != null) {
      _groups.add(current);
      debugLog(() => 'TableLeafRegistry: end table with ${current.rows.length} rows');
    }
    _current = null;
  }

  Iterable<TableLeafGroup> get groups => _groups;

  String? toMarkdown(String selectedPlainText) {
    final normalized = _normalize(selectedPlainText);
    debugLog(() => 'TableLeafRegistry: lookup text="${selectedPlainText.replaceAll('\n', '\\n')}"');
    for (final group in _groups) {
      debugLog(() => 'TableLeafRegistry: compare against table ${group.tableNode.hashCode} text="${group.concatenatedText.replaceAll('\n', '\\n')}"');
      if (_normalize(group.concatenatedText) == normalized) {
        debugLog(() => 'TableLeafRegistry: match found');
        return group.toMarkdown();
      }
    }
    debugLog(() => 'TableLeafRegistry: no match');
    return null;
  }

  String _normalize(String value) {
    return value.replaceAll('\r', '').replaceAll('\n', '');
  }
}
