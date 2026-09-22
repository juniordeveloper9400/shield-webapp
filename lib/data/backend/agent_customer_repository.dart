import '../../module/agent/agent_customer.dart';
import '../../module/privilege/privilege_tier.dart';
import 'backend_http.dart';

/// Reads the signed-in agent's own "Direct sale" customers through
/// `backend/api`'s `GET /v1/agent/customers` — see `AgentService.listCustomers`.
///
/// Best-effort, the same contract as [AgentRepository]: an unconfigured
/// backend, a signed-out member, or a network blip returns null rather than
/// throwing. `AgentService`'s in-memory customer list is the source of truth
/// the Direct Sale section reads; this is the fetch that keeps it honest —
/// without it, every agent's Direct Sale reads "0, you have not sold a plan
/// to anyone yet" regardless of what has actually been sold and paid.
class AgentCustomerRepository {
  const AgentCustomerRepository._();

  static const AgentCustomerRepository instance = AgentCustomerRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  /// Every customer the signed-in agent has sold a plan to, plans included.
  /// [agentId] is the caller's own [Agent.id] (the `db-<id>` string the
  /// roster already uses) — the endpoint itself is scoped to the caller, so
  /// this is stamped on client-side rather than trusted from the response.
  Future<List<AgentCustomer>?> fetchAll(String agentId) =>
      _run('fetchAll', () async {
        final rows =
            await BackendHttp.instance.request('GET', '/v1/agent/customers')
                as List<dynamic>;
        return rows.cast<Map<String, dynamic>>().map((row) {
          final plans = (row['plans'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();
          return AgentCustomer(
            id: 'db-${row['id']}',
            name: (row['name'] ?? '').toString(),
            phone: (row['phone'] ?? '').toString(),
            agentId: agentId,
            plans: plans.map(_toPlan).toList(),
          );
        }).toList();
      });

  static CustomerPlan _toPlan(Map<String, dynamic> row) {
    return CustomerPlan(
      id: 'db-${row['id']}',
      tier: _tierForKind((row['tierKind'] ?? '').toString()),
      amount: num.tryParse(row['amount'].toString())?.round() ?? 0,
      activatedOn:
          DateTime.tryParse((row['activatedOn'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  static PrivilegeTier _tierForKind(String kind) {
    for (final tier in PrivilegeProgramme.tiers) {
      if (tier.kind.name.toUpperCase() == kind.toUpperCase()) {
        return tier;
      }
    }
    return PrivilegeProgramme.silver;
  }

  Future<T?> _run<T>(String label, Future<T?> Function() action) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      return await action();
    } on BackendHttpException catch (error) {
      if (!error.isForbidden && !error.isNotFound) {
        BackendHttp.log('AgentCustomerRepository.$label failed', error: error);
      }
      return null;
    } catch (error) {
      BackendHttp.log('AgentCustomerRepository.$label failed', error: error);
      return null;
    }
  }
}
