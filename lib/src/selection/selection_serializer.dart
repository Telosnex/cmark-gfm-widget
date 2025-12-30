import 'dart:math' as math;

import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/rendering.dart';

import '../flutter/debug_log.dart';
import 'leaf_text_registry.dart';

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

    // Pre-process: aggregate list fragments that belong to same node.
    // Flutter often delivers list selections as many tiny fragments (bullet + text
    // runs), so we collapse them into one fragment per list with a proper range.
    final aggregated = _aggregateListFragments(fragments);

    final buffer = StringBuffer();
    MarkdownSourceAttachment? lastAttachmentUsed;
    Rect? lastRect;

    final nodeIndex = _buildNodeIndex(aggregated);
    debugLog(() => 'SelectionSerializer: fragments=${aggregated.length}, nodes=${nodeIndex.length}');
    final fullySelectedListItems =
        _findFullySelectedListItems(nodeIndex, aggregated);
    final tableRowGroups = _groupTableRows(nodeIndex, aggregated);
    debugLog(() => 'SelectionSerializer: full list items=${fullySelectedListItems.length}, table rows=${tableRowGroups.length}');

    final emittedListItems = <CmarkNode>{};
    final emittedTableRows = <CmarkNode>{};

    for (var i = 0; i < aggregated.length; i++) {
      final fragment = aggregated[i];
      final attachment = fragment.attachment;
      final node = attachment?.blockNode;

      String textToWrite;

      debugLog(() => 'Fragment $i node=${node?.type} attachment=${attachment != null}');

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
      } else if (node != null &&
          node.type == CmarkNodeType.tableCell) {
        final row = node.parent;
        final group =
            row != null ? tableRowGroups[row] : null;
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
      final isDuplicateBlock = attachment != null &&
          attachment == lastAttachmentUsed &&
          range != null &&
          range.isFull(fragment.contentLength);

      if (isDuplicateBlock) {
        debugLog(() => 'Skipping duplicate fragment for ${attachment.blockNode?.type}');
        continue;
      }

      if (lastRect != null) {
        final topDiff = fragment.rect.top - lastRect.top;
        if (topDiff > newlineThreshold) {
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
        buffer.writeln('---');
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

      final fragment = fragments[indices.first];
      final blockText = _serializeEntireNode(fragment);
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

  String _serializeNestedList(
    CmarkNode list,
    Map<CmarkNode, List<int>> nodeIndex,
    List<SelectionFragment> fragments, {
    required String indent,
  }) {
    final buffer = StringBuffer();
    final ordered = list.listData.listType == CmarkListType.ordered;
    final startNumber = ordered ? (list.listData.start == 0 ? 1 : list.listData.start) : 1;

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
          final nested =
              _serializeNestedList(block, nodeIndex, fragments, indent: '$indent  ');
          buffer.write(nested);
          continue;
        }

        final indices = nodeIndex[block];
        if (indices == null || indices.isEmpty) {
          continue;
        }

        final fragment = fragments[indices.first];
        final blockText = _serializeEntireNode(fragment);
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
      final range = fragment.range;
      final model = fragment.attachment?.selectionModel;
      if (model != null && range != null) {
        cellTexts.add(
          model.toMarkdown(range.normalizedStart, range.normalizedEnd),
        );
      } else {
        cellTexts.add(fragment.plainText);
      }
    }

    return '| ${cellTexts.join(' | ')} |';
  }

  String _serializeEntireNode(SelectionFragment fragment) {
    final attachment = fragment.attachment!;
    final model = attachment.selectionModel;
    assert(model != null, 'Expected selection model for block node attachments.');
    return model!.toMarkdown(0, model.length);
  }

  String _serializeFragment(SelectionFragment fragment) {
    final attachment = fragment.attachment;
    var range = fragment.range;
    final CmarkNodeType? nodeType = attachment?.blockNode?.type;
    
    // Code blocks: use fences only if entire block is selected
    if (attachment != null && nodeType == CmarkNodeType.codeBlock) {
      final model = attachment.selectionModel;
      final modelPlainText = model?.plainText ?? '';
      final fragmentText = fragment.plainText.trim();
      // Full block if fragment matches model's plainText (the code content)
      final isFullBlock = fragmentText.isNotEmpty && fragmentText == modelPlainText.trim();
      debugLog(() => 'Code block: isFullBlock=$isFullBlock fragment="${fragmentText.replaceAll('\n', '\\n')}" model="${modelPlainText.replaceAll('\n', '\\n')}"');
      if (isFullBlock) {
        // Full selection - include fences
        return attachment.fullSource;
      } else {
        // Partial selection - just the selected text, no fences
        return fragment.plainText;
      }
    }

    // For list fragments without a range, compute one from plainText
    if (attachment != null && range == null && nodeType == CmarkNodeType.list) {
      final model = attachment.selectionModel;
      if (model != null) {
        final modelText = model.plainText;
        final trimmedPlain = fragment.plainText.trim();
        if (trimmedPlain.isNotEmpty && !_listMarkerOnlyPattern.hasMatch(fragment.plainText)) {
          final startIdx = modelText.indexOf(trimmedPlain);
          if (startIdx >= 0) {
            range = SelectionRange(startIdx, startIdx + trimmedPlain.length);
            debugLog(() => 'Computed range ($startIdx, ${startIdx + trimmedPlain.length}) for list fragment');
          }
        }
      }
    }
    
    

    if (attachment == null || range == null) {
      // For list marker-only fragments, skip them
      if (nodeType == CmarkNodeType.list && _listMarkerOnlyPattern.hasMatch(fragment.plainText)) {
        debugLog(() => '_serializeFragment: skipping marker-only fragment "${fragment.plainText}"');
        return '';
      }
      // Try table registry fallback
      final tableMarkdown = TableLeafRegistry.instance.toMarkdown(fragment.plainText);
      if (tableMarkdown != null) {
        debugLog(() => 'Using table registry fallback for fragment');
        return tableMarkdown;
      }
      return fragment.plainText;
    }

    if (nodeType == CmarkNodeType.list) {
      final normalizedSource = attachment.fullSource.trim();
      final normalizedPlainText = fragment.plainText.trim();
      final bool fullSourceMatches = normalizedSource == normalizedPlainText;
      if (!fullSourceMatches) {
        return _expandListFragmentToLines(fragment, attachment, range);
      }
    }

    final model = attachment.selectionModel;
    if (model != null) {
      final snippet =
          model.toMarkdown(range.normalizedStart, range.normalizedEnd);
      if (snippet.isNotEmpty) {
        return snippet;
      }
    }

    if (range.isFull(fragment.contentLength)) {
      // For table cells, fall back to the aggregate plain text rather than
      // the cell's own source. The selection system may have collapsed an
      // entire table into a single fragment, and using the cell source here
      // would drop all but the first cell.
      if (nodeType == CmarkNodeType.tableCell) {
        return fragment.plainText;
      }

      return attachment.fullSource;
    }

    return fragment.plainText;
  }

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

  /// Collapses Flutter's per-run list fragments into a single fragment per
  /// list attachment so we can compute the correct selection range before
  /// serialization.
  List<SelectionFragment> _aggregateListFragments(
      List<SelectionFragment> fragments) {
    // Group fragments by their attachment
    final groups = <MarkdownSourceAttachment?, List<SelectionFragment>>{};
    for (final fragment in fragments) {
      groups.putIfAbsent(fragment.attachment, () => []).add(fragment);
    }

    final aggregated = <SelectionFragment>[];
    for (final entry in groups.entries) {
      final attachment = entry.key;
      final group = entry.value;

      // Only aggregate if it's a list with multiple fragments and no ranges
      if (attachment != null &&
          attachment.blockNode?.type == CmarkNodeType.list &&
          group.length > 1 &&
          group.every((f) => f.range == null)) {
        final allText = group.map((f) => f.plainText).join();
        final model = attachment.selectionModel;
        final modelText = model?.plainText ?? '';
        final normalizedFragments = allText.replaceAll('• ', '').replaceAll('\n', '');
        final normalizedModel = modelText.replaceAll('\n', '');

        debugLog(() =>
            '📦 Aggregating ${group.length} list fragments: '
            'text="$normalizedFragments" model="$normalizedModel" '
            'match=${normalizedFragments == normalizedModel}');

        if (normalizedFragments == normalizedModel) {
          // Full list selection
          aggregated.add(SelectionFragment(
            rect: group.first.rect,
            plainText: allText,
            contentLength: modelText.length,
            attachment: attachment,
            range: SelectionRange(0, modelText.length),
          ));
        } else {
          // Partial list - find WHERE in the actual plainText (with newlines).
          // We can't use normalized offsets because newlines shift positions.
          // Instead, search for the first and last actual text fragments (skip bullets)
          // in the model's plainText to compute the true range.
          final textFragments = group
              .where((f) => f.plainText.trim().isNotEmpty && !f.plainText.startsWith('•'))
              .toList();
          
          if (textFragments.isEmpty) {
            aggregated.addAll(group);
          } else {
            final firstText = textFragments.first.plainText;
            final lastText = textFragments.last.plainText;
            
            final startOffset = modelText.indexOf(firstText);
            if (startOffset == -1) {
              aggregated.addAll(group);
            } else {
              var endOffset = modelText.indexOf(lastText, startOffset);
              if (endOffset != -1) {
                endOffset += lastText.length;
              } else {
                endOffset = startOffset + firstText.length;
              }
              
              aggregated.add(SelectionFragment(
                rect: group.first.rect,
                plainText: allText,
                contentLength: modelText.length,
                attachment: attachment,
                range: SelectionRange(startOffset, endOffset),
              ));
            }
          }
        }
      } else {
        // Not a multi-fragment list - keep as-is
        aggregated.addAll(group);
      }
    }

    return aggregated;
  }

  /// Regex matching list markers like "1. ", "2. ", "- ", "* ", "• ", etc.
  /// Includes Unicode bullet (U+2022) which Flutter renders for unordered lists.
  static final _listMarkerOnlyPattern = RegExp(r'^\s*(\d+\.|[-*+•])\s*$');

  String _expandListFragmentToLines(
    SelectionFragment fragment,
    MarkdownSourceAttachment attachment,
    SelectionRange? computedRange,
  ) {
    // Skip list marker-only fragments (e.g., "1. ", "2. ", "- ")
    // These don't appear in the model's plainText and would incorrectly
    // expand to the full list. Content fragments will handle serialization.
    final fragmentText = fragment.plainText;
    final isMarkerOnly = _listMarkerOnlyPattern.hasMatch(fragmentText);
    debugLog(() =>
        '_expandListFragmentToLines: fragmentText="$fragmentText" codeUnits=${fragmentText.codeUnits} '
        'isMarkerOnly=$isMarkerOnly');
    if (isMarkerOnly) {
      debugLog(() =>
          '_expandListFragmentToLines: skipping marker-only fragment "$fragmentText"');
      return '';
    }

    final model = attachment.selectionModel;
    final range = computedRange ?? fragment.range;
    
    debugLog(() =>
        '_expandListFragmentToLines: model=${model != null} range=$range '
        'fragmentPlainText="${fragment.plainText.replaceAll('\n', '\\n')}" '
        'modelPlainText="${model?.plainText.replaceAll('\n', '\\n')}"');
    
    if (model == null || range == null) {
      debugLog(() => '  → returning plain text (no model/range)');
      return fragment.plainText;
    }

    // Expand range to line boundaries in the model's plain text
    final plainText = model.plainText;
    var start = range.normalizedStart.clamp(0, plainText.length);
    var end = range.normalizedEnd.clamp(0, plainText.length);
    
    // Expand start backward to line beginning
    while (start > 0 && plainText[start - 1] != '\n') {
      start--;
    }
    
    // Expand end forward to line ending
    while (end < plainText.length && plainText[end] != '\n') {
      end++;
    }
    if (end < plainText.length && plainText[end] == '\n') {
      end++; // Include the newline
    }

    debugLog(() => '  → expanded range ($start, $end)');
    
    // Use the model to serialize the expanded range
    final markdown = model.toMarkdown(start, end);
    debugLog(() =>
        '  → model.toMarkdown($start, $end) = '
        '"${markdown.replaceAll('\n', '\\n')}"');
    if (markdown.isNotEmpty) {
      return markdown;
    }

    debugLog(() => '  → markdown empty, returning plain text');
    return fragment.plainText;
  }
}
