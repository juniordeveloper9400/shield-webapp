import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/neon/persona_repository.dart';
import '../agent/agent_model.dart';
import '../agent/agent_service.dart';
import '../auth/auth_service.dart';
import '../investor/investor_model.dart';
import '../investor/investor_service.dart';
import '../registration/shield_store.dart';

/// Resolves the signed-in member's persona from Neon and applies it.
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
/// Best-effort: a build with no `DATABASE_URL` or an unreachable database
/// leaves [snapshot] at [PersonaSnapshot.none] — a plain member.
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
      } else if (phone != _resolvedFor) {
        unawaited(reload(phone));
      }
    });
    final phone = auth.currentUser.value?.phone;
    if (phone != null && phone.isNotEmpty) {
      unawaited(reload(phone));
    }
  }

  /// Re-reads for the member who is signed in right now — call on app resume.
  Future<void> refreshCurrent() =>
      reload(AuthService.instance.currentUser.value?.phone);

  /// Re-reads the persona for [phone] (10 digits, no `+91`) and applies it.
  /// Safe to call often; an overlapping call is dropped rather than queued.
  Future<void> reload(String? phone) async {
    final clean = phone?.trim() ?? '';
    _phone = clean.isEmpty ? null : clean;
    if (clean.isEmpty) {
      _resolvedFor = null;
      _apply(PersonaSnapshot.none);
      return;
    }
    if (_loading) {
      return;
    }
    _loading = true;
    try {
      final snap = await PersonaRepository.instance.loadFor(clean);
      // Ignore a result for a number we have since moved off (sign-out/switch).
      if (_phone == clean) {
        _resolvedFor = clean;
        _apply(snap);
      }
    } finally {
      _loading = false;
    }
  }

  /// Drops any applied persona — call on sign-out.
  void clear() {
    _phone = null;
    _resolvedFor = null;
    _apply(PersonaSnapshot.none);
  }

  void _apply(PersonaSnapshot snap) {
    _snapshot = snap;
    AgentService.instance.applyRemoteAgent(
      snap.agent == null ? null : _toAgent(snap.agent!),
    );
    InvestorService.instance.applyRemoteInvestor(
      snap.investor == null ? null : _toInvestor(snap.investor!),
    );
    notifyListeners();
  }

  static Agent _toAgent(RemoteAgent r) => Agent(
        id: r.code,
        name: r.name,
        phone: r.phone,
        agentCode: r.code,
        level: AgentLevel.values.firstWhere(
          (l) => l.name == r.level,
          orElse: () => AgentLevel.ward,
        ),
        active: r.active,
        parentId: r.parentCode,
        area: r.area,
        earned: r.earned,
        redeemed: r.redeemed,
        personalSales: r.personalSales,
      );

  static Investor _toInvestor(RemoteInvestor r) => Investor(
        id: r.code,
        name: r.name,
        phone: r.phone,
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
    _phone = null;
    _resolvedFor = null;
    _loading = false;
    _apply(PersonaSnapshot.none);
  }
}
