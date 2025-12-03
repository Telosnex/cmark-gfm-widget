import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:cmark_gfm_widget/src/flutter/debug_log.dart';

import 'stable_id_registry.dart';

/// Immutable representation of a parsed Markdown document.
class DocumentSnapshot {
  /// Cached source strings for each block node, computed at snapshot creation
  /// while positions are still valid.
  final Map<CmarkNode, String> _sourceCache = {};
  DocumentSnapshot._({
    required this.root,
    required this.revision,
    this.sourceMarkdown,
    List<int>? lineOffsets,
  }) : _lineOffsets = lineOffsets;

  /// Root node of the document (always of type [CmarkNodeType.document]).
  final CmarkNode root;

  /// Snapshot revision (monotonic counter assigned by the controller).
  final int revision;

  /// Original markdown source, used for extracting source ranges.
  final String? sourceMarkdown;

  /// Precomputed start offsets for each line (1-based index).
  final List<int>? _lineOffsets;

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
    final snapshot = DocumentSnapshot._(
      root: root,
      revision: revision,
      sourceMarkdown: sourceMarkdown,
      lineOffsets:
          sourceMarkdown != null ? _computeLineOffsets(sourceMarkdown) : null,
    );
    
    // Cache source strings NOW while positions are still valid.
    // This enables incremental parsing - future parses may invalidate positions,
    // but each snapshot captures sources at the moment it was created.
    if (sourceMarkdown != null) {
      for (final block in snapshot.blocks) {
        final source = snapshot._extractNodeSource(block);
        if (source != null) {
          snapshot._sourceCache[block] = source;
        }
      }
    }
    
    return snapshot;
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
    final offsets = _lineOffsets;
    if (offsets == null || line < 1 || line > offsets.length) {
      return null;
    }

    if (column <= 0) {
      final currentStart = offsets[line - 1];
      final newlinePos = currentStart - 1;
      return newlinePos >= 0 ? newlinePos : 0;
    }

    final start = offsets[line - 1];
    final nextStart = line < offsets.length ? offsets[line] : source.length;
    final hasNewline =
        nextStart > start && source.codeUnitAt(nextStart - 1) == 0x0A;
    final contentEnd = hasNewline ? nextStart - 1 : nextStart;
    final maxColumn = (contentEnd - start) + 1;

    if (column <= maxColumn) {
      return start + (column - 1);
    }

    if (hasNewline) {
      return nextStart - 1;
    }

    return source.length;
  }

  /// Extract the original markdown source for a node.
  /// Returns cached value if available (populated at snapshot creation).
  String? getNodeSource(CmarkNode node) {
    // Return cached source if available
    final cached = _sourceCache[node];
    if (cached != null) return cached;
    
    // Fallback to computing (for nodes not in cache, e.g. inline nodes)
    return _extractNodeSource(node);
  }
  
  /// Internal method to extract source from line/column positions.
  /// Called at snapshot creation to populate cache.
  String? _extractNodeSource(CmarkNode node) {
    final source = sourceMarkdown;
    if (source == null) {
      return null;
    }

    // For headings and lists, always start from column 1 to include prefix
    final startCol =
        (node.type == CmarkNodeType.heading || node.type == CmarkNodeType.list)
            ? 1
            : node.startColumn;
    int? startOffset = lineColToOffset(node.startLine, startCol);

    // Column 0 means "start of line" - find end of previous line
    int? endOffsetRaw;
    if (node.endColumn == 0) {
      final offsets = _lineOffsets;
      if (offsets != null && node.endLine - 1 < offsets.length) {
        final newlinePos = offsets[node.endLine - 1] - 1;
        if (newlinePos >= 0 && newlinePos < source.length) {
          endOffsetRaw = newlinePos;
        }
      }
    }
    endOffsetRaw ??= lineColToOffset(node.endLine, node.endColumn);

    // Fallback: if we have startOffset but endOffset failed (parser didn't populate
    // endLine/endColumn), try to find the node's literal content in the source and
    // use that to compute the end offset. This handles cases where our cmark-dart
    // port doesn't track source positions as precisely as the C implementation.
    int? startOffsetLocal = startOffset;
    if (startOffsetLocal != null && endOffsetRaw == null) {
      final literal = node.content.toString();
      if (literal.isNotEmpty) {
        final index = source.indexOf(literal, startOffsetLocal);
        if (index != -1) {
          startOffsetLocal = index;
          endOffsetRaw = index + literal.length;
          debugLog(() =>
              '⚠️ _extractNodeSource matched literal for ${node.type} length=${literal.length} at index=$index');
        } else {
          endOffsetRaw = (startOffsetLocal + literal.length).clamp(0, source.length);
          debugLog(() =>
              '⚠️ _extractNodeSource fallback using literal length for ${node.type}');
        }
      }
    }

    if (startOffsetLocal == null || endOffsetRaw == null) {
      debugLog(() =>
          '❌ _extractNodeSource failed for node ${node.type} start=${node.startLine}:${node.startColumn} end=${node.endLine}:${node.endColumn}');
      return null;
    }

    // Add 1 to endOffset - cmark's endColumn points to the position before the end
    final endOffset = endOffsetRaw + 1;

    if (startOffsetLocal >= endOffset) {
      return null;
    }

    var extracted = source.substring(
      startOffsetLocal,
      endOffset.clamp(0, source.length),
    );

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
        '✅ _extractNodeSource: lines ${node.startLine}:${node.startColumn} to ${node.endLine}:${node.endColumn} extracted ${extracted.length} chars: "${extracted.replaceAll('\n', '\\n')}"');
    return extracted;
  }
}

List<int> _computeLineOffsets(String source) {
  final offsets = <int>[0];
  for (var i = 0; i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0A) {
      offsets.add(i + 1);
    }
  }
  return offsets;
}
