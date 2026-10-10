/// Entry point for `sendWidgetOtp`/`verifyWidgetOtp` — the real MSG91
/// JS-widget implementation on web (`msg91_widget_otp_web.dart`), a
/// throwing stub everywhere else (`msg91_widget_otp_stub.dart`, see its own
/// doc on the native gap this leaves). Import this file, never the two it
/// switches between directly.
library;

export 'msg91_widget_otp_stub.dart' if (dart.library.js_interop) 'msg91_widget_otp_web.dart';
