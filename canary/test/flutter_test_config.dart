import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The test font manager never consults fontconfig for app families, so without
/// this `fontFamily: 'Inter'` would silently fall back to FlutterTest.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader('Inter');
  for (final file in ['Inter-Regular.ttf', 'Inter-SemiBold.ttf']) {
    final bytes = File('../golden-env/fonts/$file').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
  await testMain();
}
