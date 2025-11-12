import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [SelectionContainerDelegate] that adds line breaks between selected children.
///
/// This fixes the Flutter framework bug where SelectionArea concatenates
/// selected text from multiple widgets without any separator.
/// See: https://github.com/flutter/flutter/issues/104548
class LineBreakAwareSelectionDelegate extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final List<SelectedContent> selections = <SelectedContent>[
      for (final Selectable selectable in selectables)
        if (selectable.getSelectedContent() case final SelectedContent data) data,
    ];
    if (selections.isEmpty) {
      return null;
    }
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < selections.length; i++) {
      buffer.write(selections[i].plainText);
      // Add line break between selections (but not after the last one)
      if (i < selections.length - 1) {
        buffer.write('\n');
      }
    }
    return SelectedContent(plainText: buffer.toString());
  }
}
