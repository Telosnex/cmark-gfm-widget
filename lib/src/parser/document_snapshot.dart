import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:cmark_gfm_widget/src/flutter/debug_log.dart';

import 'stable_id_registry.dart';

/// Immutable representation of a parsed Markdown document.
class DocumentSnapshot {
  DocumentSnapshot._(
      {required this.root, required this.revision, this.sourceMarkdown});

  /// Root node of the document (always of type [CmarkNodeType.document]).
  final CmarkNode root;

  /// Snapshot revision (monotonic counter assigned by the controller).
  final int revision;

  /// Original markdown source, used for extracting source ranges.
  final String? sourceMarkdown;

  /// Returns an iterable of top-level block nodes.
  Iterable<CmarkNode> get blocks sync* {
    var node = root.firstChild;
    while (node != null) {
      yield node;
      node = node.next;
    }
  }

  /// Creates a snapshot from [root], assigning stable ids via [registry].
  static DocumentSnapshot fromRoot({
    required CmarkNode root,
    required StableIdRegistry registry,
    required int revision,
    String? sourceMarkdown,
  }) {
    _assignMetadata(root, registry, revision);
    registry.prune(revision - 1);
    return DocumentSnapshot._(
        root: root, revision: revision, sourceMarkdown: sourceMarkdown);
  }

  static void _assignMetadata(
    CmarkNode node,
    StableIdRegistry registry,
    int revision,
  ) {
    final id = registry.idFor(node, revision);
    node.userData = NodeMetadata(id);

    var child = node.firstChild;
    while (child != null) {
      _assignMetadata(child, registry, revision);
      child = child.next;
    }
  }

  /// Returns the metadata attached to [node], if present.
  static NodeMetadata? metadataFor(CmarkNode node) {
    final data = node.userData;
    if (data is NodeMetadata) {
      return data;
    }
    return null;
  }

  /// Convert line/column position to byte offset in source markdown.
  /// Lines and columns are 1-indexed (as per cmark spec).
  /// Column points to the byte AFTER the position (cmark convention).
  int? lineColToOffset(int line, int column) {
    final source = sourceMarkdown;
    if (source == null) return null;

    int offset = 0;
    int currentLine = 1;
    int currentCol = 1;

    while (offset < source.length) {
      if (currentLine == line && currentCol == column) {
        return offset;
      }

      if (source[offset] == '\n') {
        // If we're on the target line and column is beyond line end, return end of line
        if (currentLine == line && column > currentCol) {
          return offset;
        }
        currentLine++;
        currentCol = 1;
      } else {
        currentCol++;
      }
      offset++;
    }

    // Reached end of file
    if (currentLine == line) {
      // If column is at or beyond end of line, return offset (end of file or line)
      return offset;
    }

    return null;
  }

  /// Extract the original markdown source for a node.
  String? getNodeSource(CmarkNode node) {
    final source = sourceMarkdown;
    if (source == null) {
      return null;
    }

    // For headings and lists, always start from column 1 to include prefix
    final startCol =
        (node.type == CmarkNodeType.heading || node.type == CmarkNodeType.list)
            ? 1
            : node.startColumn;
    final startOffset = lineColToOffset(node.startLine, startCol);

    // Column 0 means "start of line" - find end of previous line
    int? endOffsetRaw;
    if (node.endColumn == 0) {
      // Find the newline that ends line (endLine - 1)
      int offset = 0;
      int currentLine = 1;
      while (offset < source.length && currentLine < node.endLine) {
        if (source[offset] == '\n') {
          currentLine++;
          if (currentLine == node.endLine) {
            endOffsetRaw = offset; // Position of the newline
            break;
          }
        }
        offset++;
      }    } else {
      endOffsetRaw = lineColToOffset(node.endLine, node.endColumn);
    }

    if (startOffset == null || endOffsetRaw == null) {
      return null;
    }

    // Add 1 to endOffset - cmark's endColumn points to the position before the end
    final endOffset = endOffsetRaw + 1;

    if (startOffset >= endOffset) {
      return null;
    }

    var extracted =
        source.substring(startOffset, endOffset.clamp(0, source.length));

    // Trim trailing whitespace - position logic will add newlines as needed
    extracted = extracted.trimRight();

    // Special case: math_block nodes don't include closing delimiter, add it back
    if (node.type == CmarkNodeType.mathBlock) {
      final opener = extracted.startsWith('\$\$')
          ? '\$\$'
          : extracted.startsWith('\\[')
              ? '\\]'
              : null;
      if (opener != null) {
        // Check if we already have the closer
        final closer = opener == '\$\$' ? '\$\$' : '\\]';
        if (!extracted.trimRight().endsWith(closer)) {
          extracted = '$extracted\n$closer';
        }
      }
    }

    debugLog(() =>
        '✅ getNodeSource: lines ${node.startLine}:${node.startColumn} to ${node.endLine}:${node.endColumn} extracted ${extracted.length} chars: "${extracted.replaceAll('\n', '\\n')}"');
    return extracted;
  }
}
