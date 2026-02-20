import 'package:flutter/rendering.dart';
import 'package:pixel_snap/material.dart';

class InlineMathSelectable extends StatelessWidget {
  const InlineMathSelectable({
    super.key, 
    required this.literal,
    required this.child,
  });

  final String literal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (literal.isEmpty) {
      return child;
    }

    final registrar = SelectionContainer.maybeOf(context);
    if (registrar == null) {
      return child;
    }

    final selectionColor =
        DefaultSelectionStyle.of(context).selectionColor ??
        const Color(0x6633B5E5);

    return _InlineMathSelectableRenderObject(
      literal: literal,
      selectionColor: selectionColor,
      registrar: registrar,
      child: child,
    );
  }
}

class _InlineMathSelectableRenderObject extends SingleChildRenderObjectWidget {
  const _InlineMathSelectableRenderObject({
    required this.literal,
    required this.selectionColor,
    required this.registrar,
    required super.child,
  });

  final String literal;
  final Color selectionColor;
  final SelectionRegistrar registrar;

  @override
  _RenderInlineMathSelectable createRenderObject(BuildContext context) {
    return _RenderInlineMathSelectable(
      literal: literal,
      selectionColor: selectionColor,
      registrar: registrar,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderInlineMathSelectable renderObject,
  ) {
    renderObject
      ..literal = literal
      ..selectionColor = selectionColor
      ..registrar = registrar;
  }
}

class _RenderInlineMathSelectable extends RenderProxyBox
    with Selectable, SelectionRegistrant {
  _RenderInlineMathSelectable({
    required String literal,
    required Color selectionColor,
    required SelectionRegistrar registrar,
  }) : _literal = literal,
       _selectionColor = selectionColor,
       _geometry = ValueNotifier<SelectionGeometry>(_noSelection) {
    this.registrar = registrar;
    _geometry.addListener(markNeedsPaint);
  }

  static const SelectionGeometry _noSelection = SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: true,
  );

  final ValueNotifier<SelectionGeometry> _geometry;

  String _literal;
  set literal(String value) {
    if (_literal == value) {
      return;
    }
    _literal = value;
  }

  Color get selectionColor => _selectionColor;
  Color _selectionColor;
  set selectionColor(Color value) {
    if (_selectionColor == value) {
      return;
    }
    _selectionColor = value;
    markNeedsPaint();
  }

  @override
  void addListener(VoidCallback listener) => _geometry.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _geometry.removeListener(listener);

  @override
  SelectionGeometry get value => _geometry.value;

  @override
  List<Rect> get boundingBoxes => <Rect>[paintBounds];

  static const double _handlePadding = 2.0;
  Rect _selectionRect() {
    return Rect.fromLTWH(
      -_handlePadding,
      -_handlePadding,
      size.width + _handlePadding * 2,
      size.height + _handlePadding * 2,
    );
  }

  Offset? _start;
  Offset? _end;
  void _updateGeometry() {
    if (_start == null || _end == null) {
      _geometry.value = _noSelection;
      return;
    }

    final renderObjectRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final selectionRect = Rect.fromPoints(_start!, _end!);
    if (renderObjectRect.intersect(selectionRect).isEmpty) {
      _geometry.value = _noSelection;
      return;
    }

    final highlightRect = _selectionRect();
    final startPoint = SelectionPoint(
      localPosition: highlightRect.bottomLeft,
      lineHeight: highlightRect.height,
      handleType: TextSelectionHandleType.left,
    );
    final endPoint = SelectionPoint(
      localPosition: highlightRect.bottomRight,
      lineHeight: highlightRect.height,
      handleType: TextSelectionHandleType.right,
    );

    final bool isReversed;
    if (_start!.dy > _end!.dy) {
      isReversed = true;
    } else if (_start!.dy < _end!.dy) {
      isReversed = false;
    } else {
      isReversed = _start!.dx > _end!.dx;
    }

    _geometry.value = SelectionGeometry(
      status: SelectionStatus.uncollapsed,
      hasContent: true,
      startSelectionPoint: isReversed ? endPoint : startPoint,
      endSelectionPoint: isReversed ? startPoint : endPoint,
      selectionRects: <Rect>[highlightRect],
    );
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    SelectionResult result = SelectionResult.none;
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        final renderObjectRect = Rect.fromLTWH(0, 0, size.width, size.height);
        final point = globalToLocal(
          (event as SelectionEdgeUpdateEvent).globalPosition,
        );
        final adjustedPoint = SelectionUtils.adjustDragOffset(
          renderObjectRect,
          point,
        );
        if (event.type == SelectionEventType.startEdgeUpdate) {
          _start = adjustedPoint;
        } else {
          _end = adjustedPoint;
        }
        result = SelectionUtils.getResultBasedOnRect(renderObjectRect, point);
      case SelectionEventType.clear:
        _start = _end = null;
      case SelectionEventType.selectAll:
      case SelectionEventType.selectWord:
      case SelectionEventType.selectParagraph:
        _start = Offset.zero;
        _end = Offset.infinite;
      case SelectionEventType.granularlyExtendSelection:
        result = SelectionResult.end;
        final extendSelectionEvent =
            event as GranularlyExtendSelectionEvent;
        if (_start == null || _end == null) {
          if (extendSelectionEvent.forward) {
            _start = _end = Offset.zero;
          } else {
            _start = _end = Offset.infinite;
          }
        }
        final Offset newOffset = extendSelectionEvent.forward
            ? Offset.infinite
            : Offset.zero;
        if (extendSelectionEvent.isEnd) {
          if (newOffset == _end) {
            result = extendSelectionEvent.forward
                ? SelectionResult.next
                : SelectionResult.previous;
          }
          _end = newOffset;
        } else {
          if (newOffset == _start) {
            result = extendSelectionEvent.forward
                ? SelectionResult.next
                : SelectionResult.previous;
          }
          _start = newOffset;
        }
      case SelectionEventType.directionallyExtendSelection:
        result = SelectionResult.end;
        final extendSelectionEvent =
            event as DirectionallyExtendSelectionEvent;
        final double horizontalBaseLine =
            globalToLocal(Offset(event.dx, 0)).dx;
        late final Offset newOffset;
        late final bool forward;
        switch (extendSelectionEvent.direction) {
          case SelectionExtendDirection.backward:
          case SelectionExtendDirection.previousLine:
            forward = false;
            if (_start == null || _end == null) {
              _start = _end = Offset.infinite;
            }
            if (extendSelectionEvent.direction ==
                    SelectionExtendDirection.previousLine ||
                horizontalBaseLine < 0) {
              newOffset = Offset.zero;
            } else {
              newOffset = Offset.infinite;
            }
          case SelectionExtendDirection.nextLine:
          case SelectionExtendDirection.forward:
            forward = true;
            if (_start == null || _end == null) {
              _start = _end = Offset.zero;
            }
            if (extendSelectionEvent.direction ==
                    SelectionExtendDirection.nextLine ||
                horizontalBaseLine > size.width) {
              newOffset = Offset.infinite;
            } else {
              newOffset = Offset.zero;
            }
        }
        if (extendSelectionEvent.isEnd) {
          if (newOffset == _end) {
            result = forward ? SelectionResult.next : SelectionResult.previous;
          }
          _end = newOffset;
        } else {
          if (newOffset == _start) {
            result = forward ? SelectionResult.next : SelectionResult.previous;
          }
          _start = newOffset;
        }
    }
    _updateGeometry();
    return result;
  }

  @override
  SelectedContent? getSelectedContent() {
    return value.hasSelection
        ? SelectedContent(plainText: _literal)
        : null;
  }

  @override
  SelectedContentRange? getSelection() {
    if (!value.hasSelection) {
      return null;
    }
    return SelectedContentRange(startOffset: 0, endOffset: _literal.length);
  }

  @override
  int get contentLength => _literal.length;

  LayerLink? _startHandle;
  LayerLink? _endHandle;

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (_startHandle == startHandle && _endHandle == endHandle) {
      return;
    }
    _startHandle = startHandle;
    _endHandle = endHandle;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!_geometry.value.hasSelection) {
      return;
    }
    final selectionPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = _selectionColor;
    context.canvas.drawRect(
      _selectionRect().shift(offset),
      selectionPaint,
    );

    if (_startHandle != null) {
      context.pushLayer(
        LeaderLayer(
          link: _startHandle!,
          offset: offset + value.startSelectionPoint!.localPosition,
        ),
        (PaintingContext context, Offset offset) {},
        Offset.zero,
      );
    }
    if (_endHandle != null) {
      context.pushLayer(
        LeaderLayer(
          link: _endHandle!,
          offset: offset + value.endSelectionPoint!.localPosition,
        ),
        (PaintingContext context, Offset offset) {},
        Offset.zero,
      );
    }
  }

  @override
  void dispose() {
    _geometry.dispose();
    _startHandle = null;
    _endHandle = null;
    super.dispose();
  }
}
