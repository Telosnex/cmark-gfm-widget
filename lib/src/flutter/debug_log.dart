import 'package:flutter/foundation.dart';

const bool _kForceLogs = false;
const bool kIsCopyDiagnosticsEnabled = false;

void debugLog(String Function() messageBuilder) {
  if (!_kForceLogs || !kDebugMode) {
    return;
  }

  // ignore: avoid_print
  print('[cmark_gfm_widget] ${messageBuilder()}');
}

/// Always-on (in debug/profile) diagnostics for the copy path.
///
/// Cmd+C failing is a *silent* failure: no exception surfaces to the user and
/// nothing is written to the clipboard. These breadcrumbs let a developer
/// distinguish, from the console alone:
///  1. No log at all      -> the key event never reached the SelectableRegion
///     (focus was elsewhere, or macOS menu/engine consumed the shortcut).
///  2. "invoked" + null    -> selection state was lost before copy.
///  3. "invoked" + THREW   -> serialization bug (file an issue with the log).
///  4. "copying 0 chars"   -> serializer produced an empty string.
void copyDiagnosticLog(String Function() messageBuilder) {
  if (kReleaseMode || !kIsCopyDiagnosticsEnabled) {
    return;
  }
  // ignore: avoid_print
  print('[cmark_gfm_widget][copy] ${messageBuilder()}');
}
