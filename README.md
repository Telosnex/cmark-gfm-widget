# cmark_gfm_widget

A lightweight Flutter Markdown renderer built on top of
[`cmark_gfm`](../cmark-gfm-dart). It parses GitHub Flavored Markdown using the
streaming CommonMark parser and renders content as a `Column` of Flutter
widgets composed from `InlineSpan`s.

## Features

- Pure Dart parsing with `cmark_gfm`
- Direct `InlineSpan` rendering (no intermediary `SpanNode` tree)
- Column-based layout ready for wrapping in scroll views
- Stable node identifiers for efficient keyed rebuilds
- Basic support for GitHub Flavored Markdown (headings, lists, tables,
  block quotes, code blocks, strikethrough, etc.)
- Optional selectable text output
- Syntax highlighting powered by `highlight`/`flutter_highlight` with
  cached span generation

## Getting Started

Add the package as a dependency (path or git) and render Markdown using the
high-level widget:

```dart
final controller = ParserController();

SingleChildScrollView(
  child: CmarkMarkdownColumn(
    data: markdownSource,
    controller: controller,
    padding: const EdgeInsets.all(16),
  ),
);
```

If you need selectable text:

```dart
SelectableCmarkMarkdownColumn(
  data: markdownSource,
  controller: controller,
);
```

You can also parse once and reuse a snapshot:

```dart
final snapshot = controller.parse(markdownSource);

CmarkMarkdownColumn(
  snapshot: snapshot,
);
```

## Theming

Wrap any subtree with `CmarkTheme` to override styles or provide a custom
`CmarkThemeData` instance directly to the widget:

```dart
import 'package:flutter_highlight/themes/a11y-light.dart';

CmarkMarkdownColumn(
  data: markdownSource,
  theme: CmarkThemeData.fallback(Theme.of(context).textTheme).copyWith(
    paragraphTextStyle: Theme.of(context).textTheme.bodyLarge!,
    codeHighlightTheme: CodeHighlightTheme(
      theme: a11yLightTheme,
      autoDetectLanguage: false,
      defaultLanguage: 'dart',
    ),
  ),
);
```

## Roadmap

- Custom renderer registration API
- Streaming updates with minimal diff application
- Code block syntax highlighting helpers

## License

MIT
