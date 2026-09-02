import '../privilege/privilege_tier.dart';
import 'agent_customer.dart';

/// The customers behind an agent's "Direct sale" — who they personally sold
/// privilege cards to, and what those cards are.
///
/// The national agent is the only one seeded with any: [AgentDirectory] no
/// longer pre-builds a downline for anyone to have sold through, so a fresh
/// portal starts on the one set of sales the national persona is given to
/// demonstrate the feature with, and everyone registered afterwards starts
/// with none until they make their own.
///
/// Dates are kept relative to the moment the app runs ([_monthsAgo]) rather
/// than pinned to a calendar date, so the demo always reads as current: a card
/// activated "14 months ago" is always past its year, whichever day this runs.
class AgentCustomerDirectory {
  const AgentCustomerDirectory._();

  static final List<AgentCustomer> seed = _build();

  static DateTime _monthsAgo(int months) {
    final now = DateTime.now();
    return DateTime(now.year, now.month - months, now.day);
  }

  static List<AgentCustomer> _build() => [
    // The national agent's own sales — a spread of standing, so the demo
    // persona's portal shows an active card, one about to come due for
    // renewal, one that has lapsed, and a customer who holds two cards.
    AgentCustomer(
      id: 'cus-001',
      name: 'Suresh Pillai',
      phone: '9847000001',
      agentId: 'nat-001',
      plans: [
        CustomerPlan(
          id: 'pl-001a',
          tier: PrivilegeProgramme.gold,
          amount: 50000,
          activatedOn: _monthsAgo(4),
        ),
      ],
    ),
    AgentCustomer(
      id: 'cus-002',
      name: 'Meera Krishnan',
      phone: '9847000002',
      agentId: 'nat-001',
      plans: [
        CustomerPlan(
          id: 'pl-002a',
          tier: PrivilegeProgramme.platinum,
          amount: 80000,
          activatedOn: _monthsAgo(10),
        ),
        CustomerPlan(
          id: 'pl-002b',
          tier: PrivilegeProgramme.gold,
          amount: 30000,
          activatedOn: _monthsAgo(3),
        ),
      ],
    ),
    AgentCustomer(
      id: 'cus-003',
      name: 'Rajan Nair',
      phone: '9847000003',
      agentId: 'nat-001',
      plans: [
        CustomerPlan(
          id: 'pl-003a',
          tier: PrivilegeProgramme.silver,
          amount: 20000,
          activatedOn: _monthsAgo(14),
        ),
      ],
    ),
    // Fully lapsed, and on more than one card — Rajan Nair shows a single
    // expired plan; this is the customer who never renewed either of theirs.
    AgentCustomer(
      id: 'cus-004',
      name: 'Ashraf Koya',
      phone: '9847000004',
      agentId: 'nat-001',
      plans: [
        CustomerPlan(
          id: 'pl-004a',
          tier: PrivilegeProgramme.silver,
          amount: 20000,
          activatedOn: _monthsAgo(20),
        ),
        CustomerPlan(
          id: 'pl-004b',
          tier: PrivilegeProgramme.gold,
          amount: 40000,
          activatedOn: _monthsAgo(15),
        ),
      ],
    ),
    // Mixed standing: one card that lapsed, one still running — "1 of 2
    // active" on a customer who is still counted active overall, unlike
    // Ashraf above.
    AgentCustomer(
      id: 'cus-005',
      name: 'Latha Pillai',
      phone: '9847000005',
      agentId: 'nat-001',
      plans: [
        CustomerPlan(
          id: 'pl-005a',
          tier: PrivilegeProgramme.silver,
          amount: 10000,
          activatedOn: _monthsAgo(13),
        ),
        CustomerPlan(
          id: 'pl-005b',
          tier: PrivilegeProgramme.gold,
          amount: 50000,
          activatedOn: _monthsAgo(2),
        ),
      ],
    ),
  ];
}
