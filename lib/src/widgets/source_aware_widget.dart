import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'source_markdown_registry.dart';

/// Wraps a widget with its original markdown source for intelligent copy/paste.
/// 
/// When this widget is selected and copied, the patched SelectionArea will
/// extract the markdown source instead of the rendered text.
class SourceAwareWidget extends SingleChildRenderObjectWidget {
  const SourceAwareWidget({
    super.key,
    required this.attachment,
    required super.child,
  });

  final MarkdownSourceAttachment attachment;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderSourceAware(attachment: attachment);
  }

  @override
  void updateRenderObject(BuildContext context, RenderSourceAware renderObject) {
    renderObject.attachment = attachment;
  }
}

class RenderSourceAware extends RenderProxyBox {
  RenderSourceAware({required MarkdownSourceAttachment attachment})
      : _attachment = attachment {
    SourceMarkdownRegistry.instance.register(this, attachment);
  }

  MarkdownSourceAttachment _attachment;
  MarkdownSourceAttachment get attachment => _attachment;
  set attachment(MarkdownSourceAttachment value) {
    if (_attachment == value) {
      return;
    }
    _attachment = value;
    SourceMarkdownRegistry.instance.register(this, value);
  }
}
