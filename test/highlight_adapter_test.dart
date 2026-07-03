import 'package:cmark_gfm_widget/src/highlight/highlight_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _theme = <String, TextStyle>{
  'root': TextStyle(color: Color(0xFFABB2BF)),
  'keyword': TextStyle(color: Color(0xFFC678DD)),
  'string': TextStyle(color: Color(0xFF98C379)),
  'comment': TextStyle(color: Color(0xFF5C6370), fontStyle: FontStyle.italic),
  'number': TextStyle(color: Color(0xFFD19A66)),
  'title': TextStyle(color: Color(0xFF61AFEF)),
  'built_in': TextStyle(color: Color(0xFFE6C07B)),
};

const _base = TextStyle(fontFamily: 'monospace', fontSize: 14);

HighlightedCodeLines _build(HighlightAdapter adapter, String code, String? language) {
  return adapter.buildLines(
    code: code,
    baseStyle: _base,
    theme: _theme,
    autoDetectLanguage: false,
    language: language,
    fallbackStyle: _base,
    tabSize: 2,
  );
}

/// Flattens line spans into comparable (text, style) runs per line.
List<List<(String, TextStyle?)>> _flatten(HighlightedCodeLines highlighted) {
  List<(String, TextStyle?)> flattenSpan(InlineSpan span) {
    final runs = <(String, TextStyle?)>[];
    span.visitChildren((child) {
      if (child is TextSpan && child.text != null && child.text!.isNotEmpty) {
        runs.add((child.text!, child.style));
      }
      return true;
    });
    return runs;
  }

  return highlighted.lines.map(flattenSpan).toList();
}

String _plainText(HighlightedCodeLines highlighted) {
  return highlighted.lines
      .map((line) => line.toPlainText())
      .join('\n');
}

/// Streams [code] into [adapter] in chunks of [chunkSize], returning the
/// final result.
HighlightedCodeLines _stream(
  HighlightAdapter adapter,
  String code,
  String? language, {
  int chunkSize = 3,
}) {
  HighlightedCodeLines? result;
  for (var end = 1; end <= code.length; end += chunkSize) {
    final upper = end > code.length ? code.length : end;
    result = _build(adapter, code.substring(0, upper), language);
  }
  // Ensure the final full text was built.
  result = _build(adapter, code, language);
  return result;
}

void main() {
  const dartCode = '''
/// Doc comment.
class Foo {
  /* multi
     line
     comment */
  final String bar = "hello \${world}";

  int add(int a, int b) {
    // line comment
    return a + b + 42;
  }
}''';

  const pythonCode = '''
def greet(name):
    """Docstring
    spanning lines."""
    total = 1 + 2.5
    return f"hello {name}"''';

  const jsCode = '''
const x = `template
spanning \${lines}`;
// trailing comment
function f() { return /re.?gex/; }''';

  const xmlCode = '''
<root attr="value">
  <!-- comment
       spanning lines -->
  <child>text</child>
</root>''';

  group('HighlightAdapter incremental highlighting', () {
    for (final (name, code, language) in [
      ('dart', dartCode, 'dart'),
      ('python', pythonCode, 'python'),
      ('javascript', jsCode, 'javascript'),
      ('xml', xmlCode, 'xml'),
      ('plaintext', dartCode, 'plaintext'),
      ('unknown language', dartCode, 'no-such-language'),
      ('null language', dartCode, null),
    ]) {
      test('streamed output matches one-shot output ($name)', () {
        final streamed = _stream(HighlightAdapter(), code, language);
        final oneShot = _build(HighlightAdapter(), code, language);

        expect(_plainText(streamed), code);
        expect(_plainText(oneShot), code);
        expect(_flatten(streamed), _flatten(oneShot));
      });
    }

    test('completed line spans are identical instances across appends', () {
      final adapter = HighlightAdapter();
      final first = _build(adapter, 'void main() {\n  print("hi");', 'dart');
      final second = _build(adapter, 'void main() {\n  print("hi");\n}', 'dart');
      final third = _build(adapter, 'void main() {\n  print("hi");\n}\n// done', 'dart');

      // Line 0 completed in the first build and must stay the same instance.
      expect(identical(first.lines[0], second.lines[0]), isTrue);
      expect(identical(second.lines[0], third.lines[0]), isTrue);
      // Line 1 completed in the second build.
      expect(identical(second.lines[1], third.lines[1]), isTrue);
      // Line 2 completed in the third build.
      expect(identical(second.lines[2], third.lines[2]), isFalse);
    });

    test('multi-line constructs keep continuation state across chunks', () {
      final adapter = HighlightAdapter();
      // Stream so the comment opener and closer arrive in separate builds.
      _build(adapter, '/* comment\n', 'dart');
      final result = _build(adapter, '/* comment\nstill comment\n*/ final x = 1;', 'dart');

      // The second line is inside the block comment and must be styled as one.
      final secondLineRuns = _flatten(result)[1];
      expect(secondLineRuns, hasLength(1));
      expect(secondLineRuns.single.$2?.color, _theme['comment']!.color);
    });

    test('non-append edits fall back to a correct full parse', () {
      final adapter = HighlightAdapter();
      _build(adapter, 'final a = 1;\nfinal b = 2;\n', 'dart');
      // Rewrite history: not an append of the previous text.
      const edited = 'const x = "y";\nconst z = 3;';
      final result = _build(adapter, edited, 'dart');
      final oneShot = _build(HighlightAdapter(), edited, 'dart');

      expect(_plainText(result), edited);
      expect(_flatten(result), _flatten(oneShot));
    });

    test('empty and whitespace-only code render a single empty line', () {
      final adapter = HighlightAdapter();
      expect(_build(adapter, '', 'dart').lines, hasLength(1));
      expect(_build(adapter, '\n\n', 'dart').lines, hasLength(1));
    });

    test('trailing whitespace after newline becomes its own line', () {
      final adapter = HighlightAdapter();
      final result = _build(adapter, 'a\n  ', 'dart');
      expect(result.lines, hasLength(2));
      expect(result.lines[0].toPlainText(), 'a');
      expect(result.lines[1].toPlainText(), '  ');
    });

    test('exact repeats are served from cache with identical instances', () {
      final adapter = HighlightAdapter();
      const code = 'final a = 1;\nfinal b = 2;';
      final first = _build(adapter, code, 'dart');
      final second = _build(adapter, code, 'dart');
      expect(identical(first, second), isTrue);
    });

    test('lines never contain newline characters', () {
      final result = _stream(HighlightAdapter(), dartCode, 'dart');
      for (final line in result.lines) {
        expect(line.toPlainText().contains('\n'), isFalse);
      }
    });
  });
}
