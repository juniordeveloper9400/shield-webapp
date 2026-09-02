import 'agent_model.dart';

/// The starting agent hierarchy — the data [AgentService] is seeded from.
///
/// One national agent, and nobody else: the seed is a blank org waiting to
/// be built, not a populated demo. [national]'s phone is the one the login
/// screen recognises — signing in with it is what turns the home "Refer &
/// Earn" card into the "Agent Portal" card, and lands on the national
/// position at the top of an otherwise empty tree. Every position below it
/// — 2 region, 4 state, 8 district, 16 assembly, 32 lsgd, 64 ward, per
/// [AgentLevel.childCapacity] — exists as an open slot on "My Team" rather
/// than as a name; registering someone into one is what turns a slot into an
/// agent, and [AgentService] is where that happens.
///
/// This is the seed only. The live roster lives on [AgentService], which
/// copies this list on startup and on reset. A backend would replace both
/// wholesale.
class AgentDirectory {
  const AgentDirectory._();

  /// The seed persona — the first agent, at the top of the tree.
  static const Agent national = Agent(
    id: 'nat-001',
    name: 'Muhammed Rafi',
    phone: '9539810000',
    agentCode: 'SHD-NAT-001',
    level: AgentLevel.national,
    active: true,
    parentId: null,
    area: 'Kerala',
    earned: 285000,
    redeemed: 120000,
    personalSales: 90000,
  );

  static const List<Agent> seed = [national];
}
