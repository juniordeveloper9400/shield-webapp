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
  final int sort;

  const GeoNode({
    required this.id,
    required this.parentId,
    required this.level,
    required this.name,
    this.code = '',
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
/// This flattens the six tables back into the `(id, parent_id, level, name,
/// code, sort)` rows [GeoNode.fromRow] expects — a region's `parent_id` is null,
/// every deeper tier points at the row above it.
///
/// Loaded in two steps: the structure region..lsgd is one small query (~1200
/// rows), then the ~21k wards are a second query merged in. If the ward query
/// fails or times out on a poor connection, the tree still works down to LSGD
/// rather than the whole load failing.
///
/// Read-only and best-effort like the other Neon repositories: a missing
/// `DATABASE_URL`, a network failure, or empty tables return null, and the
/// caller ([AgentGeo]) keeps the hierarchy bundled with the build.
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
    try {
      // Step 1 — the structure, region down to LSGD. Small and quick.
      final structure = await NeonHttp.instance.query(r'''
        SELECT id::text AS id, NULL::text AS parent_id, 'region' AS level,
               name, code, sort, 1 AS tier
        FROM app.region
        UNION ALL
        SELECT id::text, region_id::text, 'state', name, code, sort, 2
        FROM app.state
        UNION ALL
        SELECT id::text, state_id::text, 'district', name, code, sort, 3
        FROM app.district
        UNION ALL
        SELECT id::text, district_id::text, 'assembly', name, code, sort, 4
        FROM app.assembly
        UNION ALL
        SELECT id::text, assembly_id::text, 'lsgd', name, code, sort, 5
        FROM app.lsgd
        ORDER BY tier, sort, name
      ''');
      final nodes = structure
          .map(GeoNode.fromRow)
          .whereType<GeoNode>()
          .toList(); // growable — wards are appended below
      if (nodes.isEmpty) {
        return null;
      }

      // Step 2 — the wards. Best effort: a failure here leaves the tree
      // whole down to LSGD rather than dropping the entire hierarchy.
      try {
        final wards = await NeonHttp.instance.query(r'''
          SELECT id::text AS id, lsgd_id::text AS parent_id, 'ward' AS level,
                 name, code, sort
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
    } catch (error) {
      NeonHttp.log('AgentGeoRepository.fetchAll failed', error: error);
      return null;
    }
  }
}
