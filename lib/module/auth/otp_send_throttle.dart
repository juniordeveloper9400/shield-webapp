import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Formerly a local cap on how often a device could ask for an OTP — a rolling
/// four-an-hour window plus an hour-long hard block whenever Firebase returned
/// `too-many-requests`.
///
/// That block re-armed on every Firebase hiccup and ended up locking real
/// members out of sign-in for an hour at a time, on every device. A member has
/// to be able to sign in anywhere, any time, so the cap is gone: Firebase's own
/// server-side rate limiting is the only limit now.
///
/// The class stays so its call sites keep compiling. [blockedFor] never blocks
/// and clears anything a previous build stored; the rest are no-ops.
class OtpSendThrottle {
  OtpSendThrottle({
    this.maxSends = 4,
    this.window = const Duration(hours: 1),
    this.serverBlock = const Duration(hours: 1),
  });

  final int maxSends;
  final Duration window;
  final Duration serverBlock;

  static const String _attemptsKey = 'otp_send_attempts_v1';
  static const String _blockUntilKey = 'otp_send_blocked_until_v1';

  /// Always `null` — a send is always allowed. Also wipes any block a previous
  /// build left in storage so an updated app recovers immediately.
  Future<Duration?> blockedFor() async {
    await reset();
    return null;
  }

  /// No-op — attempts are no longer counted.
  Future<void> recordSend() async {}

  /// No-op — the app no longer takes a device off Firebase. Returns
  /// [Duration.zero] for callers that use the value in a message.
  Future<Duration> registerServerBlock() async => Duration.zero;

  /// Clears the legacy keys. Called on a successful sign-in and on every send
  /// attempt via [blockedFor].
  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_attemptsKey);
      await prefs.remove(_blockUntilKey);
    } catch (error) {
      debugPrint('OtpSendThrottle: could not clear stored state — $error');
    }
  }
}
