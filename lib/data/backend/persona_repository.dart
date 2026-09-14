import 'backend_http.dart';

/// The signed-in member's own agent row plus every descendant, as returned
/// by `GET /v1/agent/team` (`agent.service.ts`'s `getTeamForMember`).
class RemoteAgent {
  /// `app.agent.id`, as text — the row's real database id, not its printed
  /// [code]. [PersonaService] builds [Agent.id] as `'db-<id>'` from this,
  /// the same scheme [AgentRepository] uses for every other agent fetched
  /// into the roster — see that class's own doc for why this has to match.
  final String id;
  final String code;
  final String name;
  final String phone;

  /// Lowercase `AgentLevel` name — `national` … `ward`.
  final String level;
  final bool active;
  final String area;

  /// The real slot id (`app.region`/`state`/`district`/`assembly`/`lsgd`/
  /// `ward`) that [area] names on display — see [Agent.areaId]'s doc. Null
  /// for the national agent or one on a free-text place.
  final String? areaId;
  final int earned;
  final int redeemed;
  final int personalSales;

  /// The parent agent's own `app.agent.id`, as text, or null at the top of
  /// the tree. Also `'db-<id>'`-scheme, same reasoning as [id] itself.
  final String? parentId;

  const RemoteAgent({
    required this.id,
    required this.code,
    required this.name,
    required this.phone,
    required this.level,
    required this.active,
    required this.area,
    required this.areaId,
    required this.earned,
    required this.redeemed,
    required this.personalSales,
    required this.parentId,
  });
}

/// The signed-in member's own investor row, as returned by
/// `GET /v1/investor/me` (`investor.service.ts`'s `getOwnProfile`).
class RemoteInvestor {
  final String code;
  final String name;
  final String phone;
  final int totalUnits;
  final int unitPrice;
  final DateTime investedSince;
  final double roiPercent;

  /// Lowercase `InvestorPlanType` name — `yearly` / `monthly`.
  final String planType;

  /// The `app.shield_store.code` this stake is in, or null. The backend
  /// only carries the store's numeric id on the investor row itself; this
  /// is resolved by matching it against the public store list.
  final String? storeCode;

  const RemoteInvestor({
    required this.code,
    required this.name,
    required this.phone,
    required this.totalUnits,
    required this.unitPrice,
    required this.investedSince,
    required this.roiPercent,
    required this.planType,
    required this.storeCode,
  });
}

/// What the signed-in member resolves to on the backend — at most one of
/// [agent] / [investor], or neither for a plain member.
class PersonaSnapshot {
  final RemoteAgent? agent;
  final RemoteInvestor? investor;

  const PersonaSnapshot({this.agent, this.investor});

  static const PersonaSnapshot none = PersonaSnapshot();

  bool get isAgent => agent != null;
  bool get isInvestor => investor != null;
  bool get isConverted => agent != null || investor != null;
}

/// Reads the signed-in member's persona from the backend: whether the Super
/// Admin has converted them into an agent (`GET /v1/agent/team`) or an
/// investor (`GET /v1/investor/me`).
///
/// Best-effort over [BackendHttp] — not signed in to the backend, or an
/// unreachable one, returns [PersonaSnapshot.none], so a converted member is
/// never locked out of the app by a transient failure.
class PersonaRepository {
  const PersonaRepository._();

  static const PersonaRepository instance = PersonaRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  /// The persona for the member currently signed in to the backend. Never
  /// throws. [phone] is accepted for parity with the old direct-Neon
  /// signature (call sites already pass it) but is unused — the backend
  /// resolves identity from the session, not a client-supplied phone.
  Future<PersonaSnapshot> loadFor(String phone) async {
    if (!BackendHttp.isConfigured || !BackendHttp.instance.isSignedIn) {
      return PersonaSnapshot.none;
    }
    try {
      final results = await Future.wait([_agentFor(), _investorFor()]);
      return PersonaSnapshot(
        agent: results[0] as RemoteAgent?,
        investor: results[1] as RemoteInvestor?,
      );
    } catch (error) {
      BackendHttp.log('PersonaRepository.loadFor failed', error: error);
      return PersonaSnapshot.none;
    }
  }

  Future<RemoteAgent?> _agentFor() async {
    try {
      final body =
          await BackendHttp.instance.request('GET', '/v1/agent/team')
              as Map<String, dynamic>;
      String str(Object? v) => (v ?? '').toString();
      int money(Object? v) => double.tryParse(str(v))?.round() ?? 0;
      final parentId = body['parentId'];
      final areaId = str(body['areaId']);
      return RemoteAgent(
        id: str(body['id']),
        code: str(body['code']),
        name: str(body['name']),
        phone: str(body['phone']),
        level: str(body['level']).toLowerCase(),
        active: body['active'] == true,
        area: str(body['area']),
        areaId: areaId.isEmpty ? null : areaId,
        earned: money(body['earned']),
        redeemed: money(body['redeemed']),
        personalSales: money(body['personalSales']),
        parentId: parentId == null ? null : str(parentId),
      );
    } on BackendHttpException catch (error) {
      // 403 "Not an approved agent" — the expected shape for a plain member.
      if (error.isForbidden) return null;
      rethrow;
    }
  }

  Future<RemoteInvestor?> _investorFor() async {
    try {
      final body =
          await BackendHttp.instance.request('GET', '/v1/investor/me')
              as Map<String, dynamic>;
      String str(Object? v) => (v ?? '').toString();
      return RemoteInvestor(
        code: str(body['code']),
        name: str(body['name']),
        phone: str(body['phone']),
        totalUnits: _int(body['totalUnits']),
        unitPrice: _int(body['unitPrice'], 150000),
        investedSince: _date(body['investedSince']) ?? DateTime.now(),
        roiPercent: _double(body['roiPercent']),
        planType: str(body['planType']).toLowerCase(),
        storeCode: await _storeCodeFor(body['investedStoreId']),
      );
    } on BackendHttpException catch (error) {
      // 403 "Not an investor" — the expected shape for a plain member.
      if (error.isForbidden) return null;
      rethrow;
    }
  }

  /// The public store list only ever carries a handful of branches, so this
  /// is cheap and not worth caching separately from whatever the catalogue
  /// screen itself already loads.
  Future<String?> _storeCodeFor(Object? investedStoreId) async {
    if (investedStoreId == null) {
      return null;
    }
    try {
      final stores =
          await BackendHttp.instance.request(
                'GET',
                '/v1/public/catalogue/stores',
                auth: false,
              )
              as List<dynamic>;
      for (final store in stores.cast<Map<String, dynamic>>()) {
        if (store['id'].toString() == investedStoreId.toString()) {
          return store['code'] as String?;
        }
      }
    } catch (error) {
      BackendHttp.log('PersonaRepository._storeCodeFor failed', error: error);
    }
    return null;
  }

  static int _int(Object? v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return num.tryParse(v?.toString() ?? '')?.toInt() ?? fallback;
  }

  static double _double(Object? v, [double fallback = 0]) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? fallback;
  }

  static DateTime? _date(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
