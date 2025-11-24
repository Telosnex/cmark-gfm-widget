import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../widgets/source_markdown_registry.dart';
import 'markdown_selection_model.dart';
import 'selection_serializer.dart';

/// Custom [SelectionContainer] for list blocks that uses [MarkdownSelectionModel]
/// to preserve bullet markers and inline formatting in partial selections.
///
/// DISABLED BY DEFAULT (via [kUseMarkdownSelectables] flag) because wrapping lists
/// in custom SelectionContainers breaks cross-boundary drag selection:
/// - Dragging from a paragraph into a list only captures partial text (e.g., "Th")
/// - Bullet markers live in separate Text widgets outside the SelectionContainer
/// - Visual selection highlight doesn't match what gets copied
///
/// Instead, we let Flutter handle selection normally and use [SelectionSerializer]
/// with fragment aggregation to reconstruct proper markdown at copy time.
class MarkdownSelectableList extends StatelessWidget {
  const MarkdownSelectableList({
    super.key,
    required this.attachment,
    required this.child,
  });

  final MarkdownSourceAttachment attachment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(
      delegate: MarkdownListSelectionDelegate(attachment: attachment),
      child: child,
    );
  }
}

@visibleForTesting
class MarkdownListSelectionDelegate
    extends MultiSelectableSelectionContainerDelegate {
  MarkdownListSelectionDelegate({required this.attachment});

  final MarkdownSourceAttachment attachment;

  @override
  void ensureChildUpdated(Selectable selectable) {}

  @override
  SelectedContent? getSelectedContent() {
    final SelectedContent? content = super.getSelectedContent();
    if (content == null) {
      return content;
    }

    final String? markdown = markdownForRanges(_collectRanges());
    if (markdown == null || markdown.isEmpty) {
      return content;
    }

    return SelectedContent(plainText: markdown);
  }

  List<SelectionRange> _collectRanges() {
    final ranges = <SelectionRange>[];
    int cumulativeOffset = 0;
    for (final Selectable selectable in selectables) {
      final SelectedContentRange? range = selectable.getSelection();
      final int length = selectable.contentLength;
      if (range != null && range.startOffset != range.endOffset) {
        ranges.add(SelectionRange(
          cumulativeOffset + range.startOffset,
          cumulativeOffset + range.endOffset,
        ));
      }
      cumulativeOffset += length;
    }
    return ranges;
  }

  @visibleForTesting
  String? markdownForRanges(List<SelectionRange> ranges) {
    if (ranges.isEmpty) {
      return null;
    }
    final source = attachment.fullSource;
    if (source.isEmpty) {
      return null;
    }
    final expanded = _expandRangesToLineBoundaries(ranges, source);
    if (expanded.isEmpty) {
      return null;
    }
    final int start = _clamp(expanded.first.normalizedStart, 0, source.length);
    final int end = _clamp(expanded.last.normalizedEnd, 0, source.length);
    if (start >= end) {
      return null;
    }
    return source.substring(start, end);
  }

  List<SelectionRange> _expandRangesToLineBoundaries(
    List<SelectionRange> ranges,
    String source,
  ) {
    if (ranges.isEmpty) {
      return <SelectionRange>[];
    }
    final expanded = <SelectionRange>[];
    for (final range in ranges) {
      var start = _clamp(range.normalizedStart, 0, source.length);
      var end = _clamp(range.normalizedEnd, 0, source.length);
      while (start > 0 && source[start - 1] != '\n') {
        start--;
      }
      while (end < source.length && source[end] != '\n') {
        end++;
      }
      if (end < source.length) {
        end++;
      }
      expanded.add(SelectionRange(start, end));
    }
    expanded.sort((a, b) => a.normalizedStart.compareTo(b.normalizedStart));
    final merged = <SelectionRange>[];
    for (final range in expanded) {
      if (merged.isEmpty) {
        merged.add(range);
        continue;
      }
      final last = merged.last;
      if (range.normalizedStart <= last.normalizedEnd) {
        final newEnd = range.normalizedEnd > last.normalizedEnd
            ? range.normalizedEnd
            : last.normalizedEnd;
        merged[merged.length - 1] = SelectionRange(
          last.normalizedStart,
          newEnd,
        );
      } else {
        merged.add(range);
      }
    }
    return merged;
  }
}
  int _clamp(int value, int min, int max) {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }
