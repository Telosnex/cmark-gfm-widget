import 'dart:math' as math;

import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/rendering.dart';

import '../flutter/debug_log.dart';
import 'leaf_text_registry.dart';
import 'markdown_selection_model.dart';

import '../widgets/source_markdown_registry.dart';

/// Represents a single selected fragment coming from a Selectable child.
class SelectionFragment {
  SelectionFragment({
    required this.rect,
    required this.plainText,
    required this.contentLength,
    this.attachment,
    this.range,
  });

  final Rect rect;
  final String plainText;
  final int contentLength;
  final MarkdownSourceAttachment? attachment;
  final SelectionRange? range;
}

/// Inclusive-exclusive range of UTF-16 offsets within a Selectable.
class SelectionRange {
  const SelectionRange(this.start, this.end);

  final int start;
  final int end;

  int get normalizedStart => math.min(start, end);
  int get normalizedEnd => math.max(start, end);

  bool isFull(int length) => normalizedStart == 0 && normalizedEnd == length;
}

const Set<CmarkNodeType> _listItemCoverageTypes = <CmarkNodeType>{
  CmarkNodeType.paragraph,
  CmarkNodeType.heading,
  CmarkNodeType.htmlBlock,
  CmarkNodeType.customBlock,
  CmarkNodeType.codeBlock,
  CmarkNodeType.mathBlock,
};

const Set<CmarkNodeType> _listItemBlockTypes = <CmarkNodeType>{
  ..._listItemCoverageTypes,
  CmarkNodeType.list,
};

class SelectionSerializer {
  SelectionSerializer({this.newlineThreshold = 5});

  /// Vertical pixel delta that triggers a newline between fragments.
  final double newlineThreshold;

  String serialize(List<SelectionFragment> fragments) {
    if (fragments.isEmpty) {
      return '';
    }

    final buffer = StringBuffer();
    MarkdownSourceAttachment? lastAttachmentUsed;
    Rect? lastRect;

    final nodeIndex = _buildNodeIndex(fragments);
    debugLog(() =>
        'SelectionSerializer: fragments=${fragments.length}, nodes=${nodeIndex.length}');
    final fullySelectedListItems =
        _findFullySelectedListItems(nodeIndex, fragments);
    final tableRowGroups = _groupTableRows(nodeIndex, fragments);
    debugLog(() =>
        'SelectionSerializer: full list items=${fullySelectedListItems.length}, table rows=${tableRowGroups.length}');

    final emittedListItems = <CmarkNode>{};
    final emittedTableRows = <CmarkNode>{};

    for (var i = 0; i < fragments.length; i++) {
      final fragment = fragments[i];
      final attachment = fragment.attachment;
      final node = attachment?.blockNode;

      String textToWrite;

      debugLog(() =>
          'Fragment $i node=${node?.type} attachment=${attachment != null}');

      if (node != null &&
          node.parent?.type == CmarkNodeType.item &&
          fullySelectedListItems.contains(node.parent!) &&
          emittedListItems.add(node.parent!)) {
        textToWrite = _buildListItemMarkdown(
          node.parent!,
          nodeIndex,
          fragments,
        );
        _markDescendantItemsEmitted(node.parent!, emittedListItems);
      } else if (node != null &&
          node.parent?.type == CmarkNodeType.item &&
          fullySelectedListItems.contains(node.parent!)) {
        continue;
      } else if (node != null && node.type == CmarkNodeType.tableCell) {
        final row = node.parent;
        final group = row != null ? tableRowGroups[row] : null;
        if (row != null &&
            row.type == CmarkNodeType.tableRow &&
            group != null &&
            group.length > 1) {
          if (!emittedTableRows.add(row)) {
            continue;
          }
          debugLog(() => 'Serializing table row with ${group.length} cells');
          textToWrite = _buildTableRowMarkdown(row, group, fragments);
        } else {
          textToWrite = _serializeFragment(fragment);
        }
      } else {
        textToWrite = _serializeFragment(fragment);
      }

      if (textToWrite.isEmpty) {
        continue;
      }

      final range = fragment.range;
      final nodeType = attachment?.blockNode?.type;
      final isDuplicateBlock = attachment != null &&
          attachment == lastAttachmentUsed &&
          range != null &&
          range.isFull(fragment.contentLength) &&
          // List fragments share one attachment but represent different items.
          nodeType != CmarkNodeType.list;

      if (isDuplicateBlock) {
        debugLog(() =>
            'Skipping duplicate fragment for ${attachment.blockNode?.type}');
        continue;
      }

      if (lastRect != null) {
        final topDiff = fragment.rect.top - lastRect.top;
        // Different source blocks are never inline continuations of each
        // other, so always separate them; identical(null, null) keeps
        // same-line unattributed spans (and same-block leaves) joined.
        final blockChanged =
            !identical(attachment?.blockNode, lastAttachmentUsed?.blockNode);
        if (blockChanged) {
          // Blank line between blocks: canonical markdown block separation
          // (a single newline would merge adjacent paragraphs on re-render).
          // Exception: rows of the same table, where a blank line would
          // terminate the table.
          final wantNewlines = _inSameTable(
            attachment?.blockNode,
            lastAttachmentUsed?.blockNode,
          )
              ? 1
              : 2;
          _ensureTrailingNewlines(buffer, wantNewlines);
        } else if (topDiff > newlineThreshold) {
          buffer.writeln();
        }
      }

      _insertIntermediateBlocks(buffer, lastAttachmentUsed, attachment);

      buffer.write(textToWrite);
      lastAttachmentUsed = attachment;
      lastRect = fragment.rect;
    }

    return buffer.toString();
  }

  /// Appends newlines so [buffer] ends with exactly [count] of them (never
  /// removes existing ones).
  static void _ensureTrailingNewlines(StringBuffer buffer, int count) {
    final current = buffer.toString();
    var trailing = 0;
    for (var i = current.length - 1;
        i >= 0 && current[i] == '\n' && trailing < count;
        i--) {
      trailing++;
    }
    for (var i = trailing; i < count; i++) {
      buffer.write('\n');
    }
  }

  static bool _inSameTable(CmarkNode? a, CmarkNode? b) {
    final tableA = _ancestorTable(a);
    if (tableA == null) return false;
    return identical(tableA, _ancestorTable(b));
  }

  static CmarkNode? _ancestorTable(CmarkNode? node) {
    var current = node;
    while (current != null) {
      if (current.type == CmarkNodeType.table) return current;
      current = current.parent;
    }
    return null;
  }

  /// Emits markdown for blocks that sit between two selected siblings even if
  /// Flutter never produced a fragment for them (for example thematic breaks).
  void _insertIntermediateBlocks(
    StringBuffer buffer,
    MarkdownSourceAttachment? previous,
    MarkdownSourceAttachment? current,
  ) {
    if (previous == null || current == null) return;
    final prevNode = previous.blockNode;
    final currNode = current.blockNode;
    if (prevNode == null || currNode == null) return;
    // Same node (e.g., multiple fragments from same list) - no intermediates
    if (identical(prevNode, currNode)) return;
    if (prevNode.parent != currNode.parent) return;

    var sibling = prevNode.next;
    while (sibling != null && !identical(sibling, currNode)) {
      if (sibling.type == CmarkNodeType.thematicBreak) {
        // Keep intermediate blocks consistent with the fragment writer:
        // blocks are separated by blank lines.
        _ensureTrailingNewlines(buffer, 2);
        buffer.write('---');
        _ensureTrailingNewlines(buffer, 2);
      }
      sibling = sibling.next;
    }
  }

  Map<CmarkNode, List<int>> _buildNodeIndex(List<SelectionFragment> fragments) {
    final Map<CmarkNode, List<int>> index = <CmarkNode, List<int>>{};
    for (var i = 0; i < fragments.length; i++) {
      final node = fragments[i].attachment?.blockNode;
      if (node == null) {
        continue;
      }
      index.putIfAbsent(node, () => <int>[]).add(i);
    }
    return index;
  }

  Set<CmarkNode> _findFullySelectedListItems(
    Map<CmarkNode, List<int>> nodeIndex,
    List<SelectionFragment> fragments,
  ) {
    final result = <CmarkNode>{};
    for (final entry in nodeIndex.entries) {
      final node = entry.key;
      final parent = node.parent;
      if (parent == null || parent.type != CmarkNodeType.item) {
        continue;
      }
      if (result.contains(parent)) {
        continue;
      }
      if (_isListItemFullySelected(parent, nodeIndex, fragments)) {
        result.add(parent);
      }
    }
    return result;
  }

  Map<CmarkNode, List<int>> _groupTableRows(
    Map<CmarkNode, List<int>> nodeIndex,
    List<SelectionFragment> fragments,
  ) {
    final Map<CmarkNode, List<int>> rows = <CmarkNode, List<int>>{};
    nodeIndex.forEach((node, indices) {
      if (node.type != CmarkNodeType.tableCell) {
        return;
      }
      final row = node.parent;
      if (row == null || row.type != CmarkNodeType.tableRow) {
        return;
      }
      rows.putIfAbsent(row, () => <int>[]).addAll(indices);
    });
    return rows;
  }

  bool _isListItemFullySelected(
    CmarkNode item,
    Map<CmarkNode, List<int>> nodeIndex,
    List<SelectionFragment> fragments,
  ) {
    final blocks = _collectDescendantBlocks(item).toList();
    if (blocks.isEmpty) {
      return false;
    }

    for (final block in blocks) {
      final indices = nodeIndex[block];
      if (indices == null || indices.isEmpty) {
        return false;
      }

      var hasFull = false;
      for (final index in indices) {
        final range = fragments[index].range;
        if (range == null) {
          continue;
        }
        if (range.isFull(fragments[index].contentLength)) {
          hasFull = true;
          break;
        }
      }

      if (!hasFull) {
        return false;
      }
    }

    return true;
  }

  Iterable<CmarkNode> _collectDescendantBlocks(CmarkNode node) sync* {
    var child = node.firstChild;
    while (child != null) {
      if (_listItemCoverageTypes.contains(child.type)) {
        yield child;
      } else if (child.type == CmarkNodeType.list) {
        var nestedItem = child.firstChild;
        while (nestedItem != null) {
          if (nestedItem.type == CmarkNodeType.item) {
            yield* _collectDescendantBlocks(nestedItem);
          }
          nestedItem = nestedItem.next;
        }
      }
      child = child.next;
    }
  }

  Iterable<CmarkNode> _listItemBlockChildren(CmarkNode item) sync* {
    var child = item.firstChild;
    while (child != null) {
      if (_listItemBlockTypes.contains(child.type)) {
        yield child;
      }
      child = child.next;
    }
  }

  String _buildListItemMarkdown(
    CmarkNode item,
    Map<CmarkNode, List<int>> nodeIndex,
    List<SelectionFragment> fragments,
  ) {
    final CmarkNode list = item.parent!;
    assert(list.type == CmarkNodeType.list);

    final data = list.listData;
    final ordered = data.listType == CmarkListType.ordered;
    final startNumber = ordered ? (data.start == 0 ? 1 : data.start) : 1;

    var itemNumber = startNumber;
    var current = list.firstChild;
    while (current != null) {
      if (current.type == CmarkNodeType.item) {
        if (identical(current, item)) {
          break;
        }
        itemNumber += 1;
      }
      current = current.next;
    }

    final marker = ordered ? '$itemNumber.' : '-';

    final buffer = StringBuffer();
    var firstBlock = true;
    for (final block in _listItemBlockChildren(item)) {
      if (block.type == CmarkNodeType.list) {
        final nestedText =
            _serializeNestedList(block, nodeIndex, fragments, indent: '  ');
        if (nestedText.isEmpty) {
          continue;
        }
        if (!firstBlock) {
          buffer.writeln();
        } else {
          buffer.write(marker);
        }
        final trimmedNested = (!firstBlock && nestedText.startsWith('\n'))
            ? nestedText.substring(1)
            : nestedText;
        buffer.write(trimmedNested);
        firstBlock = false;
        continue;
      }

      final indices = nodeIndex[block];
      if (indices == null || indices.isEmpty) {
        continue;
      }

      final blockText = _blockText(block, indices, fragments);
      if (blockText.isEmpty) {
        continue;
      }
      if (firstBlock) {
        buffer.write('$marker $blockText');
        firstBlock = false;
      } else {
        buffer.write('\n  $blockText');
      }
    }

    return buffer.toString();
  }

  /// Combines the fragments belonging to one block. Code blocks render one
  /// selectable per line, so their fragments are joined with newlines; other
  /// blocks render a single paragraph, so the first fragment carries the text.
  String _blockText(
    CmarkNode block,
    List<int> indices,
    List<SelectionFragment> fragments,
  ) {
    if (block.type == CmarkNodeType.codeBlock && indices.length > 1) {
      return indices.map((index) => fragments[index].plainText).join('\n');
    }
    return fragments[indices.first].plainText;
  }

  String _serializeNestedList(
    CmarkNode list,
    Map<CmarkNode, List<int>> nodeIndex,
    List<SelectionFragment> fragments, {
    required String indent,
  }) {
    final buffer = StringBuffer();
    final ordered = list.listData.listType == CmarkListType.ordered;
    final startNumber =
        ordered ? (list.listData.start == 0 ? 1 : list.listData.start) : 1;

    var itemNumber = startNumber;
    var item = list.firstChild;
    while (item != null) {
      assert(item.type == CmarkNodeType.item,
          'Lists should only contain list items.');

      final childBlocks = _listItemBlockChildren(item).toList();
      if (childBlocks.isEmpty) {
        item = item.next;
        itemNumber += 1;
        continue;
      }

      final marker = ordered ? '$itemNumber.' : '-';
      buffer.write('\n');
      buffer.write(indent);
      buffer.write('$marker ');

      var firstBlock = true;
      for (final block in childBlocks) {
        if (block.type == CmarkNodeType.list) {
          final nested = _serializeNestedList(block, nodeIndex, fragments,
              indent: '$indent  ');
          buffer.write(nested);
          continue;
        }

        final indices = nodeIndex[block];
        if (indices == null || indices.isEmpty) {
          continue;
        }

        final blockText = _blockText(block, indices, fragments);
        if (blockText.isEmpty) {
          continue;
        }
        if (!firstBlock) {
          buffer.write('\n');
          buffer.write(indent);
          buffer.write('  ');
        }
        buffer.write(blockText);
        firstBlock = false;
      }

      item = item.next;
      itemNumber += 1;
    }

    return buffer.toString();
  }

  String _buildTableRowMarkdown(
    CmarkNode row,
    List<int> selectionIndices,
    List<SelectionFragment> fragments,
  ) {
    if (selectionIndices.isEmpty) {
      return '';
    }

    selectionIndices.sort((a, b) {
      final rectA = fragments[a].rect;
      final rectB = fragments[b].rect;
      return rectA.left.compareTo(rectB.left);
    });

    final cellTexts = <String>[];
    for (final index in selectionIndices) {
      final fragment = fragments[index];
      cellTexts.add(fragment.plainText);
    }

    return '| ${cellTexts.join(' | ')} |';
  }

  String _serializeFragment(SelectionFragment fragment) {
    final attachment = fragment.attachment;
    final CmarkNodeType? nodeType = attachment?.blockNode?.type;

    // Thematic breaks render invisible \r---\r text for selectability.
    if (nodeType == CmarkNodeType.thematicBreak) {
      return '---\n';
    }

    final node = attachment?.blockNode;
    if (node != null) {
      final model = MarkdownSelectionModel(node);
      final range = fragment.range;
      if (range != null) {
        final markdown =
            model.toMarkdown(range.normalizedStart, range.normalizedEnd);
        if (markdown.isNotEmpty) {
          return markdown;
        }
      }

      // Coarse ConversationScreen selections are expanded into one full-block
      // fragment per SourceAware block. In that path no precise range is
      // available, but the fragment text is exactly the block's projected text,
      // so serialize the full block back to markdown.
      if (_normalized(fragment.plainText) == _normalized(model.plainText)) {
        final markdown = model.toMarkdown(0, model.length);
        if (markdown.isNotEmpty) {
          return markdown;
        }
      }
    }

    // Try table registry fallback for fragments without attachments
    if (attachment == null) {
      final tableMarkdown =
          TableLeafRegistry.instance.toMarkdown(fragment.plainText);
      if (tableMarkdown != null) {
        return tableMarkdown;
      }
    }

    return fragment.plainText;
  }

  String _normalized(String value) =>
      value.replaceAll('\r', '').replaceAll(RegExp(r'\s+'), ' ').trim();

  void _markDescendantItemsEmitted(
    CmarkNode item,
    Set<CmarkNode> emitted,
  ) {
    var child = item.firstChild;
    while (child != null) {
      if (child.type == CmarkNodeType.list) {
        var nested = child.firstChild;
        while (nested != null) {
          if (nested.type == CmarkNodeType.item) {
            if (emitted.add(nested)) {
              _markDescendantItemsEmitted(nested, emitted);
            }
          }
          nested = nested.next;
        }
      }
      child = child.next;
    }
  }
}
