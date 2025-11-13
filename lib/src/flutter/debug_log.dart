import 'package:flutter/foundation.dart';

void debugLog(String Function() messageBuilder) {
  // ignore: dead_code
  if (true && !kDebugMode) {
    return;
  }

  // ignore: avoid_print
  print('[cmark_gfm_widget] ${messageBuilder()}');
}