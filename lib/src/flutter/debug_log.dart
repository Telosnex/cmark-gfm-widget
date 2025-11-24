import 'package:flutter/foundation.dart';

const bool _kForceLogs = false;

void debugLog(String Function() messageBuilder) {
  if (!_kForceLogs || !kDebugMode) {
    return;
  }

  // ignore: avoid_print
  print('[cmark_gfm_widget] ${messageBuilder()}');
}
