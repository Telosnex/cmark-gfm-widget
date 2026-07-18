import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Marks a subtree as a "Select All" boundary for an enclosing
/// [SelectionArea]/SelectableRegion from this package.
///
/// Only the Select All intent (Cmd/Ctrl+A and the context menu action) is
/// confined to the scope that received the most recent pointer down; drag
/// selection is unaffected and may still cross scopes freely, and edge-drag
/// autoscroll keeps working because the enclosing region and its scrollable
/// remain the selection owners.
///
/// When no scope contains the most recent pointer down (or no pointer down
/// happened yet), Select All falls back to selecting the whole region.
class SelectionScope extends SingleChildRenderObjectWidget {
  const SelectionScope({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSelectionScope();
}

/// Render object for [SelectionScope]; a pure marker in the hit-test path.
class RenderSelectionScope extends RenderProxyBox {}
