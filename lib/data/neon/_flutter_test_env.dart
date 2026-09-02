/// Web / no-`dart:io` fallback for [isUnderFlutterTest].
///
/// A platform without `dart:io` cannot be running `flutter test` against a real
/// Neon socket or HTTP endpoint, so this is always `false`. The `dart:io`
/// variant in `_flutter_test_env_io.dart` does the real `FLUTTER_TEST` check.
bool get isUnderFlutterTest => false;
