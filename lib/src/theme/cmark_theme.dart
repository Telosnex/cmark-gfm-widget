import 'package:pixel_snap/material.dart';
import 'package:flutter_highlight/themes/a11y-dark.dart' as highlight_theme;

/// Configuration for syntax highlighting in code blocks.
class CodeHighlightTheme {
  const CodeHighlightTheme({
    this.theme = const {},
    this.autoDetectLanguage = true,
    this.defaultLanguage,
    this.fallbackStyle,
    this.tabSize = 2,
  });

  /// Mapping from highlight style class name to [TextStyle].
  final Map<String, TextStyle> theme;

  /// Whether highlight.js should auto-detect the language.
  ///
  /// When false, [defaultLanguage] or the code fence info string is used.
  final bool autoDetectLanguage;

  /// Default language used when auto-detection is disabled and the code block
  /// does not provide an info string.
  final String? defaultLanguage;

  /// Text style applied when a token does not match any class in [theme].
  final TextStyle? fallbackStyle;

  /// Number of spaces to use when replacing tab characters.
  final int tabSize;

  CodeHighlightTheme copyWith({
    Map<String, TextStyle>? theme,
    bool? autoDetectLanguage,
    String? defaultLanguage,
    TextStyle? fallbackStyle,
    int? tabSize,
  }) {
    return CodeHighlightTheme(
      theme: theme ?? this.theme,
      autoDetectLanguage: autoDetectLanguage ?? this.autoDetectLanguage,
      defaultLanguage: defaultLanguage ?? this.defaultLanguage,
      fallbackStyle: fallbackStyle ?? this.fallbackStyle,
      tabSize: tabSize ?? this.tabSize,
    );
  }
}

/// Styling configuration used by the renderer.
class CmarkThemeData {
  const CmarkThemeData({
    required this.paragraphTextStyle,
    required List<TextStyle> headingTextStyles,
    required this.codeSpanTextStyle,
    // Chosen on 25-11-16 based on IM Fell and Jet Brains Mono.
    this.inlineCodeFontScale = 0.85,
    required this.linkTextStyle,
    required this.emphasisTextStyle,
    required this.strongTextStyle,
    required this.strikethroughTextStyle,
    required this.thematicBreakColor,
    required this.thematicBreakThickness,
    required this.thematicBreakVerticalPadding,
    required this.blockSpacing,
    required this.blockQuoteBackgroundColor,
    required this.blockQuoteBorderColor,
    required this.blockQuotePadding,
    required this.codeBlockBackgroundColor,
    required this.codeBlockPadding,
    required this.codeBlockTextStyle,
    required this.listBulletGap,
    required this.orderedListIndent,
    required this.unorderedListIndent,
    required this.listItemSpacing,
    this.listItemBlockSpacing = EdgeInsets.zero,
    required this.orderedListBulletTextStyle,
    required this.unorderedListBulletTextStyle,
    required this.tableHeaderTextStyle,
    required this.tableBodyTextStyle,
    required this.tableCellPadding,
    required this.tableBorder,
    required this.footnoteLabelTextStyle,
    required this.codeHighlightTheme,
  }) : _headingTextStyles = headingTextStyles;

  final TextStyle paragraphTextStyle;
  final List<TextStyle> _headingTextStyles;
  final TextStyle codeSpanTextStyle;
  /// Multiplier applied to the surrounding font size for inline code spans.
  ///
  /// Values < 1.0 make code appear slightly smaller than the surrounding text,
  /// which often compensates for monospace glyphs appearing visually larger.
  final double inlineCodeFontScale;
  final TextStyle linkTextStyle;
  final TextStyle emphasisTextStyle;
  final TextStyle strongTextStyle;
  final TextStyle strikethroughTextStyle;
  final Color thematicBreakColor;
  final double thematicBreakThickness;
  final double thematicBreakVerticalPadding;
  final EdgeInsets blockSpacing;
  final Color blockQuoteBackgroundColor;
  final Color blockQuoteBorderColor;
  final EdgeInsets blockQuotePadding;
  final Color codeBlockBackgroundColor;
  final EdgeInsets codeBlockPadding;
  final TextStyle codeBlockTextStyle;
  final double listBulletGap;

  /// Returns the indentation for an ordered list at the given nesting [level].
  ///
  /// The provided [level] is 1-based, where the outermost list has level 1.
  final double Function(int level) orderedListIndent;

  /// Returns the indentation for an unordered list at the given nesting [level].
  ///
  /// The provided [level] is 1-based, where the outermost list has level 1.
  final double Function(int level) unorderedListIndent;
  final double listItemSpacing;
  final EdgeInsets listItemBlockSpacing;
  final TextStyle orderedListBulletTextStyle;
  final TextStyle unorderedListBulletTextStyle;
  final TextStyle tableHeaderTextStyle;
  final TextStyle tableBodyTextStyle;
  final EdgeInsets tableCellPadding;
  final TableBorder tableBorder;
  final TextStyle footnoteLabelTextStyle;
  final CodeHighlightTheme codeHighlightTheme;

  TextStyle headingTextStyle(int level) {
    final index = level.clamp(1, _headingTextStyles.length) - 1;
    return _headingTextStyles[index];
  }

  CmarkThemeData copyWith({
    TextStyle? paragraphTextStyle,
    List<TextStyle>? headingTextStyles,
    TextStyle? codeSpanTextStyle,
    double? inlineCodeFontScale,
    TextStyle? linkTextStyle,
    TextStyle? emphasisTextStyle,
    TextStyle? strongTextStyle,
    TextStyle? strikethroughTextStyle,
    Color? thematicBreakColor,
    double? thematicBreakThickness,
    double? thematicBreakVerticalPadding,
    EdgeInsets? blockSpacing,
    Color? blockQuoteBackgroundColor,
    Color? blockQuoteBorderColor,
    EdgeInsets? blockQuotePadding,
    Color? codeBlockBackgroundColor,
    EdgeInsets? codeBlockPadding,
    TextStyle? codeBlockTextStyle,
    double? listBulletGap,
    double Function(int level)? orderedListIndent,
    double Function(int level)? unorderedListIndent,
    double? listItemSpacing,
    EdgeInsets? listItemBlockSpacing,
    TextStyle? orderedListBulletTextStyle,
    TextStyle? unorderedListBulletTextStyle,
    TextStyle? tableHeaderTextStyle,
    TextStyle? tableBodyTextStyle,
    EdgeInsets? tableCellPadding,
    TableBorder? tableBorder,
    TextStyle? footnoteLabelTextStyle,
    CodeHighlightTheme? codeHighlightTheme,
  }) {
    return CmarkThemeData(
      paragraphTextStyle: paragraphTextStyle ?? this.paragraphTextStyle,
      headingTextStyles:
          headingTextStyles ?? List<TextStyle>.from(_headingTextStyles),
      codeSpanTextStyle: codeSpanTextStyle ?? this.codeSpanTextStyle,
      inlineCodeFontScale: inlineCodeFontScale ?? this.inlineCodeFontScale,
      linkTextStyle: linkTextStyle ?? this.linkTextStyle,
      emphasisTextStyle: emphasisTextStyle ?? this.emphasisTextStyle,
      strongTextStyle: strongTextStyle ?? this.strongTextStyle,
      strikethroughTextStyle:
          strikethroughTextStyle ?? this.strikethroughTextStyle,
      thematicBreakColor: thematicBreakColor ?? this.thematicBreakColor,
      thematicBreakThickness:
          thematicBreakThickness ?? this.thematicBreakThickness,
      thematicBreakVerticalPadding:
          thematicBreakVerticalPadding ?? this.thematicBreakVerticalPadding,
      blockSpacing: blockSpacing ?? this.blockSpacing,
      blockQuoteBackgroundColor:
          blockQuoteBackgroundColor ?? this.blockQuoteBackgroundColor,
      blockQuoteBorderColor:
          blockQuoteBorderColor ?? this.blockQuoteBorderColor,
      blockQuotePadding: blockQuotePadding ?? this.blockQuotePadding,
      codeBlockBackgroundColor:
          codeBlockBackgroundColor ?? this.codeBlockBackgroundColor,
      codeBlockPadding: codeBlockPadding ?? this.codeBlockPadding,
      codeBlockTextStyle: codeBlockTextStyle ?? this.codeBlockTextStyle,
      listBulletGap: listBulletGap ?? this.listBulletGap,
      orderedListIndent: orderedListIndent ?? this.orderedListIndent,
      unorderedListIndent: unorderedListIndent ?? this.unorderedListIndent,
      listItemSpacing: listItemSpacing ?? this.listItemSpacing,
      listItemBlockSpacing: listItemBlockSpacing ?? this.listItemBlockSpacing,
      orderedListBulletTextStyle:
          orderedListBulletTextStyle ?? this.orderedListBulletTextStyle,
      unorderedListBulletTextStyle:
          unorderedListBulletTextStyle ?? this.unorderedListBulletTextStyle,
      tableHeaderTextStyle: tableHeaderTextStyle ?? this.tableHeaderTextStyle,
      tableBodyTextStyle: tableBodyTextStyle ?? this.tableBodyTextStyle,
      tableCellPadding: tableCellPadding ?? this.tableCellPadding,
      tableBorder: tableBorder ?? this.tableBorder,
      footnoteLabelTextStyle:
          footnoteLabelTextStyle ?? this.footnoteLabelTextStyle,
      codeHighlightTheme: codeHighlightTheme ?? this.codeHighlightTheme,
    );
  }

  static CmarkThemeData fallback(TextTheme textTheme) {
    final headingStyles = <TextStyle>[
      textTheme.headlineMedium ??
          const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
      textTheme.headlineSmall ??
          const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      textTheme.titleLarge ??
          const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      textTheme.titleMedium ??
          const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      textTheme.titleSmall ??
          const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      textTheme.bodyLarge ??
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ];

    return CmarkThemeData(
      paragraphTextStyle: textTheme.bodyMedium ?? const TextStyle(fontSize: 16),
      headingTextStyles: headingStyles,
      codeSpanTextStyle: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontFamily: 'monospace',
        backgroundColor: Colors.grey.shade200,
      ),
      inlineCodeFontScale: 0.85,
      linkTextStyle: const TextStyle(
        color: Colors.blue,
        decoration: TextDecoration.underline,
      ),
      emphasisTextStyle: const TextStyle(fontStyle: FontStyle.italic),
      strongTextStyle: const TextStyle(fontWeight: FontWeight.bold),
      strikethroughTextStyle: const TextStyle(
        decoration: TextDecoration.lineThrough,
      ),
      thematicBreakColor: Colors.grey.shade400,
      thematicBreakThickness: 1.0,
      thematicBreakVerticalPadding: 8.0,
      blockSpacing: const EdgeInsets.only(bottom: 0),
      blockQuoteBackgroundColor: Colors.grey.shade100,
      blockQuoteBorderColor: Colors.grey.shade400,
      blockQuotePadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      codeBlockBackgroundColor: Colors.grey.shade900,
      codeBlockPadding: const EdgeInsets.all(12),
      codeBlockTextStyle: const TextStyle(
        fontFamily: 'monospace',
        color: Colors.white,
        fontSize: 14,
      ),
      listBulletGap: 8,
      orderedListIndent: (_) => 16,
      unorderedListIndent: (_) => 16,
      listItemSpacing: 8,
      orderedListBulletTextStyle: textTheme.bodyMedium ?? const TextStyle(),
      unorderedListBulletTextStyle: textTheme.bodyMedium ?? const TextStyle(),
      tableHeaderTextStyle: (textTheme.labelLarge ?? const TextStyle())
          .copyWith(fontWeight: FontWeight.bold),
      tableBodyTextStyle: textTheme.bodyMedium ?? const TextStyle(),
      tableCellPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      tableBorder: TableBorder.all(color: Colors.grey),
      footnoteLabelTextStyle:
          textTheme.bodySmall ?? const TextStyle(fontSize: 12),
      codeHighlightTheme: const CodeHighlightTheme(
        theme: highlight_theme.a11yDarkTheme,
        autoDetectLanguage: true,
        defaultLanguage: 'plaintext',
        fallbackStyle: TextStyle(color: Colors.white70),
        tabSize: 2,
      ),
    );
  }
}

class CmarkTheme extends InheritedWidget {
  const CmarkTheme({super.key, required this.data, required super.child});

  final CmarkThemeData data;

  static CmarkThemeData of(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<CmarkTheme>();
    if (inherited != null) {
      return inherited.data;
    }
    final textTheme = Theme.of(context).textTheme;
    return CmarkThemeData.fallback(textTheme);
  }

  static CmarkThemeData? maybeOf(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<CmarkTheme>();
    return inherited?.data;
  }

  @override
  bool updateShouldNotify(covariant CmarkTheme oldWidget) {
    return oldWidget.data != data;
  }
}
