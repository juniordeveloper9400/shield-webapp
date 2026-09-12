import 'neon_http.dart';

/// The `app.agent` row an admin created for a member, flattened to what the app
/// needs to build an `Agent`.
class RemoteAgent {
  /// `app.agent.id` (bigint), as text — the row's real database id, not its
  /// printed [code]. [PersonaService] builds [Agent.id] as `'db-<id>'` from
  /// this, the same scheme [AgentRepository] uses for every other agent
  /// fetched into the roster. Building it from [code] instead (as this used
  /// to) meant the signed-in agent's own [Agent.id] never matched the entry
  /// [AgentRepository.fetchAll] had already put in the roster for the same
  /// row — so `AgentService.byId` never found it, `childrenOf`/`descendantsOf`
  /// ran against the wrong id, and a national or region agent's own "My
  /// Team" could show an empty downline no matter how many real agents sat
  /// underneath them.
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
  /// for the national agent or one on a free-text place. Without this, the
  /// "My Team" tree has no way to tell which of a region's states (say)
  /// this agent heads, and falls back to showing every position under them
  /// as an unnamed, generic open slot.
  final String? areaId;
  final int earned;
  final int redeemed;
  final int personalSales;

  /// The parent agent's own `app.agent.id` (bigint, as text), or null at the
  /// top of the tree. Also `'db-<id>'`-scheme, same reasoning as [id] itself.
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

/// The `app.investor` row an admin created for a member.
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

  /// The `app.shield_store.code` this stake is in, or null.
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

/// What a phone resolves to on Neon — at most one of [agent] / [investor], or
/// neither for a plain member.
class PersonaSnapshot {
  final RemoteAgent? agent;
  final RemoteInvestor? investor;

  const PersonaSnapshot({this.agent, this.investor});

  static const PersonaSnapshot none = PersonaSnapshot();

  bool get isAgent => agent != null;
  bool get isInvestor => investor != null;
  bool get isConverted => agent != null || investor != null;
}

/// Reads a signed-in member's persona from Neon: whether the Super Admin has
/// converted them into an agent (`app.agent`) or an investor (`app.investor`).
///
/// Best-effort over [NeonHttp] — no `DATABASE_URL` or an unreachable endpoint
/// returns [PersonaSnapshot.none], so a converted member is never locked out of
/// the app by a transient failure.
class PersonaRepository {
  const PersonaRepository._();

  static const PersonaRepository instance = PersonaRepository._();

  bool get isAvailable => NeonHttp.isConfigured;

  /// The persona for [phone] (10 digits, no `+91`). Never throws.
  Future<PersonaSnapshot> loadFor(String phone) async {
    final clean = phone.trim();
    if (!NeonHttp.isConfigured || clean.isEmpty) {
      return PersonaSnapshot.none;
    }
    try {
      final agent = await _agentFor(clean);
      final investor = await _investorFor(clean);
      return PersonaSnapshot(agent: agent, investor: investor);
    } catch (error) {
      NeonHttp.log('PersonaRepository.loadFor failed', error: error);
      return PersonaSnapshot.none;
    }
  }

  Future<RemoteAgent?> _agentFor(String phone) async {
    final rows = await NeonHttp.instance.query(
      r'''
        SELECT a.id::text AS id, a.code, a.name, a.phone, a.level, a.active,
               a.area, a.area_id::text AS area_id,
               a.earned, a.redeemed, a.personal_sales,
               a.parent_id::text AS parent_id
        FROM app.agent a
        WHERE a.phone = $1
        LIMIT 1
      ''',
      [phone],
    );
    if (rows.isEmpty) {
      return null;
    }
    final r = rows.first;
    final areaId = (r['area_id'] as Object?)?.toString();
    final parentId = (r['parent_id'] as Object?)?.toString();
    return RemoteAgent(
      id: (r['id'] ?? '').toString(),
      code: (r['code'] ?? '').toString(),
      name: (r['name'] ?? '').toString(),
      phone: (r['phone'] ?? phone).toString(),
      level: (r['level'] ?? 'ward').toString().toLowerCase(),
      active: _bool(r['active'], true),
      area: (r['area'] ?? '').toString(),
      areaId: (areaId == null || areaId.isEmpty) ? null : areaId,
      earned: _int(r['earned']),
      redeemed: _int(r['redeemed']),
      personalSales: _int(r['personal_sales']),
      parentId: (parentId == null || parentId.isEmpty) ? null : parentId,
    );
  }

  Future<RemoteInvestor?> _investorFor(String phone) async {
    final rows = await NeonHttp.instance.query(
      r'''
        SELECT i.code, i.name, i.phone, i.total_units, i.unit_price,
               i.invested_since, i.roi_percent, i.plan_type,
               s.code AS store_code
        FROM app.investor i
        LEFT JOIN app.shield_store s ON s.id = i.invested_store_id
        WHERE i.phone = $1
        LIMIT 1
      ''',
      [phone],
    );
    if (rows.isEmpty) {
      return null;
    }
    final r = rows.first;
    return RemoteInvestor(
      code: (r['code'] ?? '').toString(),
      name: (r['name'] ?? '').toString(),
      phone: (r['phone'] ?? phone).toString(),
      totalUnits: _int(r['total_units']),
      unitPrice: _int(r['unit_price'], 150000),
      investedSince: _date(r['invested_since']) ?? DateTime.now(),
      roiPercent: _double(r['roi_percent']),
      planType: (r['plan_type'] ?? 'yearly').toString().toLowerCase(),
      storeCode: (r['store_code'] as Object?)?.toString(),
    );
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

  static bool _bool(Object? v, bool fallback) {
    if (v is bool) return v;
    final s = v?.toString().toLowerCase();
    if (s == 'true' || s == 't' || s == '1') return true;
    if (s == 'false' || s == 'f' || s == '0') return false;
    return fallback;
  }

  static DateTime? _date(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
