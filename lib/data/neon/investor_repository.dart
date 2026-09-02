import '../../module/investor/investor_model.dart';
import 'neon_http.dart';

/// Writes an investor's return-plan-change request to the `app.investor` and
/// `app.investor_plan_change_request` tables on Neon.
///
/// Best-effort, the same contract as the other repositories: when the app was
/// built without a `DATABASE_URL` (tests, a build that left
/// `--dart-define-from-file=.env` off) or the network is down, the call
/// no-ops. Requesting a switch must never fail because the database is down.
///
/// Goes over [NeonHttp] (HTTPS on 443) rather than the raw Postgres socket, so
/// it works from a `flutter build web` bundle as well as the APK. Neon's
/// `/sql` endpoint runs one statement per request with no client transaction,
/// so the `app.investor` row is upserted first and the request row inserted
/// against the id it returns.
class InvestorRepository {
  const InvestorRepository._();

  static const InvestorRepository instance = InvestorRepository._();

  bool get isAvailable => NeonHttp.isConfigured;

  /// Records a `REQUESTED` row asking to switch the investor's return plan to
  /// [requestedPlanType], creating or refreshing the `app.investor` row it
  /// hangs off first.
  Future<void> requestPlanChange({
    required String investorCode,
    required String investorName,
    required String investorPhone,
    required InvestorPlanType currentPlanType,
    required InvestorPlanType requestedPlanType,
    String? investedStoreCode,
    required int totalUnits,
    required int unitPrice,
    required DateTime investedSince,
    required double roiPercent,
  }) async {
    if (!NeonHttp.isConfigured) {
      return;
    }
    try {
      final since = investedSince.toIso8601String().split('T').first;

      // 1 · The investor row this request belongs to. Linked to the member row
      // for the same phone when one exists; keyed on the unique code so a
      // repeat request updates rather than duplicates.
      final investorRows = await NeonHttp.instance.query(
        '''
          INSERT INTO app.investor
            (member_id, code, name, phone, invested_store_id, total_units,
             unit_price, invested_since, roi_percent, plan_type)
          VALUES
            ((SELECT id FROM app.users WHERE phone = \$1),
             \$2, \$3, \$1,
             (SELECT id FROM app.shield_store WHERE code = \$4),
             \$5, \$6, \$7::date, \$8,
             \$9::app.investor_plan_type)
          ON CONFLICT (code) DO UPDATE SET
            name       = EXCLUDED.name,
            phone      = EXCLUDED.phone,
            member_id  = COALESCE(app.investor.member_id, EXCLUDED.member_id),
            updated_at = now()
          RETURNING id
        ''',
        [
          investorPhone,
          investorCode,
          investorName,
          investedStoreCode,
          totalUnits,
          unitPrice,
          since,
          roiPercent,
          currentPlanType.name.toUpperCase(),
        ],
      );
      final investorId = _rowId(investorRows);
      if (investorId == null) {
        return;
      }

      // 2 · The request itself; status defaults to 'REQUESTED'.
      await NeonHttp.instance.query(
        '''
          INSERT INTO app.investor_plan_change_request
            (investor_id, requested_plan_type)
          VALUES (\$1, \$2::app.investor_plan_type)
        ''',
        [investorId, requestedPlanType.name.toUpperCase()],
      );
    } catch (error) {
      NeonHttp.log('InvestorRepository.requestPlanChange failed', error: error);
    }
  }

  static int? _rowId(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return null;
    }
    final value = rows.first['id'] ?? rows.first.values.firstOrNull;
    if (value == null) {
      return null;
    }
    return value is int ? value : int.tryParse(value.toString());
  }
}
