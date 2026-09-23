import 'package:flutter_test/flutter_test.dart';
import 'package:shield/data/backend/agent_geo_repository.dart';
import 'package:shield/module/agent/agent_model.dart';

/// A tiny South Region → Kerala → Malappuram → Perinthalmanna chain — enough
/// to check [GeoHierarchy.isWithin] against a real multi-tier gap, the same
/// shape "My Team" hits whenever an agent is registered several empty tiers
/// below the nearest occupied one.
GeoHierarchy _hierarchy() => GeoHierarchy.fromNodes(const [
  GeoNode(id: 'south', parentId: null, level: AgentLevel.region, name: 'South'),
  GeoNode(
    id: 'kerala',
    parentId: 'south',
    level: AgentLevel.state,
    name: 'Kerala',
  ),
  GeoNode(
    id: 'malappuram',
    parentId: 'kerala',
    level: AgentLevel.district,
    name: 'Malappuram',
  ),
  GeoNode(
    id: 'perinthalmanna',
    parentId: 'malappuram',
    level: AgentLevel.assembly,
    name: 'Perinthalmanna',
  ),
]);

void main() {
  test('isWithin is true of a slot several empty tiers below the ancestor', () {
    final geo = _hierarchy();
    expect(geo.isWithin('perinthalmanna', 'south'), isTrue);
    expect(geo.isWithin('perinthalmanna', 'kerala'), isTrue);
    expect(geo.isWithin('perinthalmanna', 'malappuram'), isTrue);
    // A slot is within itself too — the exact-match case the tree checks
    // first, before ever falling back to this walk.
    expect(geo.isWithin('perinthalmanna', 'perinthalmanna'), isTrue);
  });

  test('isWithin is false outside that branch, and at the root with nowhere '
      'left to climb', () {
    final geo = _hierarchy();
    expect(geo.isWithin('south', 'perinthalmanna'), isFalse);
    expect(geo.isWithin('south', 'kerala'), isFalse);
    expect(geo.isWithin('unknown-id', 'south'), isFalse);
  });
}
