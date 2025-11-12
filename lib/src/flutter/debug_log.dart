import 'package:flutter/foundation.dart';

void debugLog(String Function() messageBuilder) {
  if (!kDebugMode) {
    return;
  }

  // ignore: avoid_print
  print('[cmark_gfm_widget] ${messageBuilder()}');
}