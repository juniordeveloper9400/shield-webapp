import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/backend/backend_http.dart';
import '../../data/backend/rewards_repository.dart';
import '../auth/auth_service.dart';

enum RewardsStatus { idle, loading, ready, error }

/// The member's reward-points balance, backed by the
/// `app.reward_point_transaction` ledger — reads and redemption go through
/// `backend/api` (see [RewardsRepository]); crediting (registration bonus,
/// order points, referral reward) still goes straight to Neon (see
/// `legacy.RewardsRepository`) since the backend has no endpoint for it yet.
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

  /// What a point is worth: 100 points to the rupee. The one exchange rate in
  /// the programme — the Rewards screen, the wallet redemption and the
  /// backend's own (`POINTS_PER_RUPEE` in `rewards.service.ts`) all read
  /// this, so they cannot quote different ones. Change them together.
  static const int pointsPerRupee = 100;

  /// [points] as whole rupees, rounded down — the most they can buy.
  static int rupeesForPoints(int points) =>
      points <= 0 ? 0 : points ~/ pointsPerRupee;

  /// The most of [points] that turn into a whole number of rupees: 250 points
  /// are 200 that can be spent and 50 that wait for another 50 to make ₹1.
  static int wholeRupeePoints(int points) =>
      rupeesForPoints(points) * pointsPerRupee;

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

  bool get isConfigured => BackendHttp.isConfigured;
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
    if (!BackendHttp.isConfigured) {
      _status = RewardsStatus.error;
      _inFlight = null;
      notifyListeners();
      return;
    }
    _status = RewardsStatus.loading;
    notifyListeners();
    try {
      final balance = await RewardsRepository.instance.balanceFor();
      final history = await RewardsRepository.instance.historyFor();
      if (balance != null) _balance = balance;
      if (history != null) _history = history;
      _status = balance == null ? RewardsStatus.error : RewardsStatus.ready;
    } catch (error) {
      BackendHttp.log('RewardsService load failed', error: error);
      _status = RewardsStatus.error;
    } finally {
      _inFlight = null;
      notifyListeners();
    }
  }

  // ---- earning ----------------------------------------------------------
  //
  // Every credit path used to live here, calling straight through to Neon:
  // the registration bonus, order points, and a never-wired referral bonus.
  // All three are gone from this class now:
  //  - the registration bonus is credited automatically by the backend,
  //    inside `PATCH /v1/member/me` (see `RegistrationService.save`'s doc);
  //  - order points are credited automatically by the backend, inside
  //    `POST /v1/member/orders`'s checkout transaction (see
  //    `PurchaseService.record`'s doc);
  //  - the referral bonus had no real trigger before this migration either
  //    ("nothing calls it yet") — nothing lost in not porting it.
  // pointsForSpend above is kept as the one place the ₹100-per-10-point
  // rate is written down, even though nothing currently calls it either —
  // it documents what the backend's own copy of this same rate
  // (`RUPEES_PER_POINT` in `order.service.ts`) is matching.

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

  /// Spends [points] from the balance into the wallet — one backend call
  /// atomically debits the points ledger and credits the wallet balance
  /// (`RewardsRepository.redeem`), unlike the old two-separate-writes
  /// version of this. Returns `true` on success.
  Future<bool> redeem(int points) async {
    final user = AuthService.instance.currentUser.value;
    if (user == null || points <= 0 || points > _balance) {
      return false;
    }
    final spent = await RewardsRepository.instance.redeem(points);
    await refresh();
    return spent;
  }
}
