import 'package:flutter/widgets.dart';

import '../parser/document_snapshot.dart';
import '../theme/cmark_theme.dart';
import 'block_renderers.dart';
import 'inline_renderers.dart';

class RenderOptions {
  const RenderOptions({
    this.selectable = false,
    this.textScaleFactor = 1.0,
    this.footnoteReferenceBuilder,
  });

  final bool selectable;
  final double textScaleFactor;
  final FootnoteReferenceSpanBuilder? footnoteReferenceBuilder;
}

class RenderPipeline {
  const RenderPipeline();

  List<BlockRenderResult> render(
    DocumentSnapshot snapshot,
    CmarkThemeData theme,
    RenderOptions options,
  ) {
    final inlineContext = InlineRenderContext(
      theme: theme,
      textScaleFactor: options.textScaleFactor,
      footnoteReferenceBuilder: options.footnoteReferenceBuilder,
    );
    final blockContext = BlockRenderContext(
      theme: theme,
      inlineContext: inlineContext,
      selectable: options.selectable,
      textScaleFactor: options.textScaleFactor,
    );

    return renderDocumentBlocks(snapshot, blockContext);
  }

  List<Widget> buildWidgets(
    DocumentSnapshot snapshot,
    CmarkThemeData theme,
    RenderOptions options,
  ) {
    final entries = render(snapshot, theme, options);
    return entries
        .map(
          (entry) => KeyedSubtree(
            key: ValueKey<String>(entry.id),
            child: entry.widget,
          ),
        )
        .toList(growable: false);
  }
}
