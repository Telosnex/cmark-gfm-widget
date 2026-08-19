final _htmlLineBreakPattern = RegExp(
  r'^<br\s*/?>$',
  caseSensitive: false,
);

/// Whether [literal] is a bare HTML line-break tag.
///
/// Arbitrary inline HTML remains literal text in the widget renderer. A bare
/// `<br>` is handled specially because it is the standard GFM mechanism for a
/// line break in places where a Markdown newline is structural, such as a
/// table cell.
bool isHtmlLineBreak(String literal) => _htmlLineBreakPattern.hasMatch(literal);

/// Returns the visible plain text represented by an inline HTML node.
String inlineHtmlPlainText(String literal) =>
    isHtmlLineBreak(literal) ? '\n' : literal;
