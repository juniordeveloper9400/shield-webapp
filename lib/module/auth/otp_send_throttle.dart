import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A local cap on how often a device may ask for an OTP.
///
/// Two rules, whichever bites first:
///
///  * a rolling window — [maxSends] requests inside [window], then the send
///    button is refused until the oldest of those ages out; and
///  * a hard block set by [registerServerBlock], used when Firebase itself
///    comes back with `too-many-requests`. Firebase's block is opaque and only
///    grows if it keeps being hit, so once we see it the app stops sending for
///    [serverBlock] and lets it clear.
///
/// Backed by `SharedPreferences` so a restart or a web page reload cannot hand
/// back a fresh allowance. Every read and write falls open on a storage error —
/// the throttle must never be the reason a real member cannot sign in.
class OtpSendThrottle {
  OtpSendThrottle({
    this.maxSends = 4,
    this.window = const Duration(hours: 1),
    this.serverBlock = const Duration(hours: 1),
  });

  /// Requests allowed inside [window].
  final int maxSends;

  /// The rolling window the [maxSends] cap is measured over.
  final Duration window;

  /// How long to stay off Firebase after it returns `too-many-requests`.
  final Duration serverBlock;

  static const String _attemptsKey = 'otp_send_attempts_v1';
  static const String _blockUntilKey = 'otp_send_blocked_until_v1';

  /// How long until another send is allowed, or null when one is allowed now.
  Future<Duration?> blockedFor() async {
    final now = DateTime.now();
    var wait = Duration.zero;

    final until = await _blockedUntil();
    if (until != null && until.isAfter(now)) {
      wait = until.difference(now);
    }

    final recent = await _recent();
    if (recent.length >= maxSends) {
      // recent is sorted ascending; the oldest is what has to age out.
      final freeAt = recent.first.add(window);
      final rollingWait = freeAt.difference(now);
      if (rollingWait > wait) {
        wait = rollingWait;
      }
    }

    return wait > Duration.zero ? wait : null;
  }

  /// Records that a code send was just attempted.
  Future<void> recordSend() async {
    try {
      final kept = await _recent()
        ..add(DateTime.now());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _attemptsKey,
        kept.map((t) => t.millisecondsSinceEpoch.toString()).toList(),
      );
    } catch (error) {
      debugPrint('OtpSendThrottle: could not record an attempt — $error');
    }
  }

  /// Firebase returned `too-many-requests` — stop sending for [serverBlock].
  /// Returns how long the block now runs for, for the message.
  Future<Duration> registerServerBlock() async {
    final until = DateTime.now().add(serverBlock);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_blockUntilKey, until.millisecondsSinceEpoch);
    } catch (error) {
      debugPrint('OtpSendThrottle: could not store the server block — $error');
    }
    return serverBlock;
  }

  /// Clears both rules — called after a successful sign-in so the member is
  /// not billed a slot the next time they come back.
  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_attemptsKey);
      await prefs.remove(_blockUntilKey);
    } catch (error) {
      debugPrint('OtpSendThrottle: could not clear attempts — $error');
    }
  }

  Future<DateTime?> _blockedUntil() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_blockUntilKey);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (error) {
      debugPrint('OtpSendThrottle: could not read the server block — $error');
      return null;
    }
  }

  /// The stored attempt timestamps still inside [window], oldest first.
  Future<List<DateTime>> _recent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_attemptsKey) ?? const <String>[];
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
