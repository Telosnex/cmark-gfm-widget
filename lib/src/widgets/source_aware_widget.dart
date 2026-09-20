import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'source_markdown_registry.dart';

/// Attaches structural identity to rendered content. Ordinary selection-copy
/// uses it for boundaries while retaining the actual selected leaf text.
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
  void updateRenderObject(
      BuildContext context, RenderSourceAware renderObject) {
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

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    SourceMarkdownRegistry.instance.register(this, _attachment);
  }

  @override
  void detach() {
    SourceMarkdownRegistry.instance.unregister(this);
    super.detach();
  }
}
