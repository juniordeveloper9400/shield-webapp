import 'package:flutter/foundation.dart';

import '../../module/agent/agent_model.dart' show AgentLevel;
import 'backend_http.dart';

/// One row of the geo hierarchy ("My Team" 's shape) — a region, a state, a
/// district, an assembly segment, an LSGD or a ward, joined to its parent by
/// [parentId] (null only for the six regions).
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

  /// Builds a node from one row of `GET /v1/public/geo/tree`, or null when a
  /// required field is missing or the `level` is not one of the six
  /// recognised tiers.
  static GeoNode? fromRow(Map<String, dynamic> row) {
    String str(Object? v) => (v ?? '').toString().trim();
    final level = _levels[str(row['level']).toLowerCase()];
    final id = str(row['id']);
    final name = str(row['name']);
    if (level == null || id.isEmpty || name.isEmpty) {
      return null;
    }
    final parent = str(row['parentId']);
    return GeoNode(
      id: id,
      parentId: parent.isEmpty ? null : parent,
      level: level,
      name: name,
      code: str(row['code']),
      type: str(row['type']),
      sort: row['sort'] is int ? row['sort'] as int : int.tryParse(str(row['sort'])) ?? 0,
    );
  }
}

/// Reads the agent geographic hierarchy from the backend
/// (`GET /v1/public/geo/tree`) — a public, unauthenticated, cached read (see
/// `geo.service.ts`'s `listTree`).
///
/// This mirrors what the direct-Neon version of this class used to do
/// (flatten `app.region` … `app.ward` into one list of ~22k rows in two
/// queries) as a single HTTP call instead, so [AgentGeo] and everything it
/// feeds — the team tree, the registration form's placement cascade — need
/// no changes at all: they only ever read the flattened [GeoNode] list this
/// returns.
///
/// Read-only and best-effort: not configured or an empty response returns
/// null; a transport failure is rethrown so the caller ([AgentGeo._load])
/// can show why "My Team" is empty.
class AgentGeoRepository {
  const AgentGeoRepository._();

  static const AgentGeoRepository instance = AgentGeoRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  /// Every geo node, ordered so a parent always precedes deeper tiers, or
  /// null when the backend is not configured or the tables are empty.
  Future<List<GeoNode>?> fetchAll() async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    final rows = await BackendHttp.instance.request(
      'GET',
      '/v1/public/geo/tree',
      auth: false,
    ) as List<dynamic>;
    final nodes = rows
        .cast<Map<String, dynamic>>()
        .map(GeoNode.fromRow)
        .whereType<GeoNode>()
        .toList();
    return nodes.isEmpty ? null : nodes;
  }
}
