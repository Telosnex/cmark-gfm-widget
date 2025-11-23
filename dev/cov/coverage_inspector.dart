import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

void main(List<String> args) {
  final stdoutSink = stdout;
  final stderrSink = stderr;

  final InspectorOptions options;
  try {
    options = _parseArgs(args);
  } on CoverageInspectorException catch (error) {
    stderrSink.writeln(error.message);
    exitCode = 64; // EX_USAGE
    return;
  }

  try {
    final result = analyzeCoverage(
      sourcePath: options.sourcePath,
      lcovPath: options.lcovPath,
      workingDirectory: options.workingDirectory,
    );

    final report = renderAnnotatedReport(
      result,
      colorize: options.colorize,
      contextLines: options.contextLines,
      uncoveredOnly: options.uncoveredOnly,
    );

    stdoutSink.write(report);
  } on CoverageInspectorException catch (error) {
    stderrSink.writeln(error.message);
    exitCode = 1;
  } on IOException catch (error) {
    stderrSink.writeln('I/O error: $error');
    exitCode = 1;
  } catch (error) {
    stderrSink.writeln('Unexpected error: $error');
    exitCode = 1;
  }
}

InspectorOptions _parseArgs(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    throw const CoverageInspectorException(_kUsage);
  }

  String? source;
  String? lcov;
  bool colorize = _stdoutSupportsAnsi();
  int contextLines = 0;
  bool uncoveredOnly = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--')) {
      final splitIndex = arg.indexOf('=');
      final flag = splitIndex == -1 ? arg : arg.substring(0, splitIndex);
      String? value;
      if (splitIndex != -1) {
        value = arg.substring(splitIndex + 1);
      }

      switch (flag) {
        case '--lcov':
          value ??= _takeValue(args, ++i, '--lcov');
          lcov = value;
          break;
        case '--color':
          colorize = true;
          break;
        case '--no-color':
          colorize = false;
          break;
        case '--context':
          value ??= _takeValue(args, ++i, '--context');
          contextLines = _parsePositiveInt(value, '--context');
          break;
        case '--uncovered-only':
          uncoveredOnly = true;
          break;
        default:
          throw CoverageInspectorException('Unknown option: $flag\n$_kUsage');
      }
      continue;
    }

    if (source == null) {
      source = arg;
    } else if (lcov == null) {
      lcov = arg;
    } else {
      throw const CoverageInspectorException(
        'Too many positional arguments provided.\n$_kUsage',
      );
    }
  }

  if (source == null) {
    throw const CoverageInspectorException(
      'Missing <source-file> argument.\n$_kUsage',
    );
  }

  lcov ??= 'coverage/lcov.info';

  return InspectorOptions(
    sourcePath: source,
    lcovPath: lcov,
    colorize: colorize,
    contextLines: contextLines,
    uncoveredOnly: uncoveredOnly,
    workingDirectory: Directory.current.path,
  );
}

String _takeValue(List<String> args, int index, String flag) {
  if (index >= args.length) {
    throw CoverageInspectorException('Expected a value after $flag.\n$_kUsage');
  }
  return args[index];
}

int _parsePositiveInt(String input, String flag) {
  final parsed = int.tryParse(input);
  if (parsed == null || parsed < 0) {
    throw CoverageInspectorException(
      'Value for $flag must be a non-negative integer, got "$input".',
    );
  }
  return parsed;
}

bool _stdoutSupportsAnsi() {
  try {
    return stdout.hasTerminal && stdout.supportsAnsiEscapes;
  } catch (_) {
    return false;
  }
}

const String _kUsage =
    'Usage: dart dev/cov/coverage_inspector.dart <source-file> '
    '[--lcov <lcov-file>] [--context <lines>] [--uncovered-only] '
    '[--color|--no-color]';

class CoverageInspectorException implements Exception {
  const CoverageInspectorException(this.message);
  final String message;

  @override
  String toString() => 'CoverageInspectorException: $message';
}

class InspectorOptions {
  const InspectorOptions({
    required this.sourcePath,
    required this.lcovPath,
    required this.colorize,
    required this.contextLines,
    required this.uncoveredOnly,
    required this.workingDirectory,
  });

  final String sourcePath;
  final String lcovPath;
  final bool colorize;
  final int contextLines;
  final bool uncoveredOnly;
  final String workingDirectory;
}

class CoverageResult {
  CoverageResult({
    required this.sourcePath,
    required this.sourceLines,
    required this.lineHits,
  }) : _uncoveredLines = _extractUncovered(lineHits);

  final String sourcePath;
  final List<String> sourceLines;
  final SplayTreeMap<int, int> lineHits;
  final Set<int> _uncoveredLines;

  int get totalInstrumented => lineHits.length;

  int get coveredLineCount =>
      lineHits.values.where((count) => count > 0).length;

  Set<int> get uncoveredLines => _uncoveredLines;

  double get coveragePercent => totalInstrumented == 0
      ? 0
      : (coveredLineCount / totalInstrumented) * 100.0;

  List<LineRange> get uncoveredRanges => _groupLineRanges(_uncoveredLines);

  static Set<int> _extractUncovered(SplayTreeMap<int, int> hits) {
    return hits.entries
        .where((entry) => entry.value == 0)
        .map((entry) => entry.key)
        .toSet();
  }
}

class LineRange {
  const LineRange(this.start, this.end);

  final int start;
  final int end;

  bool get isSingle => start == end;

  @override
  String toString() => isSingle ? '$start' : '$start-$end';
}

CoverageResult analyzeCoverage({
  required String sourcePath,
  required String lcovPath,
  String? workingDirectory,
}) {
  final baseDir = workingDirectory ?? Directory.current.path;
  final sourceAbsolute = _toAbsolutePath(sourcePath, baseDir);
  final lcovAbsolute = _toAbsolutePath(lcovPath, baseDir);

  final lcovFile = File(lcovAbsolute);
  if (!lcovFile.existsSync()) {
    throw CoverageInspectorException(
      'Coverage file not found at ${lcovFile.path}.',
    );
  }

  final sourceFile = File(sourceAbsolute);
  if (!sourceFile.existsSync()) {
    throw CoverageInspectorException(
      'Source file not found at ${sourceFile.path}.',
    );
  }

  final hits = _parseLcovForFile(
    lcovFile.readAsLinesSync(),
    sourceAbsolute,
    baseDir,
    lcovFile.parent.path,
  );

  if (hits == null || hits.isEmpty) {
    throw CoverageInspectorException(
      'No coverage data found for ${_prettyPath(sourceAbsolute, baseDir)}.',
    );
  }

  final sourceLines = sourceFile.readAsLinesSync();

  return CoverageResult(
    sourcePath: sourceAbsolute,
    sourceLines: sourceLines,
    lineHits: hits,
  );
}

SplayTreeMap<int, int>? _parseLcovForFile(
  List<String> lcovLines,
  String targetAbsolute,
  String baseDir,
  String lcovDir,
) {
  String? currentFilePath;
  final currentHits = SplayTreeMap<int, int>();
  SplayTreeMap<int, int>? aggregatedHits;
  void mergeCurrentHits() {
    if (currentHits.isEmpty) {
      return;
    }

    aggregatedHits ??= SplayTreeMap<int, int>();
    for (final entry in currentHits.entries) {
      final existing = aggregatedHits![entry.key];
      if (existing == null) {
        aggregatedHits![entry.key] = entry.value;
      } else {
        aggregatedHits![entry.key] = existing + entry.value;
      }
    }
  }

  void finalizeRecord() {
    if (currentFilePath == null) {
      currentHits.clear();
      return;
    }

    final resolvedPaths = _resolveCandidatePaths(
      currentFilePath!,
      baseDir,
      lcovDir,
    );

    if (resolvedPaths.contains(targetAbsolute)) {
      mergeCurrentHits();
    }

    currentFilePath = null;
    currentHits.clear();
  }

  for (final line in lcovLines) {
    if (line.startsWith('SF:')) {
      finalizeRecord();

      currentFilePath = line.substring(3).trim();
      continue;
    }

    if (line == 'end_of_record') {
      finalizeRecord();
      continue;
    }

    if (currentFilePath == null) {
      continue;
    }

    if (line.startsWith('DA:')) {
      final payload = line.substring(3);
      final parts = payload.split(',');
      if (parts.length < 2) {
        continue;
      }

      final lineNumber = int.tryParse(parts[0]);
      final hitCount = int.tryParse(parts[1]);
      if (lineNumber == null || hitCount == null) {
        continue;
      }

      currentHits[lineNumber] = hitCount;
    }
  }

  finalizeRecord();

  return aggregatedHits;
}

String renderAnnotatedReport(
  CoverageResult result, {
  bool colorize = false,
  int contextLines = 0,
  bool uncoveredOnly = false,
}) {
  final buffer = StringBuffer();
  final relativePath = _prettyPath(result.sourcePath, Directory.current.path);

  buffer.writeln('Coverage summary for $relativePath');
  buffer.writeln(
    '  Coverage           : ${result.coveragePercent.toStringAsFixed(1)}%',
  );
  buffer.writeln('  Instrumented lines : ${result.totalInstrumented}');
  buffer.writeln('  Covered lines      : ${result.coveredLineCount}');
  buffer.write('  Uncovered lines    : ${result.uncoveredLines.length}');

  if (result.uncoveredLines.isNotEmpty) {
    final ranges = _formatRanges(result.uncoveredRanges);
    buffer.write(' ($ranges)');
  }
  buffer.writeln();
  buffer.writeln();

  final width = result.sourceLines.length.toString().length;
  final uncovered = result.uncoveredLines;

  Iterable<int> linesToPrint() sync* {
    if (!uncoveredOnly || uncovered.isEmpty) {
      for (var i = 1; i <= result.sourceLines.length; i++) {
        yield i;
      }
      return;
    }

    final seen = <int>{};
    for (final range in result.uncoveredRanges) {
      final start = (range.start - contextLines).clamp(
        1,
        result.sourceLines.length,
      );
      final end = (range.end + contextLines).clamp(
        1,
        result.sourceLines.length,
      );
      for (var line = start; line <= end; line++) {
        if (seen.add(line)) {
          yield line;
        }
      }
    }
  }

  final iterator = linesToPrint().toList()..sort();

  for (var index = 0; index < iterator.length; index++) {
    final lineNumber = iterator[index];
    final content = _lineSafe(result.sourceLines, lineNumber);
    final isUncovered = uncovered.contains(lineNumber);
    final highlightPrefix = isUncovered ? '!!!' : '   ';
    final highlightSuffix = isUncovered ? ' !!!' : '';
    final lineLabel = lineNumber.toString().padLeft(width);

    String textLine = '$highlightPrefix $lineLabel | $content$highlightSuffix';

    if (colorize && isUncovered) {
      textLine = '\x1B[31m$textLine\x1B[0m';
    }

    buffer.writeln(textLine);
  }

  return buffer.toString();
}

String _lineSafe(List<String> lines, int lineNumber) {
  if (lineNumber < 1 || lineNumber > lines.length) {
    return '';
  }
  return lines[lineNumber - 1];
}

String _formatRanges(List<LineRange> ranges) {
  return ranges.map((range) => range.toString()).join(', ');
}

List<LineRange> _groupLineRanges(Set<int> lines) {
  final sorted = lines.toList()..sort();
  if (sorted.isEmpty) {
    return const [];
  }

  final grouped = <LineRange>[];
  var start = sorted.first;
  var prev = start;

  for (var i = 1; i < sorted.length; i++) {
    final current = sorted[i];
    if (current == prev + 1) {
      prev = current;
      continue;
    }

    grouped.add(LineRange(start, prev));
    start = current;
    prev = current;
  }

  grouped.add(LineRange(start, prev));
  return grouped;
}

String _prettyPath(String path, String baseDir) {
  final normalizedPath = p.normalize(path);
  final normalizedBase = p.normalize(baseDir);
  final relative = p.relative(normalizedPath, from: normalizedBase);
  if (!relative.startsWith('..')) {
    return relative;
  }
  return normalizedPath;
}

String _toAbsolutePath(String path, String baseDir) {
  if (p.isAbsolute(path)) {
    return p.normalize(path);
  }
  return p.normalize(p.join(baseDir, path));
}

Set<String> _resolveCandidatePaths(
  String path,
  String baseDir,
  String lcovDir,
) {
  final candidates = <String>{};
  if (p.isAbsolute(path)) {
    candidates.add(p.normalize(path));
  } else {
    candidates.add(p.normalize(p.join(baseDir, path)));
    if (!p.equals(baseDir, lcovDir)) {
      candidates.add(p.normalize(p.join(lcovDir, path)));
    }
  }
  candidates.add(path);
  return candidates;
}
