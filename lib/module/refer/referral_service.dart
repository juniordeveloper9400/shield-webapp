import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/neon/neon_http.dart';
import '../../data/neon/referral_repository.dart';
import '../auth/auth_service.dart';
import 'referral_level.dart';

enum ReferralStatus { idle, loading, ready, error }

/// The signed-in member's refer-and-earn standing, backed by `app.referral`
/// and `app.users.referral_code` on Neon (see [ReferralRepository]).
///
/// Mirrors [RewardsService]: one figure kept once, so the home card and the
/// refer & earn screen read the same real numbers rather than each carrying
/// its own guess. [attach] wires it to the auth session; call it once from
/// `main()`.
class ReferralService extends ChangeNotifier {
  ReferralService._();

  static final ReferralService instance = ReferralService._();

  ReferralStatus _status = ReferralStatus.idle;
  ReferralStatus get status => _status;
  bool get isLoading => _status == ReferralStatus.loading;
  bool get isConfigured => NeonHttp.isConfigured;

  ReferralProgress _progress = const ReferralProgress(directReferrals: 0);

  /// The member's real standing. Zeroed while signed out or before the first
  /// load — never the sample fixture, which is for tests and the widget
  /// gallery only.
  ReferralProgress get progress => _progress;

  String? _code;

  /// The member's real invite code once it has loaded, the ladder's
  /// placeholder text before then (or on a build with no database) — the
  /// code card is never left blank.
  String get code => _code ?? ReferralLadder.fallbackCode;

  String? _phone;
  bool _attached = false;
  Future<void>? _inFlight;

  /// Follow the auth session: (re)load on sign-in, clear on sign-out. Safe to
  /// call more than once.
  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    AuthService.instance.currentUser.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void _onAuthChanged() {
    final phone = AuthService.instance.currentUser.value?.phone;
    if (phone == _phone) {
      return;
    }
    _phone = phone;
    if (phone == null) {
      _progress = const ReferralProgress(directReferrals: 0);
      _code = null;
      _status = ReferralStatus.idle;
      _inFlight = null;
      notifyListeners();
    } else {
      unawaited(refresh());
    }
  }

  /// Loads the standing for the signed-in member if not already loaded. A
  /// no-op while signed out.
  Future<void> ensureLoaded() {
    if (_phone == null || _status == ReferralStatus.ready) {
      return Future.value();
    }
    return _inFlight ??= _load();
  }

  /// Re-reads the standing now (after a referral lands, or pull-to-refresh).
  Future<void> refresh() {
    _inFlight = null;
    return _inFlight ??= _load();
  }

  Future<void> _load() async {
    final phone = _phone;
    if (phone == null) {
      _status = ReferralStatus.idle;
      _inFlight = null;
      notifyListeners();
      return;
    }
    if (!NeonHttp.isConfigured) {
      _status = ReferralStatus.error;
      _inFlight = null;
      notifyListeners();
      return;
    }
    _status = ReferralStatus.loading;
    notifyListeners();
    try {
      final code = await ReferralRepository.instance.ensureCodeFor(phone);
      final progress = await ReferralRepository.instance.progressFor(phone);
      if (code != null) _code = code;
      if (progress != null) _progress = progress;
      _status = progress == null ? ReferralStatus.error : ReferralStatus.ready;
    } catch (error) {
      NeonHttp.log('ReferralService load failed', error: error);
      _status = ReferralStatus.error;
    } finally {
      _inFlight = null;
      notifyListeners();
    }
  }

  // ---- writes ------------------------------------------------------

  /// Records a referral code entered on the registration form. Called once,
  /// right after [RegistrationService.save] on a first-time registration —
  /// editing an existing profile carries no such field, so this never runs
  /// twice for the same member.
  ///
  /// Best-effort and silent either way: a bad, self-used or already-spent
  /// code must not stop the registration it rode in on.
  Future<void> recordSignupCode(String code) async {
    final phone = AuthService.instance.currentUser.value?.phone;
    final trimmed = code.trim();
    if (phone == null || trimmed.isEmpty) {
      return;
    }
    await ReferralRepository.instance.recordSignup(
      code: trimmed,
      newMemberPhone: phone,
    );
  }

  /// Marks the signed-in member's own inbound referral as transacted — they
  /// were the one invited, and have just completed their first paid order.
  /// Called alongside `RewardsService.awardForOrder` from
  /// `PurchaseService.record`. A no-op for a member nobody referred.
  Future<void> markTransacted() async {
    final phone = AuthService.instance.currentUser.value?.phone;
    if (phone == null) {
      return;
    }
    await ReferralRepository.instance.markTransacted(phone);
    // The rung this unlocks (or the commission a later plan will pay) should
    // show up without the member having to leave the screen and come back.
    await refresh();
  }

  // ---- test hooks --------------------------------------------------

  /// Puts [progress] (and, optionally, [code]) straight in, as if a load had
  /// completed — for widget tests, which have no database.
  @visibleForTesting
  void debugSet(ReferralProgress progress, {String? code}) {
    _phone = AuthService.instance.currentUser.value?.phone ?? 'test';
    _progress = progress;
    if (code != null) {
      _code = code;
    }
    _status = ReferralStatus.ready;
    _inFlight = null;
    notifyListeners();
  }

  /// Back to the unloaded state.
  @visibleForTesting
  void debugReset() {
    _phone = null;
    _progress = const ReferralProgress(directReferrals: 0);
    _code = null;
    _status = ReferralStatus.idle;
    _inFlight = null;
    notifyListeners();
  }
}
