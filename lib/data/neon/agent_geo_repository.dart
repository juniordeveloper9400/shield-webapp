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

/// Reads the agent geographic hierarchy — `app.agent_geo_node`, seeded and
/// then maintained from the database — over the Neon HTTP SQL endpoint.
///
/// Read-only and best-effort like the other Neon repositories: a missing
/// `DATABASE_URL`, a network failure, or an empty table returns null, and the
/// caller ([AgentGeo]) keeps the hierarchy bundled with the build.
class AgentGeoRepository {
  const AgentGeoRepository._();

  static const AgentGeoRepository instance = AgentGeoRepository._();

  bool get isAvailable => NeonHttp.isConfigured;

  /// Every geo node, ordered so a parent always precedes deeper tiers, or null
  /// when the table cannot be read.
  Future<List<GeoNode>?> fetchAll() async {
    if (!NeonHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await NeonHttp.instance.query(r'''
        SELECT id, parent_id, level, name, code, sort
        FROM app.agent_geo_node
        ORDER BY
          array_position(
            ARRAY['region','state','district','assembly','lsgd','ward'], level
          ),
          sort,
          name
      ''');
      final nodes =
          rows.map(GeoNode.fromRow).whereType<GeoNode>().toList(growable: false);
      return nodes.isEmpty ? null : nodes;
    } catch (error) {
      NeonHttp.log('AgentGeoRepository.fetchAll failed', error: error);
      return null;
    }
  }
}
