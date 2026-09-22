import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/backend/persona_repository.dart';
import '../agent/agent_directory.dart';
import '../agent/agent_model.dart';
import '../agent/agent_service.dart';
import '../auth/auth_service.dart';
import '../investor/investor_model.dart';
import '../investor/investor_service.dart';
import '../registration/shield_store.dart';

/// Resolves the signed-in member's persona from the backend and applies it.
///
/// A member the Super Admin converts in the console gets an `app.agent` or
/// `app.investor` row. This service reads that on sign-in, on a session
/// restored at launch, and on app resume, then:
///
///  * feeds it into [AgentService] / [InvestorService] so the agent / investor
///    card shows on the web build's home screen, and
///  * flips [isConverted], which `RootScreen` uses to send a converted member
///    on the **APK** to a "use the web console" screen instead of the app.
///
/// Failed lookups retain a confirmed role. A first lookup that fails remains
/// unresolved, with an error and retry option instead of a member referral card.
class PersonaService extends ChangeNotifier {
  PersonaService._();

  static final PersonaService instance = PersonaService._();

  PersonaSnapshot _snapshot = PersonaSnapshot.none;
  PersonaSnapshot get snapshot => _snapshot;

  bool get isAgent => _snapshot.isAgent;
  bool get isInvestor => _snapshot.isInvestor;

  /// True once the admin has made this member an agent or an investor.
  bool get isConverted => _snapshot.isConverted;

  /// Whether a persona has been resolved at least once for the current phone,
  /// so `RootScreen` can hold the app shell back until the answer is in rather
  /// than flashing it and then yanking it away.
  bool get isResolved => _resolvedFor != null;

  String? _phone;
  String? _resolvedFor;
  bool _loading = false;
  bool _attached = false;
  int _generation = 0;
  bool _retryQueued = false;
  String? _error;
  String? get error => _error;
  Future<PersonaSnapshot> Function(String)? _testLoader;

  @visibleForTesting
  void debugSetLoader(Future<PersonaSnapshot> Function(String) loader) {
    _testLoader = loader;
  }

  /// Ticks [refreshCurrent] every 60 seconds while someone is signed in — the
  /// one automatic trigger that does not depend on the app losing and
  /// regaining focus.
  ///
  /// Before this, [attach]'s only refresh triggers were sign-in and
  /// `RootScreen`'s `AppLifecycleState.resumed` — which on the web build
  /// fires only when the browser tab itself loses and regains focus. A
  /// member who stays on the same tab the whole time (the exact case an
  /// admin testing a conversion is likely to be in, side by side in another
  /// window they never actually switch to) had no way to see it land short
  /// of a manual sign-out/sign-in or a hard page reload — read as "the
  /// agent card takes a long time to show up," when the real cause was
  /// nothing in that session was ever going to ask again. [refreshCurrent]'s
  /// own 8-second throttle still applies, so this never stacks with a
  /// resume that just ran.
  Timer? _pollTimer;

  static const Duration _pollInterval = Duration(seconds: 60);

  /// When [reload] last actually resolved something, so [refreshCurrent]
  /// can skip a redundant one — see that method's doc.
  DateTime? _lastResolvedAt;

  /// Starts following the session: reloads the persona whenever the signed-in
  /// member changes, and clears it on sign-out. Call once from `main()` after
  /// `AuthService.restoreSession()`. Also does the first load for whoever is
  /// already signed in.
  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    final auth = AuthService.instance;
    auth.currentUser.addListener(() {
      final phone = auth.currentUser.value?.phone;
      if (phone == null || phone.isEmpty) {
        clear();
      } else {
        if (phone != _resolvedFor) {
          unawaited(reload(phone));
        }
        _pollTimer ??= Timer.periodic(
          _pollInterval,
          (_) => unawaited(refreshCurrent()),
        );
      }
    });
    final phone = auth.currentUser.value?.phone;
    if (phone != null && phone.isNotEmpty) {
      unawaited(reload(phone));
      _pollTimer ??= Timer.periodic(
        _pollInterval,
        (_) => unawaited(refreshCurrent()),
      );
    }
  }

  /// Re-reads for the member who is signed in right now — call on app resume.
  ///
  /// "Resumed" can fire more than once in quick succession — a browser tab
  /// losing and regaining focus while DevTools is open is a common way to
  /// trigger it repeatedly — and each call is a full network round trip
  /// (agent + investor). Skipping one that just ran avoids stacking
  /// redundant fetches on top of each other, which is what turned an
  /// already-slow cold backend into a much longer wait in practice: a
  /// change the admin console made a few seconds ago can wait for the next
  /// resume rather than justifying another full reload right away.
  Future<void> refreshCurrent() {
    final last = _lastResolvedAt;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 8)) {
      return Future<void>.value();
    }
    return reload(AuthService.instance.currentUser.value?.phone);
  }

  /// Re-reads the persona for [phone] (10 digits, no `+91`) and applies it.
  /// An overlapping call queues one fresh lookup for the current account.
  Future<void> reload(String? phone) async {
    final clean = phone?.trim() ?? '';
    if (_phone != (clean.isEmpty ? null : clean)) {
      _generation++;
      _resolvedFor = null;
      _lastResolvedAt = null;
      _error = null;
      _apply(PersonaSnapshot.none);
    }
    _phone = clean.isEmpty ? null : clean;
    if (clean.isEmpty) {
      _resolvedFor = null;
      _apply(PersonaSnapshot.none);
      return;
    }
    if (_loading) {
      _retryQueued = true;
      return;
    }
    final generation = _generation;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final snap = await (_testLoader ?? PersonaRepository.instance.loadFor)(clean);
      // Ignore a result for a number we have since moved off (sign-out/switch).
      if (_phone == clean && generation == _generation) {
        _resolvedFor = clean;
        _lastResolvedAt = DateTime.now();
        _apply(snap);
      }
    } catch (_) {
      if (_phone == clean && generation == _generation) {
        _error = 'Could not load your account role. Please retry.';
        // Retain a confirmed agent/investor role during network failures.
        notifyListeners();
      }
    } finally {
      _loading = false;
      if (_retryQueued) {
        _retryQueued = false;
        unawaited(reload(_phone));
      }
    }
  }

  /// Drops any applied persona — call on sign-out. Also resets
  /// [AgentService]'s whole fetched roster, not just this member's own row
  /// — otherwise a different member signing in next on the same device
  /// inherits whatever team tree the previous member's one-shot
  /// `ensureLoaded` fetch already pulled in (see that method's doc).
  void clear() {
    _generation++;
    _retryQueued = false;
    _error = null;
    _phone = null;
    _resolvedFor = null;
    _lastResolvedAt = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    AgentService.instance.reset();
    _apply(PersonaSnapshot.none);
  }

  void _apply(PersonaSnapshot snap) {
    _snapshot = snap;
    AgentService.instance.applyRemoteAgent(
      snap.agent == null ? null : _toAgent(snap.agent!, _phone),
    );
    InvestorService.instance.applyRemoteInvestor(
      snap.investor == null ? null : _toInvestor(snap.investor!, _phone),
    );
    notifyListeners();
  }

  // 'db-<id>' — the exact scheme AgentRepository.fetchAll uses for every
  // other agent in the roster (see RemoteAgent.id's own doc for why this
  // has to match: AgentService.byId looks the signed-in agent up by this
  // id to find their real roster entry, with correct children/downline).
  static Agent _toAgent(RemoteAgent r, String? memberPhone) => Agent(
        id: 'db-${r.id}',
        name: r.name,
        // The authenticated endpoint identifies the owner. Use their session
        // phone as the local lookup key, even if admin contact formatting differs.
        phone: memberPhone ?? r.phone,
        agentCode: r.code,
        level: AgentLevel.values.firstWhere(
          (l) => l.name == r.level,
          orElse: () => AgentLevel.ward,
        ),
        active: r.active,
        parentId: r.parentId == null
            ? AgentDirectory.national.id
            : 'db-${r.parentId}',
        area: r.area,
        areaId: r.areaId,
        earned: r.earned,
        redeemed: r.redeemed,
        personalSales: r.personalSales,
      );

  static Investor _toInvestor(RemoteInvestor r, String? memberPhone) => Investor(
        id: r.code,
        name: r.name,
        phone: memberPhone ?? r.phone,
        investorCode: r.code,
        investedStore: StoreDirectory.byId(r.storeCode ?? '') ??
            StoreDirectory.all.first,
        totalUnits: r.totalUnits,
        unitPrice: r.unitPrice,
        investedSince: r.investedSince,
        roiPercent: r.roiPercent,
        planType: InvestorPlanType.values.firstWhere(
          (p) => p.name == r.planType,
          orElse: () => InvestorPlanType.yearly,
        ),
      );

  @visibleForTesting
  void reset() {
    _generation++;
    _retryQueued = false;
    _error = null;
    _testLoader = null;
    _phone = null;
    _resolvedFor = null;
    _lastResolvedAt = null;
    _loading = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _apply(PersonaSnapshot.none);
  }
}
