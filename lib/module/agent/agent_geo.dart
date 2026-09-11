import 'package:flutter/foundation.dart';

import '../../data/neon/agent_geo_repository.dart';
import 'agent_model.dart' show AgentLevel;

// ============================================================================
//  The agent geographic hierarchy — region → state → district → assembly →
//  lsgd → ward.
//
//  The live shape comes from Neon — one table per tier, `app.region` …
//  `app.ward` (migration 0014), read through [AgentGeoRepository]. The admin
//  can add / rename / delete a ward, an LSGD or a whole district and the app
//  picks it up on the next "My Team" open. Until that load lands (or when the
//  database is unreachable) the hierarchy is empty — there is no bundled
//  fallback and nothing in this file names a real place. Tests that need a
//  full tree hand one in via [AgentGeo.useHierarchy] — see
//  test/support/agent_geo_seed_fixture.dart.
//
//  Everything downstream (the tree, the registration form's placement
//  cascade, `AgentService.openPositionsUnder`) reads this through the plain
//  functions at the bottom — `agentSlotLabelsUnder`, `agentRegions`,
//  `agentSlotCode` — which just forward to [AgentGeo.current].
// ============================================================================

/// The named tiers, widest first — the levels that carry a fixed list of
/// child slots. [AgentLevel.national]'s children are always [GeoHierarchy]
/// regions; [AgentLevel.ward] heads nobody.
const List<AgentLevel> agentNamedTiers = [
  AgentLevel.region,
  AgentLevel.state,
  AgentLevel.district,
  AgentLevel.assembly,
  AgentLevel.lsgd,
];

/// One named slot in the hierarchy — a region, a state, a district, an
/// assembly, an LSGD or a ward — carrying the [id] every real lookup and
/// match is keyed on, plus what to show for it: [name] and, where the tier
/// carries one, [code].
///
/// [id] is what makes a slot unique. Two different slots can and often do
/// share a [name] — Kerala's real ward list alone repeats "Railway Station",
/// "Market", "High School" and hundreds more across different LSGDs, and a
/// handful of names (e.g. "Alappuzha") are used at more than one *tier*
/// (both a district and, separately, an LSGD). [GeoHierarchy]'s id-keyed
/// methods below are the only ones safe to build real navigation or
/// agent-to-slot matching on; the legacy name-keyed methods above them exist
/// for tests against the small, hand-curated, collision-free seed fixture
/// only — never use them against live data.
@immutable
class GeoSlot {
  final String id;
  final String name;
  final String code;
  final AgentLevel level;

  /// LSGD tier only — `corporation` / `municipality` / `grama_panchayat`.
  /// Empty for every other tier. [typeLabel] turns it into display text.
  final String type;

  const GeoSlot({
    required this.id,
    required this.name,
    required this.level,
    this.code = '',
    this.type = '',
  });

  /// "Corporation" / "Municipality" / "Grama Panchayat", or '' when this slot
  /// is not an LSGD or its kind is unknown.
  String get typeLabel => switch (type) {
        'corporation' => 'Corporation',
        'municipality' => 'Municipality',
        'grama_panchayat' => 'Grama Panchayat',
        _ => '',
      };

  @override
  bool operator ==(Object other) => other is GeoSlot && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// An immutable snapshot of the whole hierarchy: which slot names sit under
/// each parent, and the printed code each slot carries.
@immutable
class GeoHierarchy {
  const GeoHierarchy._({
    required this.regionNames,
    required this.regions,
    required Map<String, List<String>> childrenByParentName,
    required Map<String, String> codeByName,
    required Map<AgentLevel, List<String>> namesByLevel,
    required Map<String, AgentLevel> levelByName,
    required Map<String, String> parentNameByChild,
    required Map<String, AgentLevel> childLevelByParentName,
    required Map<String, List<GeoSlot>> childrenByParentId,
    required Map<String, String> codeById,
    required Map<String, String> nameById,
    required Map<String, AgentLevel> levelById,
    required Map<String, String> parentIdByChildId,
    required Map<String, AgentLevel> childLevelByParentId,
  }) : _childrenByParentName = childrenByParentName,
       _codeByName = codeByName,
       _namesByLevel = namesByLevel,
       _levelByName = levelByName,
       _parentNameByChild = parentNameByChild,
       _childLevelByParentName = childLevelByParentName,
       _childrenByParentId = childrenByParentId,
       _codeById = codeById,
       _nameById = nameById,
       _levelById = levelById,
       _parentIdByChildId = parentIdByChildId,
       _childLevelByParentId = childLevelByParentId;

  /// The six regions, in order — the slots directly under the national agent.
  ///
  /// Name-keyed, kept only for the tests written against the seed fixture
  /// (see [GeoSlot]'s doc) — real code should use [regions] instead.
  final List<String> regionNames;

  /// The six regions, in order — the slots directly under the national
  /// agent. What real navigation and matching should use; see [GeoSlot].
  final List<GeoSlot> regions;

  final Map<String, List<String>> _childrenByParentName;
  final Map<String, String> _codeByName;
  final Map<AgentLevel, List<String>> _namesByLevel;
  final Map<String, AgentLevel> _levelByName;
  final Map<String, String> _parentNameByChild;
  final Map<String, AgentLevel> _childLevelByParentName;

  // ---- id-keyed — what real navigation and agent-to-slot matching use ----
  final Map<String, List<GeoSlot>> _childrenByParentId;
  final Map<String, String> _codeById;
  final Map<String, String> _nameById;
  final Map<String, AgentLevel> _levelById;
  final Map<String, String> _parentIdByChildId;
  final Map<String, AgentLevel> _childLevelByParentId;

  /// The tier [id] is a slot of, or null when [id] is not a real slot (a
  /// free-text place has no id at all).
  AgentLevel? levelOfId(String id) => _levelById[id];

  /// The id of the slot one tier up from [id], or null at a region / for an
  /// unknown id.
  String? parentIdOf(String id) => _parentIdByChildId[id];

  /// The tier of [parentId]'s children — normally the enum successor of
  /// the parent's own level, but read straight from the data so an
  /// irregular branch is honoured (a ward sitting directly under an
  /// assembly, skipping the LSGD tier, say). Null when [parentId] has no
  /// children.
  AgentLevel? childLevelOfId(String parentId) =>
      _childLevelByParentId[parentId];

  /// The slots one tier below a [level] agent heading [parentId], or an
  /// empty list where that tier just doubles (a ward heads nobody) or
  /// [parentId] is null (an agent on a free-text place, not a real slot).
  /// national ignores [parentId] — its children are always [regions].
  List<GeoSlot> slotsUnder(AgentLevel level, String? parentId) {
    if (level == AgentLevel.national) {
      return regions;
    }
    if (parentId == null) {
      return const <GeoSlot>[];
    }
    return _childrenByParentId[parentId] ?? const <GeoSlot>[];
  }

  /// The printed code for a slot that carries one (`AC136`, `TVC`,
  /// `AC136-L1`, `AC136-L1-W005`), or null for a slot with no code — a zone,
  /// a state, a district, or an unknown id.
  String? codeForId(String id) => _codeById[id];

  /// The display name for [id], or null when it is not a real slot.
  String? nameForId(String id) => _nameById[id];

  /// The full slot for [id] — its name, level and code — or null when [id]
  /// is not a real slot.
  GeoSlot? slotById(String id) {
    final level = _levelById[id];
    if (level == null) {
      return null;
    }
    return GeoSlot(
      id: id,
      name: _nameById[id] ?? '',
      level: level,
      code: _codeById[id] ?? '',
    );
  }

  /// Every slot at [level], as full [GeoSlot]s — a test/tooling convenience
  /// for resolving "the slot named X at level Y" against the collision-free
  /// seed fixture. Never use this against live data to look a slot up by
  /// name — see [GeoSlot]'s doc.
  @visibleForTesting
  List<GeoSlot> slotsAtLevel(AgentLevel level) => [
    for (final entry in _levelById.entries)
      if (entry.value == level) slotById(entry.key)!,
  ];

  // ---- name-keyed legacy API — test fixtures only, see [GeoSlot] ----------
  //
  // Every method below matches purely on display name, with no id behind it.
  // That is exactly correct against the small, hand-curated seed fixture
  // (test/support/agent_geo_seed_fixture.dart) every name-keyed test in
  // test/agent_portal_test.dart checks against — nothing there repeats a
  // name. It silently does the wrong thing against the real, full-scale
  // Kerala data (loaded via [GeoHierarchy.fromNodes] from Neon), which
  // repeats thousands of ward names and a hundred-plus names across
  // different tiers. Production code must use the id-keyed methods above
  // instead: [levelOfId], [parentIdOf], [childLevelOfId], [slotsUnder],
  // [codeForId], [nameForId].

  /// The tier [name] is a named slot of, or null when it is not a fixed slot
  /// anywhere (a free-text place).
  AgentLevel? levelOfSlot(String name) => _levelByName[name];

  /// The name of the slot one tier up from [name], or null at a region / for
  /// an unknown name.
  String? parentSlotOf(String name) => _parentNameByChild[name];

  /// The tier of [parentName]'s children — normally the enum successor of
  /// [parentName]'s own level, but read straight from the data so an
  /// irregular branch is honoured (Varkala's wards sit directly under the
  /// assembly, skipping the LSGD tier). Null when [parentName] has no
  /// children.
  AgentLevel? childLevelOf(String parentName) =>
      _childLevelByParentName[parentName];

  /// The fixed slot names one tier below a [level] agent heading [area], or an
  /// empty list where that tier just doubles (a ward, or an unknown area).
  List<String> slotLabelsUnder(AgentLevel level, String area) {
    if (level == AgentLevel.national) {
      return regionNames;
    }
    return _childrenByParentName[area] ?? const <String>[];
  }

  /// The printed code for a named slot that carries one (`AC136`, `TVC`,
  /// `AC136-L1`, `AC136-L1-W005`), or null for a slot with no code — a zone, a
  /// state, a district, or a free-text place.
  String? codeFor(String name) => _codeByName[name];

  /// Every slot name at [level], in order.
  List<String> namesAt(AgentLevel level) =>
      _namesByLevel[level] ?? const <String>[];

  /// `{ parentName: [child slot names] }` for every parent at [parentLevel]
  /// that has named children — the shape the old `agentRegionStates` /
  /// `agentStateDistricts` / `agentDistrictAssemblies` maps had.
  Map<String, List<String>> childMapFor(AgentLevel parentLevel) => {
    for (final name in namesAt(parentLevel))
      if ((_childrenByParentName[name] ?? const <String>[]).isNotEmpty)
        name: _childrenByParentName[name]!,
  };

  /// Builds a hierarchy from a flat node list ([AgentGeoRepository.fetchAll] or
  /// a test fixture).
  ///
  /// Builds both layers: the id-keyed one real navigation and agent-to-slot
  /// matching should use (ids are the real Neon primary keys, or the
  /// fixture's own synthetic-but-unique ones — either way genuinely unique),
  /// and the name-keyed legacy one kept for tests written against the
  /// collision-free seed fixture — see [GeoSlot].
  factory GeoHierarchy.fromNodes(List<GeoNode> nodes) {
    final byId = {for (final n in nodes) n.id: n};
    final byParent = <String, List<GeoNode>>{};
    final regions = <GeoNode>[];
    for (final n in nodes) {
      if (n.parentId == null) {
        if (n.level == AgentLevel.region) regions.add(n);
      } else {
        (byParent[n.parentId!] ??= <GeoNode>[]).add(n);
      }
    }

    int order(GeoNode a, GeoNode b) =>
        a.sort != b.sort ? a.sort.compareTo(b.sort) : a.name.compareTo(b.name);
    regions.sort(order);

    GeoSlot toSlot(GeoNode n) => GeoSlot(
          id: n.id,
          name: n.name,
          level: n.level,
          code: n.code,
          type: n.type,
        );

    final childrenByParentName = <String, List<String>>{};
    final parentNameByChild = <String, String>{};
    final childLevelByParentName = <String, AgentLevel>{};
    final childrenByParentId = <String, List<GeoSlot>>{};
    final parentIdByChildId = <String, String>{};
    final childLevelByParentId = <String, AgentLevel>{};
    for (final entry in byParent.entries) {
      final parent = byId[entry.key];
      if (parent == null) continue;
      final kids = entry.value..sort(order);
      childrenByParentName[parent.name] = [for (final k in kids) k.name];
      childLevelByParentName[parent.name] = kids.first.level;
      childrenByParentId[parent.id] = [for (final k in kids) toSlot(k)];
      childLevelByParentId[parent.id] = kids.first.level;
      for (final k in kids) {
        parentNameByChild[k.name] = parent.name;
        parentIdByChildId[k.id] = parent.id;
      }
    }

    final nodesByLevel = <AgentLevel, List<GeoNode>>{};
    for (final n in nodes) {
      (nodesByLevel[n.level] ??= <GeoNode>[]).add(n);
    }
    final namesByLevel = <AgentLevel, List<String>>{
      for (final entry in nodesByLevel.entries)
        entry.key: [for (final n in (entry.value..sort(order))) n.name],
    };

    return GeoHierarchy._(
      regionNames: [for (final r in regions) r.name],
      regions: [for (final r in regions) toSlot(r)],
      childrenByParentName: childrenByParentName,
      codeByName: {
        for (final n in nodes)
          if (n.code.isNotEmpty) n.name: n.code,
      },
      namesByLevel: namesByLevel,
      levelByName: {for (final n in nodes) n.name: n.level},
      parentNameByChild: parentNameByChild,
      childLevelByParentName: childLevelByParentName,
      childrenByParentId: childrenByParentId,
      codeById: {
        for (final n in nodes)
          if (n.code.isNotEmpty) n.id: n.code,
      },
      nameById: {for (final n in nodes) n.id: n.name},
      levelById: {for (final n in nodes) n.id: n.level},
      parentIdByChildId: parentIdByChildId,
      childLevelByParentId: childLevelByParentId,
    );
  }

  /// An empty hierarchy — no regions, no slots. What the app shows until
  /// [AgentGeo.ensureLoaded] has pulled the real tables (`app.region` …
  /// `app.ward`, migration 0014). There is no bundled fallback any more.
  factory GeoHierarchy.empty() => GeoHierarchy.fromNodes(const []);
}

/// Holds the hierarchy that is currently in force and swaps in the database
/// copy once it has loaded. A [ChangeNotifier] so the "My Team" tree can
/// rebuild when the real data arrives.
class AgentGeo extends ChangeNotifier {
  AgentGeo._();

  static final AgentGeo instance = AgentGeo._();

  static GeoHierarchy _current = GeoHierarchy.empty();

  /// The hierarchy every accessor reads — empty until [ensureLoaded] has
  /// pulled the database copy (`app.region` … `app.ward`).
  static GeoHierarchy get current => _current;

  bool _loaded = false;
  bool _fromDatabase = false;
  bool _attempted = false;
  Object? _lastError;
  Future<void>? _inFlight;

  /// Whether the database copy has replaced the bundled seed.
  bool get isFromDatabase => _fromDatabase;

  /// True once a load has run to completion at least once — success, empty
  /// tables, or failure. Lets a screen tell "still loading" from "loaded and
  /// there is genuinely nothing".
  bool get hasAttempted => _attempted;

  /// True while a fetch is actually in flight — including a forced re-fetch
  /// triggered by reopening "My Team" after [hasAttempted] is already true
  /// from an earlier visit. Without this, [ensureLoaded]'s `force: true`
  /// silently re-fetches in the background while the screen keeps showing
  /// whatever [current] held before the reload started; a card can look
  /// like a real, final answer (a named slot, or the generic doubling
  /// fallback) when it is really just what was on hand before this visit's
  /// own fetch had landed.
  bool get isLoading => _inFlight != null;

  /// The reason the last load failed (a transport / SQL error), or null when
  /// it succeeded, is still running, or simply came back empty. "My Team"
  /// surfaces this so an empty tree is explained rather than silent.
  Object? get lastError => _lastError;

  /// Loads the hierarchy from Neon once (best-effort — a missing or
  /// unreachable database just leaves it empty). Safe to call from every
  /// screen's `initState`; only the first call does any work unless [force]
  /// is set.
  Future<void> ensureLoaded({bool force = false}) {
    if (force) {
      _loaded = false;
      _inFlight = null;
    }
    if (_loaded) return Future<void>.value();
    return _inFlight ??= _load();
  }

  Future<void> _load() async {
    try {
      // Belt-and-suspenders on top of NeonHttp's own per-query timeout: this
      // guarantees the load reaches a terminal state (success, empty, or
      // error) within a bounded time no matter what, so "My Team" can never
      // sit on "Loading the team hierarchy…" forever — it always ends up
      // showing either the real tree or a Retry button.
      final nodes = await AgentGeoRepository.instance
          .fetchAll()
          .timeout(const Duration(seconds: 30));
      if (nodes != null && nodes.isNotEmpty) {
        _current = GeoHierarchy.fromNodes(nodes);
        _fromDatabase = true;
        _loaded = true;
        _lastError = null;
      }
      // Otherwise nothing came back — the endpoint is not configured, or the
      // region…ward tables were still empty. Leave [_loaded] false so the next
      // `ensureLoaded()` retries rather than the session being stuck on an
      // empty tree until the app is relaunched.
    } catch (error) {
      _lastError = error;
      debugPrint('AgentGeo: hierarchy load failed — $error');
    } finally {
      _attempted = true;
      _inFlight = null;
      notifyListeners();
    }
  }

  /// Test hook — drop back to an empty hierarchy and forget any load.
  @visibleForTesting
  void reset() {
    _current = GeoHierarchy.empty();
    _loaded = false;
    _fromDatabase = false;
    _attempted = false;
    _lastError = null;
    _inFlight = null;
  }

  /// Test hook — stand in [hierarchy] for what a database load would return,
  /// e.g. to check the tree / form follow an admin edit.
  @visibleForTesting
  void useHierarchy(GeoHierarchy hierarchy) {
    _current = hierarchy;
    _loaded = true;
    _fromDatabase = true;
    _attempted = true;
    _lastError = null;
    _inFlight = null;
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
//  The flat accessor surface every other file uses. Each forwards to
//  [AgentGeo.current], so they track the database copy once it has loaded.
// ---------------------------------------------------------------------------

/// The six zones the country is split into — the fixed slots below the
/// national agent.
List<String> get agentRegions => AgentGeo.current.regionNames;

/// `{ zone: [its states] }` — the fixed state slots below each region agent.
Map<String, List<String>> get agentRegionStates =>
    AgentGeo.current.childMapFor(AgentLevel.region);

/// `{ state: [its districts] }` — only states that name their districts
/// (Kerala) appear.
Map<String, List<String>> get agentStateDistricts =>
    AgentGeo.current.childMapFor(AgentLevel.state);

/// `{ district: [its assembly segments] }` — only districts that name their
/// segments (Thiruvananthapuram) appear.
Map<String, List<String>> get agentDistrictAssemblies =>
    AgentGeo.current.childMapFor(AgentLevel.district);

/// `{ assembly segment: [its LSGDs] }`.
Map<String, List<String>> get agentAssemblyLsgds =>
    AgentGeo.current.childMapFor(AgentLevel.assembly);

/// `{ LSGD: [its wards] }`.
Map<String, List<String>> get agentLsgdWards =>
    AgentGeo.current.childMapFor(AgentLevel.lsgd);

/// The fixed slot names one level below a [level] agent heading [area], or an
/// empty list where the tier just doubles.
///
/// national → the six [agentRegions]; a region agent → its zone's states; a
/// state agent → its districts; a district agent → its assembly segments; an
/// assembly segment → its LSGDs; an LSGD → its wards.
List<String> agentSlotLabelsUnder({
  required AgentLevel level,
  required String area,
}) => AgentGeo.current.slotLabelsUnder(level, area);

/// The printed code for a named slot that carries one (`AC136`, `TVC`,
/// `AC136-L1`, `AC136-L1-W005`), or null otherwise.
String? agentSlotCode(String name) => AgentGeo.current.codeFor(name);
