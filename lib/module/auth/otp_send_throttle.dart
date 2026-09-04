import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A local cap on how often a device may ask for an OTP.
///
/// Firebase runs its own abuse protection and, once tripped, blocks the device
/// for an opaque stretch with a bare `too-many-requests`. This keeps the app
/// well inside that: [maxSends] requests inside a rolling [window], then the
/// send button is refused with the exact wait shown, until the oldest of those
/// requests ages out.
///
/// Backed by `SharedPreferences` so it survives an app restart or a web page
/// reload — a refresh must not hand back four fresh attempts.
class OtpSendThrottle {
  OtpSendThrottle({this.maxSends = 4, this.window = const Duration(hours: 1)});

  /// Requests allowed inside [window].
  final int maxSends;

  /// The rolling window the [maxSends] cap is measured over.
  final Duration window;

  static const String _key = 'otp_send_attempts_v1';

  /// How long until another send is allowed, or null when one is allowed now.
  Future<Duration?> blockedFor() async {
    final recent = await _recent();
    if (recent.length < maxSends) {
      return null;
    }
    // recent is sorted ascending; the oldest is what has to age out.
    final freeAt = recent.first.add(window);
    final wait = freeAt.difference(DateTime.now());
    return wait.isNegative ? null : wait;
  }

  /// Records that a code send was just attempted.
  Future<void> recordSend() async {
    try {
      final kept = await _recent()
        ..add(DateTime.now());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _key,
        kept.map((t) => t.millisecondsSinceEpoch.toString()).toList(),
      );
    } catch (error) {
      debugPrint('OtpSendThrottle: could not record an attempt — $error');
    }
  }

  /// Clears the history — called after a successful sign-in so the member is
  /// not billed a slot the next time they come back.
  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (error) {
      debugPrint('OtpSendThrottle: could not clear attempts — $error');
    }
  }

  /// The stored timestamps still inside [window], oldest first.
  Future<List<DateTime>> _recent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? const <String>[];
      final cutoff = DateTime.now().subtract(window);
      final recent =
          raw
              .map(int.tryParse)
              .whereType<int>()
              .map(DateTime.fromMillisecondsSinceEpoch)
              .where((t) => t.isAfter(cutoff))
              .toList()
            ..sort();
      return recent;
    } catch (error) {
      // A storage failure must never block sign-in — fall open.
      debugPrint('OtpSendThrottle: could not read attempts — $error');
      return <DateTime>[];
    }
  }
}
