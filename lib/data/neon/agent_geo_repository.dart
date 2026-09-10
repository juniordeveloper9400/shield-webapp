import 'package:flutter/foundation.dart';

import '../../module/agent/agent_model.dart' show AgentLevel;
import 'neon_http.dart';

/// One row of `app.agent_geo_node` — a single slot on the agent hierarchy
/// shape ("My Team"): a region, a state, a district, an assembly segment, an
/// LSGD or a ward, joined to its parent by [parentId] (null only for the six
/// regions).
@immutable
class GeoNode {
  final String id;
  final String? parentId;
  final AgentLevel level;
  final String name;

  /// The printed tag the slot carries — `AC136`, `TVC`, `AC136-L1`,
  /// `AC136-L1-W005`. Empty for the tiers with no code (region, state,
  /// district).
  final String code;

  /// LSGD tier only — `corporation` / `municipality` / `grama_panchayat`
  /// (`app.lsgd.type`). Empty for every other tier.
  final String type;
  final int sort;

  const GeoNode({
    required this.id,
    required this.parentId,
    required this.level,
    required this.name,
    this.code = '',
    this.type = '',
    this.sort = 0,
  });

  static const Map<String, AgentLevel> _levels = {
    'region': AgentLevel.region,
    'state': AgentLevel.state,
    'district': AgentLevel.district,
    'assembly': AgentLevel.assembly,
    'lsgd': AgentLevel.lsgd,
    'ward': AgentLevel.ward,
  };

  /// Builds a node from a `/sql` row, or null when a required field is missing
  /// or the `level` is not one of the six recognised tiers.
  static GeoNode? fromRow(Map<String, dynamic> row) {
    String str(Object? v) => (v ?? '').toString().trim();
    final level = _levels[str(row['level']).toLowerCase()];
    final id = str(row['id']);
    final name = str(row['name']);
    if (level == null || id.isEmpty || name.isEmpty) {
      return null;
    }
    final parent = str(row['parent_id']);
    return GeoNode(
      id: id,
      parentId: parent.isEmpty ? null : parent,
      level: level,
      name: name,
      code: str(row['code']),
      type: str(row['type']),
      sort: int.tryParse(str(row['sort'])) ?? 0,
    );
  }
}

/// Reads the agent geographic hierarchy over the Neon HTTP SQL endpoint.
///
/// The live shape is one table per tier — `app.region` / `app.state` /
/// `app.district` / `app.assembly` / `app.lsgd` / `app.ward` (backend migration
/// 0014), linked child -> parent by foreign key. The old single self-referential
/// `app.agent_geo_node` table this used to read was dropped by that migration.
/// This flattens the six tables back into `(id, parent_id, level, name, code,
/// type, sort)` rows — a region's `parent_id` is null, every deeper tier points
/// at the row above it, and `type` carries the LSGD kind (corporation /
/// municipality / grama_panchayat).
///
/// Loaded in two steps: the structure region..lsgd is one small query (~1,200
/// rows), then the ~21k wards are a second query merged in. If the ward query
/// fails or times out on a poor connection the tree still works down to LSGD
/// rather than the whole load failing.
///
/// Read-only and best-effort: a missing `DATABASE_URL` or empty tables return
/// null; a transport / SQL failure on the structure query is rethrown so the
/// caller ([AgentGeo._load]) can show why "My Team" is empty.
class AgentGeoRepository {
  const AgentGeoRepository._();

  static const AgentGeoRepository instance = AgentGeoRepository._();

  bool get isAvailable => NeonHttp.isConfigured;

  /// Every geo node, ordered so a parent always precedes deeper tiers, or null
  /// when the endpoint is not configured or the tables are empty.
  Future<List<GeoNode>?> fetchAll() async {
    if (!NeonHttp.isConfigured) {
      return null;
    }

    // Step 1 — the structure, region down to LSGD. Small and quick. Every
    // SELECT carries a `type` column so the UNION lines up; only LSGD fills it.
    final structure = await NeonHttp.instance.query(r'''
        SELECT id::text AS id, NULL::text AS parent_id, 'region' AS level,
               name, code, '' AS type, sort, 1 AS tier
        FROM app.region
        UNION ALL
        SELECT id::text, region_id::text, 'state', name, code, '', sort, 2
        FROM app.state
        UNION ALL
        SELECT id::text, state_id::text, 'district', name, code, '', sort, 3
        FROM app.district
        UNION ALL
        SELECT id::text, district_id::text, 'assembly', name, code, '', sort, 4
        FROM app.assembly
        UNION ALL
        SELECT id::text, assembly_id::text, 'lsgd', name, code,
               type::text, sort, 5
        FROM app.lsgd
        ORDER BY tier, sort, name
      ''');
    final nodes = structure
        .map(GeoNode.fromRow)
        .whereType<GeoNode>()
        .toList(); // growable — wards appended below
    if (nodes.isEmpty) {
      return null;
    }

    // Step 2 — the wards. Best effort: a failure here leaves the tree whole
    // down to LSGD rather than dropping the entire hierarchy.
    try {
      final wards = await NeonHttp.instance.query(r'''
          SELECT id::text AS id, lsgd_id::text AS parent_id, 'ward' AS level,
                 name, code, '' AS type, sort
          FROM app.ward
          ORDER BY sort, name
        ''');
      nodes.addAll(wards.map(GeoNode.fromRow).whereType<GeoNode>());
    } catch (error) {
      NeonHttp.log(
        'AgentGeoRepository: ward load failed — tree stops at LSGD',
        error: error,
      );
    }

    return nodes;
  }
}
