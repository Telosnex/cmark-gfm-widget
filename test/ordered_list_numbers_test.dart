import 'package:cmark_gfm/cmark_gfm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ordered list - preserve original numbers', () {
    test('sequential numbers 1,2,3', () {
      const markdown = '''1. First
2. Second
3. Third''';

      final parser = CmarkParser();
      parser.feed(markdown);
      final doc = parser.finish();

      final numbers = _collectItemNumbers(doc);
      expect(numbers, [1, 2, 3]);
    });

    test('non-sequential numbers are preserved', () {
      const markdown = '''1. In n Out
2. El Pollo Loco
3. Pupuseria
7. Dominican place
10. Vons''';

      final parser = CmarkParser();
      parser.feed(markdown);
      final doc = parser.finish();

      final numbers = _collectItemNumbers(doc);
      // Should preserve original numbers, not normalize to 1,2,3,4,5
      expect(numbers, [1, 2, 3, 7, 10]);
    });

    test('starting from non-1 number', () {
      const markdown = '''5. Fifth item
6. Sixth item
10. Tenth item''';

      final parser = CmarkParser();
      parser.feed(markdown);
      final doc = parser.finish();

      final numbers = _collectItemNumbers(doc);
      expect(numbers, [5, 6, 10]);
    });

    test('repeated numbers are preserved', () {
      const markdown = '''1. First
1. Also first
1. Still first''';

      final parser = CmarkParser();
      parser.feed(markdown);
      final doc = parser.finish();

      final numbers = _collectItemNumbers(doc);
      expect(numbers, [1, 1, 1]);
    });
  });
}

List<int> _collectItemNumbers(CmarkNode node) {
  final numbers = <int>[];
  _walk(node, numbers);
  return numbers;
}

void _walk(CmarkNode node, List<int> numbers) {
  if (node.type == CmarkNodeType.item) {
    numbers.add(node.listData.start);
  }
  var child = node.firstChild;
  while (child != null) {
    _walk(child, numbers);
    child = child.next;
  }
}
