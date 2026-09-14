import 'neon_http.dart';

/// `markOrdered` only — the rest of what this class used to do (upload,
/// list, view) has moved to `lib/data/backend/prescription_repository.dart`,
/// backed by `backend/api`'s `/v1/member/prescriptions` routes.
///
/// This one method stays on Neon because it is only ever called from
/// `prescription_checkout_screen.dart`, right alongside
/// `OrderRepository.savePrescriptionOrder` — the whole checkout flow is
/// deferred until the backend has cart-based checkout and a
/// prescription-to-order linkage (neither exists yet; see the migration
/// plan's notes on that gap). No reason to move this one method on its own.
///
/// Best-effort like every repository here: an unconfigured `DATABASE_URL`
/// or a network error no-ops rather than throwing.
class PrescriptionRepository {
  const PrescriptionRepository._();

  static const PrescriptionRepository instance = PrescriptionRepository._();

  /// Marks a prescription `ORDERED` once the customer places the fulfilment
  /// order. Found by [prescriptionUuid], else by the member's most recent
  /// non-ordered script. Best-effort.
  Future<void> markOrdered({
    required String memberPhone,
    String? prescriptionUuid,
  }) async {
    await _run<Object?>('markOrdered', () async {
      if (prescriptionUuid != null && prescriptionUuid.isNotEmpty) {
        await NeonHttp.instance.query(
          '''
            UPDATE app.prescription
               SET status = CASE WHEN status = 'AWAITING_REVIEW'
                                 THEN 'ORDERED'::app.prescription_status
                                 ELSE status END,
                   updated_at = now()
             WHERE uuid = \$1::uuid AND deleted_at IS NULL
          ''',
          [prescriptionUuid],
        );
        return null;
      }
      await NeonHttp.instance.query(
        '''
          UPDATE app.prescription rx
             SET status = 'ORDERED'::app.prescription_status, updated_at = now()
            FROM app.users u
           WHERE u.id = rx.member_id
             AND u.phone = \$1
             AND rx.status = 'AWAITING_REVIEW'
             AND rx.deleted_at IS NULL
        ''',
        [memberPhone],
      );
      return null;
    });
  }

  /// Runs [action], swallowing everything: a missing `DATABASE_URL`, a network
  /// error, a SQL error. Returns null on any of them.
  Future<T?> _run<T>(String label, Future<T?> Function() action) async {
    if (!NeonHttp.isConfigured) {
      return null;
    }
    try {
      return await action();
    } catch (error) {
      NeonHttp.log('PrescriptionRepository.$label failed', error: error);
      return null;
    }
  }
}
