import 'dart:io' show Platform;

/// `true` when `flutter test` is running — it sets `FLUTTER_TEST` in the
/// environment. The connection string is a compiled-in const, so without this
/// check every repository would fire real traffic at Neon during a test run.
bool get isUnderFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');
