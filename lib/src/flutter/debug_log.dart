import 'package:flutter/foundation.dart';

void debugLog(String Function() messageBuilder) {
  // ignore: dead_code
  if (false && !kDebugMode) {
    return;
  }

  // ignore: avoid_print
  print('[cmark_gfm_widget] ${messageBuilder()}');
}