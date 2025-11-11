import 'package:cmark_gfm/cmark_gfm.dart';

import 'document_snapshot.dart';
import 'stable_id_registry.dart';

/// High-level controller that coordinates parsing and snapshot creation.
class ParserController {
  ParserController({
    StableIdRegistry? registry,
    CmarkParserOptions parserOptions = const CmarkParserOptions(),
  })  : _registry = registry ?? StableIdRegistry(),
        _parserOptions = parserOptions;

  final StableIdRegistry _registry;
  final CmarkParserOptions _parserOptions;
  int _revision = 0;

  /// Parses [data] and returns a fresh [DocumentSnapshot].
  DocumentSnapshot parse(String data) {
    final parser = CmarkParser(options: _parserOptions);
    parser.feed(data);
    final root = parser.finish();
    _revision += 1;
    return DocumentSnapshot.fromRoot(
      root: root,
      registry: _registry,
      revision: _revision,
    );
  }

  /// Parses a sequence of [chunks], useful for streaming input.
  DocumentSnapshot parseChunks(Iterable<String> chunks) {
    final parser = CmarkParser(options: _parserOptions);
    for (final chunk in chunks) {
      parser.feed(chunk);
    }
    final root = parser.finish();
    _revision += 1;
    return DocumentSnapshot.fromRoot(
      root: root,
      registry: _registry,
      revision: _revision,
    );
  }
}
