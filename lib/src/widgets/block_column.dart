import 'package:flutter/widgets.dart';

import '../theme/cmark_theme.dart';

/// Lays out the top-level blocks of a document, such as the widgets from
/// `RenderPipeline.render`.
///
/// It puts [CmarkThemeData.blockSpacing] between blocks and none after the
/// last one. The renderers give a block no space of its own, so use this
/// widget, or the same spacing, for any column of rendered blocks.
class CmarkBlockColumn extends StatelessWidget {
  const CmarkBlockColumn({
    super.key,
    required this.theme,
    required this.children,
  });

  /// The theme the blocks were rendered with.
  final CmarkThemeData theme;

  /// The rendered blocks, in document order.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: theme.blockSpacing,
      children: children,
    );
  }
}
