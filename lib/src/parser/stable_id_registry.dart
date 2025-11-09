import 'dart:collection';

import 'package:cmark_gfm/cmark_gfm.dart';

/// Internal metadata stored on [CmarkNode.userData].
class NodeMetadata {
  NodeMetadata(this.id);

  final String id;
}

/// Unique key representing the structural identity of a [CmarkNode].
class NodeKey {
  NodeKey({
    required this.typeCode,
    required this.startLine,
    required this.startColumn,
    required this.endLine,
    required this.endColumn,
    required this.childCount,
    required this.firstChildStartLine,
    required this.firstChildTypeCode,
    required this.literalHash,
    required this.extrasHash,
  });

  final int typeCode;
  final int startLine;
  final int startColumn;
  final int endLine;
  final int endColumn;
  final int childCount;
  final int firstChildStartLine;
  final int firstChildTypeCode;
  final int literalHash;
  final int extrasHash;

  @override
  int get hashCode => Object.hash(
    typeCode,
    startLine,
    startColumn,
    endLine,
    endColumn,
    childCount,
    firstChildStartLine,
    firstChildTypeCode,
    literalHash,
    extrasHash,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NodeKey) return false;
    return typeCode == other.typeCode &&
        startLine == other.startLine &&
        startColumn == other.startColumn &&
        endLine == other.endLine &&
        endColumn == other.endColumn &&
        childCount == other.childCount &&
        firstChildStartLine == other.firstChildStartLine &&
        firstChildTypeCode == other.firstChildTypeCode &&
        literalHash == other.literalHash &&
        extrasHash == other.extrasHash;
  }
}

class _Entry {
  _Entry(this.id, this.lastRevision);

  final String id;
  int lastRevision;
}

/// Manages stable identifiers for nodes across parse revisions.
class StableIdRegistry {
  StableIdRegistry();

  final Map<NodeKey, _Entry> _entries = HashMap<NodeKey, _Entry>();
  int _counter = 0;

  /// Returns a stable identifier for [node], allocating a new id if necessary.
  String idFor(CmarkNode node, int revision) {
    final key = _keyFor(node);
    final existing = _entries[key];
    if (existing != null) {
      existing.lastRevision = revision;
      return existing.id;
    }

    final id = _nextId();
    _entries[key] = _Entry(id, revision);
    return id;
  }

  /// Removes ids that have not been observed since [revisionThreshold].
  void prune(int revisionThreshold) {
    _entries.removeWhere((_, entry) => entry.lastRevision < revisionThreshold);
  }

  NodeKey _keyFor(CmarkNode node) {
    final childCount = _childCount(node);
    final firstChild = node.firstChild;
    final firstChildStartLine = firstChild?.startLine ?? -1;
    final firstChildTypeCode = firstChild?.type.encoded ?? -1;
    final literalHash = _literalHash(node);
    final extrasHash = _extrasHash(node);

    return NodeKey(
      typeCode: node.type.encoded,
      startLine: node.startLine,
      startColumn: node.startColumn,
      endLine: node.endLine,
      endColumn: node.endColumn,
      childCount: childCount,
      firstChildStartLine: firstChildStartLine,
      firstChildTypeCode: firstChildTypeCode,
      literalHash: literalHash,
      extrasHash: extrasHash,
    );
  }

  int _childCount(CmarkNode node) {
    var count = 0;
    var child = node.firstChild;
    while (child != null) {
      count++;
      child = child.next;
    }
    return count;
  }

  int _literalHash(CmarkNode node) {
    String? literal;
    switch (node.type) {
      case CmarkNodeType.text:
      case CmarkNodeType.htmlBlock:
      case CmarkNodeType.htmlInline:
        literal = node.content.toString();
        break;
      case CmarkNodeType.code:
      case CmarkNodeType.codeBlock:
        literal = node.codeData.literal;
        break;
      default:
        literal = null;
    }

    if (literal == null || literal.isEmpty) {
      return 0;
    }

    return _hashString(literal);
  }

  int _extrasHash(CmarkNode node) {
    final builder = <Object?>[];
    if (node.type == CmarkNodeType.heading) {
      builder.add(node.headingData.level);
    } else if (node.type == CmarkNodeType.list) {
      final data = node.listData;
      builder
        ..add(data.listType.index)
        ..add(data.start)
        ..add(data.delimiter.index)
        ..add(data.tight ? 1 : 0);
    } else if (node.type == CmarkNodeType.tableCell) {
      builder.add(node.tableCellData.align.index);
    } else if (node.type == CmarkNodeType.customBlock ||
        node.type == CmarkNodeType.customInline) {
      builder
        ..add(node.customData.onEnter)
        ..add(node.customData.onExit);
    } else if (node.type == CmarkNodeType.link ||
        node.type == CmarkNodeType.image) {
      builder
        ..add(node.linkData.url)
        ..add(node.linkData.title);
    }

    if (builder.isEmpty) {
      return 0;
    }

    return Object.hashAll(builder);
  }

  static int _hashString(String input) {
    const int prime = 16777619;
    const int offsetBasis = 2166136261;

    var hash = offsetBasis;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * prime) & 0xFFFFFFFF;
    }
    return hash;
  }

  String _nextId() {
    final value = _counter++;
    return _encodeBase36(value);
  }

  static const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

  String _encodeBase36(int value) {
    if (value == 0) return '0';
    var current = value;
    final buffer = StringBuffer();
    while (current > 0) {
      final index = current % 36;
      buffer.write(_alphabet[index]);
      current = current ~/ 36;
    }
    final result = buffer.toString();
    return String.fromCharCodes(result.codeUnits.reversed.toList());
  }
}
