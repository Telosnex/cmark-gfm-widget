import 'package:cmark_gfm_widget/src/selection/selection_serializer.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../widgets/source_markdown_registry.dart';
import 'markdown_selection_model.dart';

/// Custom [SelectionContainer] for paragraph blocks that uses [MarkdownSelectionModel]
/// to preserve inline formatting (bold, italic, code, links, etc.) in partial selections.
///
/// DISABLED BY DEFAULT (via [kUseMarkdownSelectables] flag) because custom selection
/// containers cause cross-boundary drag issues:
/// - Selection behavior becomes inconsistent when dragging across paragraph boundaries
/// - Adds complexity without clear benefit given the serializer's capabilities
///
/// Instead, we let Flutter handle selection normally and use [SelectionSerializer]
/// to reconstruct markdown from fragments at copy time.
class MarkdownSelectableParagraph extends StatelessWidget {
  const MarkdownSelectableParagraph({
    super.key,
    required this.attachment,
    required this.child,
  });

  final MarkdownSourceAttachment attachment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(
      delegate: MarkdownParagraphSelectionDelegate(attachment: attachment),
      child: child,
    );
  }
}

@visibleForTesting
class MarkdownParagraphSelectionDelegate
    extends MultiSelectableSelectionContainerDelegate {
  MarkdownParagraphSelectionDelegate({required this.attachment});

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
    final node = attachment.blockNode;
    if (node == null || ranges.isEmpty) {
      return null;
    }
    final model = MarkdownSelectionModel(node);
    final int start = ranges.first.normalizedStart;
    final int end = ranges.last.normalizedEnd;
    return model.toMarkdown(start, end);
  }
}
