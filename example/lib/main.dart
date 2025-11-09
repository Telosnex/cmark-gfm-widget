import 'package:cmark_gfm_widget/cmark_gfm_widget.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'cmark_gfm_widget Demo',
      theme: ThemeData.light(),
      home: const DemoHomePage(),
    );
  }
}

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  final ParserController _controller = ParserController();

  final String _sample = '''
# cmark_gfm_widget

This is a **demo** showcasing _GitHub Flavored Markdown_.

- Easy theming
- Stable node ids
- Column-based layout

> Block quotes are supported as well.

```dart
void greet() {
  print('Hello world');
}
```

| Column | Column |
| ------ | ------ |
| Cells  | Align  |
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('cmark_gfm_widget')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: CmarkMarkdownColumn(data: _sample, controller: _controller),
      ),
    );
  }
}
