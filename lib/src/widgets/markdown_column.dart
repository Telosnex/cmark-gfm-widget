import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:pixel_snap/material.dart';

import '../parser/document_snapshot.dart';
import '../parser/parser_controller.dart';
import '../theme/cmark_theme.dart';
import '../render/render_pipeline.dart';

/// Renders Markdown as a [Column] of widgets.
class CmarkMarkdownColumn extends StatefulWidget {
  const CmarkMarkdownColumn({
    super.key,
    this.data,
    this.snapshot,
    this.controller,
    this.theme,
    this.padding = EdgeInsets.zero,
    this.selectable = false,
    this.textScaleFactor,
    this.parserOptions = const CmarkParserOptions(enableMath: true),
  }) : assert(
         (data != null) ^ (snapshot != null),
         'Provide either data or snapshot.',
       );

  /// Raw Markdown input.
  final String? data;

  /// Precomputed snapshot that bypasses parsing when provided.
  final DocumentSnapshot? snapshot;

  /// Optional shared parser controller to reuse stable identifiers.
  final ParserController? controller;

  /// Theme overrides for rendering.
  final CmarkThemeData? theme;

  /// Padding applied around the generated column.
  final EdgeInsetsGeometry padding;

  /// Whether text widgets should be selectable.
  final bool selectable;

  /// Overrides the effective text scale factor.
  final double? textScaleFactor;

  /// Parser configuration used when creating an internal [ParserController].
  final CmarkParserOptions parserOptions;

  @override
  State<CmarkMarkdownColumn> createState() => _CmarkMarkdownColumnState();
}

class _CmarkMarkdownColumnState extends State<CmarkMarkdownColumn> {
  late ParserController _controller;
  bool _ownsController = false;
  DocumentSnapshot? _snapshot;
  String? _lastData;
  final RenderPipeline _pipeline = const RenderPipeline();

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        ParserController(parserOptions: widget.parserOptions);
    _recomputeSnapshot(force: true);
  }

  @override
  void didUpdateWidget(covariant CmarkMarkdownColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    var controllerChanged = false;
    if (widget.controller != oldWidget.controller) {
      if (_ownsController && widget.controller != null) {
        // Original controller becomes unused; nothing to dispose.
      }
      if (widget.controller != null) {
        _controller = widget.controller!;
        _ownsController = false;
        controllerChanged = true;
      } else if (oldWidget.controller != null) {
        _controller = ParserController(parserOptions: widget.parserOptions);
        _ownsController = true;
        controllerChanged = true;
      }
    }

    if (_ownsController &&
        widget.parserOptions != oldWidget.parserOptions) {
      _controller = ParserController(parserOptions: widget.parserOptions);
      controllerChanged = true;
    }

    final dataChanged = widget.data != oldWidget.data;
    final snapshotChanged = widget.snapshot != oldWidget.snapshot;

    if (dataChanged || snapshotChanged || controllerChanged) {
      _recomputeSnapshot(force: true);
    }
  }

  void _recomputeSnapshot({bool force = false}) {
    if (widget.snapshot != null) {
      _snapshot = widget.snapshot;
      _lastData = null;
      return;
    }

    final data = widget.data;
    if (data == null) {
      _snapshot = null;
      _lastData = null;
      return;
    }

    if (!force && _lastData == data) {
      return;
    }

    _snapshot = _controller.parse(data);
    _lastData = data;
  }

  @override
  Widget build(BuildContext context) {
    _recomputeSnapshot();

    final snapshot = widget.snapshot ?? _snapshot;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }

    final inheritedTheme = CmarkTheme.maybeOf(context);
    final theme =
        widget.theme ??
        inheritedTheme ??
        CmarkThemeData.fallback(Theme.of(context).textTheme);
    final textScale =
        widget.textScaleFactor ??
        1.0;

    final options = RenderOptions(
      selectable: widget.selectable,
      textScaleFactor: textScale,
    );

    final children = _pipeline.buildWidgets(snapshot, theme, options);

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );

    final content = widget.selectable ? SelectionArea(child: column) : column;

    return Padding(padding: widget.padding, child: content);
  }

  @override
  void dispose() {
    if (_ownsController) {
      // No resources to release currently.
    }
    super.dispose();
  }
}

/// Convenience widget that renders selectable text by default.
class SelectableCmarkMarkdownColumn extends StatelessWidget {
  const SelectableCmarkMarkdownColumn({
    super.key,
    this.data,
    this.snapshot,
    this.controller,
    this.theme,
    this.padding = EdgeInsets.zero,
    this.textScaleFactor,
    this.parserOptions = const CmarkParserOptions(enableMath: true),
  });

  final String? data;
  final DocumentSnapshot? snapshot;
  final ParserController? controller;
  final CmarkThemeData? theme;
  final EdgeInsetsGeometry padding;
  final double? textScaleFactor;
  final CmarkParserOptions parserOptions;

  @override
  Widget build(BuildContext context) {
    return CmarkMarkdownColumn(
      data: data,
      snapshot: snapshot,
      controller: controller,
      theme: theme,
      padding: padding,
      selectable: true,
      textScaleFactor: textScaleFactor,
      parserOptions: parserOptions,
    );
  }
}
