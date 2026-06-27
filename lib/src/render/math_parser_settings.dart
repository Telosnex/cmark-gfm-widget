import 'package:flutter_math_fork/flutter_math.dart';

final _unicodeCodePattern = RegExp(r'\((\d+)\)');

Strict cmarkMathStrictFun(
  String errorCode,
  String errorMsg,
  Object? token,
) {
  if (errorCode != 'unknownSymbol') {
    return Strict.warn;
  }

  final codePointMatch = _unicodeCodePattern.firstMatch(errorMsg);
  final codePoint = codePointMatch == null
      ? null
      : int.tryParse(codePointMatch.group(1) ?? '');

  // flutter_math_fork reports LaTeX-incompatible input via the strict
  // mechanism before building widgets. Unknown non-Latin-1 Unicode symbols
  // (often emoji from prose/logs accidentally parsed as math) can otherwise
  // still be laid out and produce pathological, unbreakable math lines.
  // Promote those to parse errors so Math.tex uses onErrorFallback.
  //
  // Keep Latin-1 unknown symbols as warnings so unit text like `cd/m²` inside
  // \text{...} still renders as LaTeX instead of falling back to plain text.
  if (codePoint == null || codePoint > 0xFF) {
    return Strict.error;
  }

  return Strict.warn;
}

const cmarkMathParserSettings = TexParserSettings(
  strictFun: cmarkMathStrictFun,
);
