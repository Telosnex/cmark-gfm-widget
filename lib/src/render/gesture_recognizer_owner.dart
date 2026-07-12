import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Owns the disposal lifecycle of a batch of [GestureRecognizer]s that were
/// attached directly to [TextSpan]s inside [child] (currently: link tap
/// recognizers - see [InlineRenderContext.withLinkRecognizerSink] in
/// `inline_renderers.dart`).
///
/// [TextSpan] is a plain value object with no lifecycle of its own, so
/// nothing disposes a recognizer attached to one automatically. This widget
/// bridges that gap using the owning [Element]'s lifecycle:
///  - When [child]'s span tree is rebuilt with a *new* batch of recognizers
///    (a new [recognizers] list instance), the *previous* batch is disposed
///    in [didUpdateWidget], right before the new tree replaces it.
///  - When this widget is removed from the tree entirely, the current batch
///    is disposed in [dispose].
///
/// Callers must pass a fresh `List<GestureRecognizer>` each time they render
/// a new span tree (identity is used to detect "this is a new batch");
/// mutating a previously-passed list in place will not trigger disposal.
class GestureRecognizerOwner extends StatefulWidget {
  const GestureRecognizerOwner({
    super.key,
    required this.recognizers,
    required this.child,
  });

  final List<GestureRecognizer> recognizers;
  final Widget child;

  @override
  State<GestureRecognizerOwner> createState() =>
      _GestureRecognizerOwnerState();
}

class _GestureRecognizerOwnerState extends State<GestureRecognizerOwner> {
  @override
  void didUpdateWidget(covariant GestureRecognizerOwner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.recognizers, widget.recognizers)) {
      for (final recognizer in oldWidget.recognizers) {
        recognizer.dispose();
      }
    }
  }

  @override
  void dispose() {
    for (final recognizer in widget.recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
