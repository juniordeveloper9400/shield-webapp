import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/neon/neon_http.dart';
import '../../data/neon/rewards_repository.dart';
import '../auth/auth_service.dart';

enum RewardsStatus { idle, loading, ready, error }

/// The member's reward-points balance, backed by the `app.reward_point_transaction`
/// ledger on Neon (see [RewardsRepository]).
///
/// One number, one source of truth: the balance is `SUM(points)` over the
/// ledger, and every earn / redeem is a real row. The header coin, the rewards
/// screen, the menu and the wallet all read [balance] from here, so what a
/// member sees is what the database holds — the same on the APK and the web
/// build.
///
/// Points are keyed to the signed-in mobile number, so the balance is `0`
/// while signed out. [attach] wires it to the auth session; call it once from
/// `main()`.
class RewardsService extends ChangeNotifier {
  RewardsService._();

  static final RewardsService instance = RewardsService._();

  /// Credited once, on the first completed registration.
  static const int registrationBonus = 500;

  /// Earn rate on a paid order: ₹100 → 10 points (ten rupees to the point).
  static const int rupeesPerPoint = 10;

  /// Points earned by paying [rupeesPaid] on an order, rounded down.
  static int pointsForSpend(int rupeesPaid) =>
      rupeesPaid <= 0 ? 0 : rupeesPaid ~/ rupeesPerPoint;

  RewardsStatus _status = RewardsStatus.idle;
  RewardsStatus get status => _status;

  int _balance = 0;

  /// The member's points balance — the ledger sum. `0` when signed out or
  /// before the first load.
  int get balance => _balance;

  List<RewardTxn> _history = const [];
  List<RewardTxn> get history => _history;

  bool get isConfigured => NeonHttp.isConfigured;
  bool get isLoading => _status == RewardsStatus.loading;

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
      _balance = 0;
      _history = const [];
      _status = RewardsStatus.idle;
      _inFlight = null;
      notifyListeners();
    } else {
      unawaited(refresh());
    }
  }

  /// Loads the balance + history for the signed-in member if not already
  /// loaded. A no-op while signed out.
  Future<void> ensureLoaded() {
    if (_phone == null || _status == RewardsStatus.ready) {
      return Future.value();
    }
    return _inFlight ??= _load();
  }

  /// Re-read the ledger now (after an earn / redeem, or pull-to-refresh).
  Future<void> refresh() {
    _inFlight = null;
    return _inFlight ??= _load();
  }

  Future<void> _load() async {
    final phone = _phone;
    if (phone == null) {
      _status = RewardsStatus.idle;
      _inFlight = null;
      notifyListeners();
      return;
    }
    if (!NeonHttp.isConfigured) {
      _status = RewardsStatus.error;
      _inFlight = null;
      notifyListeners();
      return;
    }
    _status = RewardsStatus.loading;
    notifyListeners();
    try {
      final balance = await RewardsRepository.instance.balanceFor(phone);
      final history = await RewardsRepository.instance.historyFor(phone);
      if (balance != null) _balance = balance;
      if (history != null) _history = history;
      _status = balance == null ? RewardsStatus.error : RewardsStatus.ready;
    } catch (error) {
      NeonHttp.log('RewardsService load failed', error: error);
      _status = RewardsStatus.error;
    } finally {
      _inFlight = null;
      notifyListeners();
    }
  }

  // ---- earning ----------------------------------------------------------

  /// Credits the one-time registration bonus. Safe to call on every completed
  /// registration — the ledger write is guarded so it only lands once.
  Future<void> awardRegistrationBonus({
    required String phone,
    required String name,
  }) async {
    await RewardsRepository.instance.credit(
      phone: phone,
      name: name,
      points: registrationBonus,
      reason: 'REGISTRATION',
      note: 'Registration bonus',
      once: true,
    );
    await refresh();
  }

  /// Credits points for a paid order (see [pointsForSpend]). A no-op while
  /// signed out or when the order earned nothing.
  Future<void> awardForOrder({
    required String code,
    required int paidRupees,
  }) async {
    final user = AuthService.instance.currentUser.value;
    final points = pointsForSpend(paidRupees);
    if (user == null || points <= 0) {
      return;
    }
    await RewardsRepository.instance.credit(
      phone: user.phone,
      name: user.name,
      points: points,
      reason: 'ORDER',
      note: 'Order $code',
      refType: 'order',
    );
    await refresh();
  }

  /// Credits a completed-referral reward. Wired for when the referral flow can
  /// say a referral has reached plan activation — nothing calls it yet.
  Future<void> awardForReferral({
    required String phone,
    required String name,
    required int points,
    String note = 'Referral reward',
  }) async {
    if (points <= 0) {
      return;
    }
    await RewardsRepository.instance.credit(
      phone: phone,
      name: name,
      points: points,
      reason: 'REFERRAL_LEVEL',
      note: note,
    );
    await refresh();
  }

  // ---- redemption -----------------------------------------------------

  // ---- test hooks --------------------------------------------------

  /// Puts [balance] straight in, as if the ledger had been read — for
  /// widget tests, which have no database. Leaves the service `ready`.
  @visibleForTesting
  void debugSet(int balance, {List<RewardTxn> history = const []}) {
    _phone = AuthService.instance.currentUser.value?.phone ?? 'test';
    _balance = balance;
    _history = history;
    _status = RewardsStatus.ready;
    _inFlight = null;
    notifyListeners();
  }

  /// Back to the unloaded state.
  @visibleForTesting
  void debugReset() {
    _phone = null;
    _balance = 0;
    _history = const [];
    _status = RewardsStatus.idle;
    _inFlight = null;
    notifyListeners();
  }

  /// Spends [points] from the balance as a negative `REDEMPTION` ledger row.
  /// The caller does the wallet-side credit. Returns `true` when the row was
  /// written.
  Future<bool> redeem(int points, {String note = 'Redeemed to wallet'}) async {
    final user = AuthService.instance.currentUser.value;
    if (user == null || points <= 0 || points > _balance) {
      return false;
    }
    final wrote = await RewardsRepository.instance.credit(
      phone: user.phone,
      name: user.name,
      points: -points,
      reason: 'REDEMPTION',
      note: note,
    );
    await refresh();
    return wrote != null;
  }
}
