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
    required this.sourceMarkdown,
    required super.child,
  });

  final String sourceMarkdown;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderSourceAware(sourceMarkdown: sourceMarkdown);
  }
  
  @override
  void updateRenderObject(BuildContext context, RenderSourceAware renderObject) {
    renderObject.sourceMarkdown = sourceMarkdown;
  }
}

class RenderSourceAware extends RenderProxyBox {
  RenderSourceAware({required String sourceMarkdown}) : _sourceMarkdown = sourceMarkdown {
    // Register this RenderObject with its source
    SourceMarkdownRegistry.instance.register(this, sourceMarkdown);
  }
  
  String _sourceMarkdown;
  String get sourceMarkdown => _sourceMarkdown;
  set sourceMarkdown(String value) {
    if (_sourceMarkdown != value) {
      _sourceMarkdown = value;
      // Re-register with new source
      SourceMarkdownRegistry.instance.register(this, value);
    }
  }
}
