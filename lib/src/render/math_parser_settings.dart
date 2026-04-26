import 'package:flutter_math_fork/flutter_math.dart';

Strict cmarkMathStrictFun(
  String errorCode,
  String errorMsg,
  Object? token,
) {
  // flutter_math_fork reports LaTeX-incompatible input via the strict
  // mechanism before building widgets. Unknown Unicode symbols (often emoji
  // from prose/logs accidentally parsed as math) can otherwise still be laid
  // out and produce pathological, unbreakable math lines. Promote only that
  // signal to a parse error so Math.tex uses onErrorFallback, while preserving
  // flutter_math_fork's default warn behavior for less severe compatibility
  // warnings like supported Unicode text in math mode.
  return errorCode == 'unknownSymbol' ? Strict.error : Strict.warn;
}

const cmarkMathParserSettings = TexParserSettings(
  strictFun: cmarkMathStrictFun,
);
