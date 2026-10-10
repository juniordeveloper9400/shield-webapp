/// Non-web stand-in for `msg91_widget_otp_web.dart` — selected by
/// `msg91_widget_otp.dart`'s conditional export on native builds, which
/// have no browser to run MSG91's JS widget in. Both functions always
/// throw [UnsupportedError]; callers map that to [OtpError.unavailable]
/// the same way a missing Firebase app used to be reported.
///
/// Native (Android/iOS) OTP sending needs a WebView-hosted equivalent of
/// `msg91_widget_otp_web.dart` — not yet built. Until then, member sign-in
/// and agent registration are web-only in practice.
Future<void> sendWidgetOtp(String identifier) {
  throw UnsupportedError('MSG91 widget OTP is only available on the web build right now.');
}

Future<String> verifyWidgetOtp(String code) {
  throw UnsupportedError('MSG91 widget OTP is only available on the web build right now.');
}
