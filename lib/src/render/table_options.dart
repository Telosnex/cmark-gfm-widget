import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter/widgets.dart';

import '../theme/cmark_theme.dart';

/// Configuration options for rendering tables.
class TableRenderOptions {
  const TableRenderOptions({
    this.defaultColumnWidth,
    this.columnWidths,
    this.wrapper,
  });

  /// Overrides the table's [Table.defaultColumnWidth].
  final TableColumnWidth? defaultColumnWidth;

  /// Overrides [Table.columnWidths].
  final Map<int, TableColumnWidth>? columnWidths;

  /// Optional wrapper invoked with the built table widget and metadata.
  final TableWrapperBuilder? wrapper;
}

/// Contextual information provided to [TableWrapperBuilder].
class TableWrapperContext {
  const TableWrapperContext({
    required this.theme,
    required this.selectable,
    required this.textScaleFactor,
  });

  final CmarkThemeData theme;
  final bool selectable;
  final double textScaleFactor;
}

/// Metadata describing the table contents.
class TableRenderMetadata {
  TableRenderMetadata({
    required this.node,
    required this.alignments,
    required this.header,
    required this.rows,
  });

  /// The original table node.
  final CmarkNode node;

  /// Column alignments as declared in the Markdown document.
  final List<CmarkTableAlign> alignments;

  /// Header row cell text, if present.
  final List<String>? header;

  /// Data rows (excluding the header).
  final List<List<String>> rows;

  /// All rows, including the header when available.
  List<List<String>> get rowsIncludingHeader =>
      header == null ? rows : [header!, ...rows];
}

/// Signature used to wrap rendered tables with additional UI.
typedef TableWrapperBuilder = Widget Function(
  Widget table,
  TableRenderMetadata metadata,
  TableWrapperContext context,
);
