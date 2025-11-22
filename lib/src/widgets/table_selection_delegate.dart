import 'dart:math' as math;

import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';

import '../flutter/debug_log.dart';
import '../selection/markdown_selection_model.dart';

/// Selection delegate for tables that produces markdown pipe syntax when
/// multiple cells are selected.
class TableSelectionContainerDelegate
    extends MultiSelectableSelectionContainerDelegate {
  TableSelectionContainerDelegate({
    required this.tableNode,
    required this.cellNodes,
    required this.columnCount,
  });

  final CmarkNode tableNode;

  /// Cell nodes in row-major order (row 0 cells, then row 1 cells, etc.).
  final List<CmarkNode> cellNodes;
  final int columnCount;

  @override
  void ensureChildUpdated(Selectable selectable) {
    debugLog(() => 'TableSelectionContainerDelegate.ensureChildUpdated: ${selectable.runtimeType}');
  }

  @override
  void didChangeSelectables() {
    debugLog(() => 'TableSelectionContainerDelegate: now have ${selectables.length} selectables');
    super.didChangeSelectables();
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    debugLog(() => 'TableSelectionContainerDelegate.dispatchSelectionEvent: ${event.runtimeType}');
    
    // For table cells, we want to continue dispatching across all cells
    // rather than stopping at the first .end result. This allows drag
    // selection to span multiple cells.
    if (event is SelectionEdgeUpdateEvent) {
      return _dispatchEdgeUpdate(event);
    }
    
    // For other events (clear, select word/all, etc.), use default behavior.
    final result = super.dispatchSelectionEvent(event);
    debugLog(() => '  → result: $result');
    return result;
  }

  @override
  SelectionResult handleSelectWord(SelectWordSelectionEvent event) {
    debugLog(() => 'TableSelectionContainerDelegate.handleSelectWord');
    return _dispatchBoundaryEvent(event);
  }

  @override
  SelectionResult handleSelectParagraph(SelectParagraphSelectionEvent event) {
    debugLog(() => 'TableSelectionContainerDelegate.handleSelectParagraph');
    return _dispatchBoundaryEvent(event);
  }

  SelectionResult _dispatchEdgeUpdate(SelectionEdgeUpdateEvent event) {
    var result = SelectionResult.none;
    final children = selectables.toList();
    
    for (final child in children) {
      final childResult = child.dispatchSelectionEvent(event);
      debugLog(() => '    child ${child.runtimeType}: $childResult');
      
      // Accumulate results: if any child handled it, we handled it.
      // Continue through all children rather than stopping at first .end.
      switch (childResult) {
        case SelectionResult.pending:
        case SelectionResult.next:
        case SelectionResult.previous:
          if (result == SelectionResult.none) {
            result = childResult;
          }
          break;
        case SelectionResult.end:
          // Keep going to other cells; one cell ending doesn't mean table ends.
          if (result == SelectionResult.none) {
            result = SelectionResult.next;
          }
          break;
        case SelectionResult.none:
          break;
      }
    }
    
    debugLog(() => '  → accumulated result: $result');
    return result;
  }

  SelectionResult _dispatchBoundaryEvent(SelectionEvent event) {
    // For word/paragraph selection within a table, we need to find which
    // cell contains the event position and dispatch only to that cell's
    // leaf selectable (the _SelectableFragment).
    //
    // We skip intermediate containers to avoid triggering
    // _ScrollableSelectionContainerDelegate assertions.
    
    final children = selectables.toList();
    if (children.isEmpty) {
      debugLog(() => '  → boundary result: none (no children)');
      return SelectionResult.none;
    }
    
    // Find the cell that should handle this event based on the event's position.
    Selectable? targetChild;
    if (event is SelectWordSelectionEvent) {
      final globalPosition = event.globalPosition;
      for (final child in children) {
        if (_containsPosition(child, globalPosition)) {
          targetChild = child;
          break;
        }
      }
    }
    
    // If we couldn't determine target from position, try first child.
    targetChild ??= children.first;
    
    final childResult = targetChild.dispatchSelectionEvent(event);
    debugLog(() => '  → boundary result: $childResult (dispatched to ${targetChild.runtimeType})');
    return childResult;
  }

  bool _containsPosition(Selectable selectable, Offset globalPosition) {
    try {
      if (selectable is! RenderObject) {
        return false;
      }
      final transform = selectable.getTransformTo(null);
      final localPosition = MatrixUtils.transformPoint(transform.clone()..invert(), globalPosition);
      final size = selectable.size;
      return localPosition.dx >= 0 &&
          localPosition.dx <= size.width &&
          localPosition.dy >= 0 &&
          localPosition.dy <= size.height;
    } catch (_) {
      return false;
    }
  }

  @override
  SelectedContent? getSelectedContent() {
    final children = selectables.toList();
    debugLog(() => 'TableSelectionContainerDelegate.getSelectedContent: '
        'children=${children.length}, cellNodes=${cellNodes.length}');
    
    for (var i = 0; i < children.length; i++) {
      final selectable = children[i];
      final content = selectable.getSelectedContent();
      final range = selectable.getSelection();
      debugLog(() => '  Cell $i: hasContent=${content != null}, '
          'hasRange=${range != null}, '
          'text="${content?.plainText ?? "(none)"}"');
    }
    
    if (children.isEmpty) {
      return null;
    }

    final int cellCount = math.min(children.length, cellNodes.length);
    final Map<int, List<String>> rows = <int, List<String>>{};

    for (var index = 0; index < cellCount; index++) {
      final selectable = children[index];
      final SelectedContent? content = selectable.getSelectedContent();
      final SelectedContentRange? range = selectable.getSelection();
      if (content == null || range == null) {
        continue;
      }

      final int start = math.min(range.startOffset, range.endOffset);
      final int end = math.max(range.startOffset, range.endOffset);
      if (start == end) {
        continue;
      }

      final cellNode = cellNodes[index];
      final model = MarkdownSelectionModel(cellNode);
      final markdown = model.toMarkdown(start, end);
      if (markdown.isEmpty) {
        continue;
      }

      final int rowIndex = index ~/ columnCount;
      rows.putIfAbsent(rowIndex, () => <String>[]).add(markdown);
    }

    if (rows.isEmpty) {
      return null;
    }

    final buffer = StringBuffer();
    final sortedRows = rows.keys.toList()..sort();
    for (var i = 0; i < sortedRows.length; i++) {
      final cells = rows[sortedRows[i]]!;
      if (i > 0) {
        buffer.writeln();
      }
      if (cells.length == 1) {
        buffer.write(cells.first);
      } else {
        buffer.write('| ${cells.join(' | ')} |');
      }
    }

    final result = buffer.toString();
    debugLog(() => 'TableSelectionContainerDelegate: returning ${result.length} chars');
    return SelectedContent(plainText: result);
  }
}
