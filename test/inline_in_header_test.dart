import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  test('paragraph renders the expected widget tree', () {
    const markdown = '# A `B` C';

    final actual = renderMarkdownToDebugString(
      markdown,
      selectable: true,
      minDiagnosticLevel: DiagnosticLevel.hidden,
    );

    // SourceAwareWidget wraps the heading but doesn't expose child in toStringDeep()
    // at DiagnosticLevel.hidden. The important thing is the source is captured.
    const expected = 'block: 1\n'
        'source: "# A `B` C"\n'
        'SourceAwareWidget';

    expect(actual, expected);
  });
}
