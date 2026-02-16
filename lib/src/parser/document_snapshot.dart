import 'package:cmark_gfm/cmark_gfm.dart';

import 'stable_id_registry.dart';

/// Immutable representation of a parsed Markdown document.
class DocumentSnapshot {
  DocumentSnapshot._({
    required this.root,
    required this.revision,
  });

  /// Root node of the document (always of type [CmarkNodeType.document]).
  final CmarkNode root;

  /// Snapshot revision (monotonic counter assigned by the controller).
  final int revision;

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
  }) {
    _assignMetadata(root, registry, revision);
    registry.prune(revision - 1);
    return DocumentSnapshot._(
      root: root,
      revision: revision,
    );
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
}
