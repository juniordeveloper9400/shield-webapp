import 'package:flutter/foundation.dart';

import '../../data/neon/agent_geo_repository.dart';
import 'agent_model.dart' show AgentLevel;

// ============================================================================
//  The agent geographic hierarchy — region → state → district → assembly →
//  lsgd → ward.
//
//  The live shape comes from Neon (`app.agent_geo_node`, migration 0011): the
//  pharmacy admin can add / rename / delete a ward, an LSGD or a whole
//  district in the database and the app picks it up on the next "My Team"
//  open. [_seed…] below is a byte-for-byte copy of that migration's seed,
//  used offline and under test — whatever the database returns wins over it.
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

/// An immutable snapshot of the whole hierarchy: which slot names sit under
/// each parent, and the printed code each slot carries.
@immutable
class GeoHierarchy {
  const GeoHierarchy._({
    required this.regionNames,
    required Map<String, List<String>> childrenByParentName,
    required Map<String, String> codeByName,
    required Map<AgentLevel, List<String>> namesByLevel,
    required Map<String, AgentLevel> levelByName,
    required Map<String, String> parentNameByChild,
    required Map<String, AgentLevel> childLevelByParentName,
  })  : _childrenByParentName = childrenByParentName,
        _codeByName = codeByName,
        _namesByLevel = namesByLevel,
        _levelByName = levelByName,
        _parentNameByChild = parentNameByChild,
        _childLevelByParentName = childLevelByParentName;

  /// The six regions, in order — the slots directly under the national agent.
  final List<String> regionNames;

  final Map<String, List<String>> _childrenByParentName;
  final Map<String, String> _codeByName;
  final Map<AgentLevel, List<String>> _namesByLevel;
  final Map<String, AgentLevel> _levelByName;
  final Map<String, String> _parentNameByChild;
  final Map<String, AgentLevel> _childLevelByParentName;

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
  /// [_seedNodes]).
  ///
  /// Slot names are assumed globally unique — a registered agent is matched to
  /// its slot by name ([Agent.area]), and the lookups here (`codeFor`,
  /// `parentSlotOf`, `levelOfSlot`) are name-keyed. The seed and migration
  /// 0011 both satisfy this (e.g. the corporation's LSGD is
  /// "Thiruvananthapuram Municipal Corporation", distinct from the
  /// "Thiruvananthapuram Corporation" assembly segment above it).
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

    final childrenByParentName = <String, List<String>>{};
    final parentNameByChild = <String, String>{};
    final childLevelByParentName = <String, AgentLevel>{};
    for (final entry in byParent.entries) {
      final parent = byId[entry.key];
      if (parent == null) continue;
      final kids = entry.value..sort(order);
      childrenByParentName[parent.name] = [for (final k in kids) k.name];
      childLevelByParentName[parent.name] = kids.first.level;
      for (final k in kids) {
        parentNameByChild[k.name] = parent.name;
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
      childrenByParentName: childrenByParentName,
      codeByName: {
        for (final n in nodes)
          if (n.code.isNotEmpty) n.name: n.code,
      },
      namesByLevel: namesByLevel,
      levelByName: {for (final n in nodes) n.name: n.level},
      parentNameByChild: parentNameByChild,
      childLevelByParentName: childLevelByParentName,
    );
  }

  /// The bundled hierarchy — an exact copy of migration 0011's seed.
  factory GeoHierarchy.seed() => GeoHierarchy.fromNodes(_seedNodes());
}

/// Holds the hierarchy that is currently in force and swaps in the database
/// copy once it has loaded. A [ChangeNotifier] so the "My Team" tree can
/// rebuild when the real data arrives.
class AgentGeo extends ChangeNotifier {
  AgentGeo._();

  static final AgentGeo instance = AgentGeo._();

  static GeoHierarchy _current = GeoHierarchy.seed();

  /// The hierarchy every accessor reads — the bundled seed until
  /// [ensureLoaded] has pulled the database copy.
  static GeoHierarchy get current => _current;

  bool _loaded = false;
  bool _fromDatabase = false;
  Future<void>? _inFlight;

  /// Whether the database copy has replaced the bundled seed.
  bool get isFromDatabase => _fromDatabase;

  /// Loads the hierarchy from Neon once (best-effort — a missing or
  /// unreachable database just keeps the bundled seed). Safe to call from
  /// every screen's `initState`; only the first call does any work unless
  /// [force] is set.
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
      final nodes = await AgentGeoRepository.instance.fetchAll();
      if (nodes != null && nodes.isNotEmpty) {
        _current = GeoHierarchy.fromNodes(nodes);
        _fromDatabase = true;
        _loaded = true;
        notifyListeners();
      }
      // Otherwise nothing came back — the endpoint is not configured, or the
      // region…ward tables were still empty / unreachable. Leave [_loaded]
      // false so the next `ensureLoaded()` retries rather than the session
      // being stuck on the bundled seed until the app is relaunched.
    } catch (error) {
      debugPrint('AgentGeo: hierarchy load failed — $error');
    } finally {
      _inFlight = null;
    }
  }

  /// Test hook — drop back to the bundled seed and forget any load.
  @visibleForTesting
  void resetToSeed() {
    _current = GeoHierarchy.seed();
    _loaded = false;
    _fromDatabase = false;
    _inFlight = null;
  }

  /// Test hook — stand in [hierarchy] for what a database load would return,
  /// e.g. to check the tree / form follow an admin edit.
  @visibleForTesting
  void useHierarchy(GeoHierarchy hierarchy) {
    _current = hierarchy;
    _loaded = true;
    _fromDatabase = true;
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
}) =>
    AgentGeo.current.slotLabelsUnder(level, area);

/// The printed code for a named slot that carries one (`AC136`, `TVC`,
/// `AC136-L1`, `AC136-L1-W005`), or null otherwise.
String? agentSlotCode(String name) => AgentGeo.current.codeFor(name);

// ---------------------------------------------------------------------------
//  Bundled seed — a byte-for-byte copy of migration 0011's generated shape.
//  Keep the two in lockstep: a change here needs the same change there.
// ---------------------------------------------------------------------------

const List<String> _seedRegions = [
  'North',
  'South',
  'East',
  'West',
  'Central',
  'Northeast',
];

const Map<String, List<String>> _seedRegionStates = {
  'North': [
    'Chandigarh',
    'Delhi',
    'Haryana',
    'Himachal Pradesh',
    'Jammu & Kashmir',
    'Ladakh',
    'Punjab',
    'Rajasthan',
  ],
  'South': ['Andhra Pradesh', 'Karnataka', 'Kerala', 'Tamil Nadu', 'Telangana'],
  'East': ['Bihar', 'Jharkhand', 'Odisha', 'West Bengal'],
  'West': ['Chhattisgarh', 'Goa', 'Gujarat', 'Maharashtra'],
  'Central': ['Madhya Pradesh', 'Uttar Pradesh', 'Uttarakhand'],
  'Northeast': [
    'Arunachal Pradesh',
    'Assam',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Sikkim',
    'Tripura',
  ],
};

const List<String> _seedKeralaDistricts = [
  'Thiruvananthapuram',
  'Kollam',
  'Pathanamthitta',
  'Alappuzha',
  'Kottayam',
  'Idukki',
  'Ernakulam',
  'Thrissur',
  'Palakkad',
  'Malappuram',
  'Kozhikode',
  'Wayanad',
  'Kannur',
  'Kasaragod',
];

/// Thiruvananthapuram's thirteen assembly segments plus the city corporation,
/// each with its printed code — the order is the seed's `sort`.
const List<List<String>> _seedTvmAssemblies = [
  ['Varkala', 'AC124'],
  ['Attingal', 'AC125'],
  ['Chirayinkeezhu', 'AC126'],
  ['Nedumangad', 'AC127'],
  ['Vamanapuram', 'AC128'],
  ['Kazhakkoottam', 'AC129'],
  ['Vattiyoorkavu', 'AC130'],
  ['Nemom', 'AC132'],
  ['Aruvikkara', 'AC133'],
  ['Parassala', 'AC134'],
  ['Kattakkada', 'AC135'],
  ['Kovalam', 'AC136'],
  ['Neyyattinkara', 'AC137'],
  ['Thiruvananthapuram Corporation', 'TVC'],
];

/// Varkala's (AC124) local bodies — six grama panchayats and the municipality
/// that carries [_seedVarkalaMunicipalityWards]; every other assembly segment
/// just gets three generic `<name> Panchayat n` LSGDs.
const List<String> _seedVarkalaLsgds = [
  'Chemmaruthy',
  'Edava',
  'Elakamon',
  'Madavoor',
  'Pallickal',
  'Vettoor',
  'Varkala Municipality',
];

/// The wards of Varkala Municipality, in order.
const List<String> _seedVarkalaMunicipalityWards = [
  'Vilakkulam',
  'Idapparambu',
  'Janathamukku',
  'Karunilakode',
  'Kallazhi',
  'Pullannikode',
  'Ayanikkuzhivila',
  'Kannamba',
  'Nadayara',
  'Kanwasramam',
  'Chaluvila',
  'Kallamkonam',
  'Cherukunnam',
  'Sivagiri',
  'Teachers Colony',
  'Raghunathapuram',
  'Puthenchantha',
  'Thachankonam',
  'Ramanthali',
  'Panayil',
  'Vallakkadavu',
  'Perumkulam',
  'Kottumoola',
  'Maithanam',
  'Municipal Office',
  'Hospital',
  'Temple',
  'Janardhanapuram / Papanasam',
  'Parayil / Mundayil',
  'Jawahar Park',
  'Punnamoodu',
  'Parayil',
  'Papanasam',
  'Kurakkanni',
];

String _slug(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');

String _pad(int n, int width) => n.toString().padLeft(width, '0');

/// Rebuilds migration 0011's rows in memory.
List<GeoNode> _seedNodes() {
  final nodes = <GeoNode>[];

  for (var ri = 0; ri < _seedRegions.length; ri++) {
    final region = _seedRegions[ri];
    final regionId = 'geo/${_slug(region)}';
    nodes.add(GeoNode(
      id: regionId,
      parentId: null,
      level: AgentLevel.region,
      name: region,
      sort: ri + 1,
    ));

    final states = _seedRegionStates[region] ?? const <String>[];
    for (var si = 0; si < states.length; si++) {
      final state = states[si];
      final stateId = '$regionId/${_slug(state)}';
      nodes.add(GeoNode(
        id: stateId,
        parentId: regionId,
        level: AgentLevel.state,
        name: state,
        sort: si + 1,
      ));

      if (state != 'Kerala') continue;

      for (var di = 0; di < _seedKeralaDistricts.length; di++) {
        final district = _seedKeralaDistricts[di];
        final districtId = '$stateId/${_slug(district)}';
        nodes.add(GeoNode(
          id: districtId,
          parentId: stateId,
          level: AgentLevel.district,
          name: district,
          sort: di + 1,
        ));

        if (district != 'Thiruvananthapuram') continue;

        for (var ai = 0; ai < _seedTvmAssemblies.length; ai++) {
          final aname = _seedTvmAssemblies[ai][0];
          final acode = _seedTvmAssemblies[ai][1];
          final assemblyId = '$districtId/${_slug(aname)}';
          nodes.add(GeoNode(
            id: assemblyId,
            parentId: districtId,
            level: AgentLevel.assembly,
            name: aname,
            code: acode,
            sort: ai + 1,
          ));

          // The LSGDs under this assembly segment: Varkala names its six
          // grama panchayats + the municipality; the corporation segment is
          // its own single body; every other segment gets three generic
          // panchayats.
          final List<String> lsgds;
          if (acode == 'AC124') {
            lsgds = _seedVarkalaLsgds;
          } else if (acode == 'TVC') {
            lsgds = const ['Thiruvananthapuram Municipal Corporation'];
          } else {
            lsgds = [for (var li = 1; li <= 3; li++) '$aname Panchayat $li'];
          }

          for (var li = 0; li < lsgds.length; li++) {
            final lsgd = lsgds[li];
            final lcode = acode == 'TVC' ? 'TVC-L1' : '$acode-L${li + 1}';
            final lsgdId = '$assemblyId/${_slug(lsgd)}';
            nodes.add(GeoNode(
              id: lsgdId,
              parentId: assemblyId,
              level: AgentLevel.lsgd,
              name: lsgd,
              code: lcode,
              sort: li + 1,
            ));

            // Named wards for the two municipal bodies; generic numbered
            // wards for the panchayats.
            final List<String> wards;
            if (lsgd == 'Varkala Municipality') {
              wards = _seedVarkalaMunicipalityWards;
            } else if (acode == 'TVC') {
              wards = [
                for (var wi = 1; wi <= 100; wi++) '$lsgd Ward ${_pad(wi, 2)}',
              ];
            } else {
              wards = [
                for (var wi = 1; wi <= 12; wi++) '$lsgd Ward ${_pad(wi, 2)}',
              ];
            }

            for (var wi = 0; wi < wards.length; wi++) {
              nodes.add(GeoNode(
                id: '$lsgdId/ward-${_pad(wi + 1, 3)}',
                parentId: lsgdId,
                level: AgentLevel.ward,
                name: wards[wi],
                code: '$lcode-W${_pad(wi + 1, 3)}',
                sort: wi + 1,
              ));
            }
          }
        }
      }
    }
  }

  return nodes;
}
