import '../../module/labtest/lab_booking_record.dart';
import 'backend_http.dart';

/// Reads the signed-in member's lab bookings, and the report the lab attached
/// to one, from `backend/api` (`GET /v1/member/lab-bookings` and
/// `.../:id/report`) — the REST mirror of root's direct-Neon
/// `LabBookingRepository`.
///
/// Best-effort like every repository here: `null` when the backend is not
/// configured or unreachable, so the screen can say "could not load" instead
/// of showing an empty list that looks like "no bookings". The backend knows
/// the member from the session, so the `phone` root's version needs is
/// accepted here only to keep the two call sites identical.
class LabBookingRepository {
  const LabBookingRepository._();

  static const LabBookingRepository instance = LabBookingRepository._();

  /// Every booking the member has made, newest first. The report pages are
  /// only counted — each is a large image, read by [fetchReportPages] when the
  /// member opens the report.
  Future<List<LabBookingRecord>?> fetchForMember({String? phone}) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows =
          await BackendHttp.instance.request('GET', '/v1/member/lab-bookings')
              as List<dynamic>;
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          LabBookingRecord.fromJson(row),
      ];
    } catch (error) {
      BackendHttp.log('LabBookingRepository.fetchForMember failed', error: error);
      return null;
    }
  }

  /// The report pages (`data:` URIs) of one of the member's own bookings, in
  /// order. Someone else's booking is a 404 from the backend, read here as
  /// "could not load".
  Future<List<String>?> fetchReportPages({
    required int bookingId,
    String? phone,
  }) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final body =
          await BackendHttp.instance.request(
                'GET',
                '/v1/member/lab-bookings/$bookingId/report',
              )
              as Map<String, dynamic>;
      final pages = (body['pages'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      return [
        for (final page in pages)
          if ((page['image'] ?? '').toString().isNotEmpty)
            page['image'].toString(),
      ];
    } catch (error) {
      BackendHttp.log('LabBookingRepository.fetchReportPages failed', error: error);
      return null;
    }
  }
}
