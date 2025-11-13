// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cmark_gfm_widget/src/parser/document_snapshot_v2.dart';
import 'package:cmark_gfm_widget/src/parser/parser_controller.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'perf_tester.dart';

const bool _benchEnv = bool.fromEnvironment('BENCH');

Future<void> main([List<String>? args]) async {
  final bench = _benchEnv || (args?.contains('--bench') ?? false);
  if (bench) {
    await runDocumentSnapshotPerfTest();
    return;
  }

  test('DocumentSnapshot.getNodeSource performance', skip: true, () async {
    await runDocumentSnapshotPerfTest();
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<void> runDocumentSnapshotPerfTest() async {
  final assetsDir = path.join(Directory.current.path, 'test');
  final selectableRegionFile =
      File(path.join(assetsDir, 'selectable_region.txt'));
  final poemFile = File(path.join(assetsDir, 'long_poem.txt'));

  final selectableSource = await selectableRegionFile.readAsString();
  final poemSource = await poemFile.readAsString();

  print('Loaded assets:');
  print('  selectable_region.txt → ${selectableSource.length} chars');
  print('  long_poem.txt         → ${poemSource.length} chars');

  final testCases = [
    selectableSource,
    selectableSource.substring(0, selectableSource.length ~/ 2),
    selectableSource.substring(
        selectableSource.length ~/ 4, selectableSource.length * 3 ~/ 4),
    poemSource,
  ];

  final controller = ParserController();

  final tester = PerfTester<String, void>(
    testName: 'DocumentSnapshot.getNodeSource',
    testCases: testCases,
    implementation1: (input) {
      final snapshot = controller.parse(input);
      for (final block in snapshot.blocks) {
        // Force computation for each block
        snapshot.getNodeSource(block);
      }
      return null;
    },
    // Implementation2 intentionally identical; we only care about one path
    implementation2: (input) {
      final snapshotV2 = DocumentSnapshotV2.fromSnapshot(
        controller.parse(input),
      );
      for (final block in snapshotV2.blocks) {
        snapshotV2.getNodeSource(block);
      }
      return null;
    },
    impl1Name: 'documentsnapshot_getnodesource',
    impl2Name: 'documentsnapshot_getnodesource_v2',
  );

  await tester.run(
    warmupRuns: 20,
    benchmarkRuns: 20,
    skipEqualityCheck: true,
  );
}
