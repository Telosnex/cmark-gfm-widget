import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:cmark_gfm_widget/src/render/block_renderers.dart';
import 'package:flutter/material.dart';

/// Helper to create a minimal rendering context for tests
BlockRenderContext createTestBlockContext({
  CmarkThemeData? theme,
  bool selectable = true,
}) {
  final effectiveTheme = theme ?? CmarkThemeData.fallback(ThemeData().textTheme);
  
  return BlockRenderContext(
    theme: effectiveTheme,
    inlineContext: InlineRenderContext(
      theme: effectiveTheme,
      textScaleFactor: 1.0,
    ),
    selectable: selectable,
    textScaleFactor: 1.0,
    renderFootnoteDefinitions: false,
    tableOptions: const TableRenderOptions(),
    codeBlockWrapper: null,
    mathBlockBuilder: null,
  );
}


/// Helper to parse and render markdown, returning BlockRenderResults with sources
List<BlockRenderResult> renderMarkdownBlocks(String markdown, {bool selectable = true}) {
  final controller = ParserController();
  final snapshot = controller.parse(markdown);
  final context = createTestBlockContext(selectable: selectable);
  
  return renderDocumentBlocks(snapshot, const [], context);
}

/// Converts rendered blocks into a deterministic, human-readable string that
/// can be compared against golden expectations in tests.
String renderResultsToString(
  List<BlockRenderResult> results, {
  DiagnosticLevel minDiagnosticLevel = DiagnosticLevel.info,
}) {
  final buffer = StringBuffer();
  for (final result in results) {
    buffer.writeln('block: ${result.id}');
    buffer.writeln(
      result.widget.toStringDeep(minLevel: minDiagnosticLevel).trimRight(),
    );
    buffer.writeln();
  }
  return buffer.toString().trimRight();
}

/// Convenience wrapper to parse markdown, render it, and stringify the widget
/// tree in one call.
String renderMarkdownToDebugString(
  String markdown, {
  bool selectable = true,
  DiagnosticLevel minDiagnosticLevel = DiagnosticLevel.info,
}) {
  final results = renderMarkdownBlocks(markdown, selectable: selectable);
  return renderResultsToString(
    results,
    minDiagnosticLevel: minDiagnosticLevel,
  );
}
