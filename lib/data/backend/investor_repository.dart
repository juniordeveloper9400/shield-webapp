import '../../module/investor/investor_model.dart';
import 'backend_http.dart';

/// Files an investor's return-plan-change request through
/// `POST /v1/investor/plan-change-requests` — see `investor.service.ts`.
///
/// Investor creation stays admin-console-only (that service's own doc
/// comment); this repository only ever files a request against an investor
/// row that already exists, resolved server-side from the signed-in
/// member's session. The old direct-Neon version of this class also
/// self-upserted the `app.investor` row before filing the request — a
/// member client creating its own investor financial record, contradicting
/// that same admin-only intent. That upsert is dropped, not ported.
///
/// Best-effort, the same contract as the other repositories here: an
/// unconfigured backend or an unreachable one no-ops. Requesting a switch
/// must never fail because the backend is down.
class InvestorRepository {
  const InvestorRepository._();

  static const InvestorRepository instance = InvestorRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  /// Records a `REQUESTED` row asking to switch the signed-in investor's
  /// return plan to [requestedPlanType].
  Future<void> requestPlanChange({
    required InvestorPlanType requestedPlanType,
  }) async {
    if (!BackendHttp.isConfigured) {
      return;
    }
    try {
      await BackendHttp.instance.request(
        'POST',
        '/v1/investor/plan-change-requests',
        body: {'requestedPlanType': requestedPlanType.name.toUpperCase()},
      );
    } catch (error) {
      BackendHttp.log('InvestorRepository.requestPlanChange failed', error: error);
    }
  }
}
