import '../../module/home/customer_reviews.dart';
import 'backend_http.dart';

/// Reads "What our customers have to say" from `backend/api`'s
/// `GET /v1/public/catalogue/review-videos` — see `catalogue.service.ts`'s
/// `listActiveReviewVideos`.
///
/// Read-only. Clips are added, ordered and hidden from the pharmacy admin
/// console (`shieldweb`), never from the app; this repository only lists
/// what the admin has switched on.
///
/// Best-effort: with an unconfigured backend (tests, a build with no
/// `BACKEND_API_BASE_URL`) or the network down, [listActive] returns `null`
/// so the caller can tell "could not load" from "the admin has added
/// nothing yet" and fall back to the clips bundled with the app.
class CustomerReviewRepository {
  const CustomerReviewRepository._();

  static const CustomerReviewRepository instance =
      CustomerReviewRepository._();

  /// Whether a read would actually reach the backend.
  bool get isAvailable => BackendHttp.isConfigured;

  /// Every clip the admin has marked active, in display order.
  ///
  /// Returns `null` (not an empty list) when the backend is off or
  /// unreachable, so a transient failure does not blank the reel — the
  /// caller falls back to the bundled clips instead.
  Future<List<CustomerReviewItem>?> listActive() async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await BackendHttp.instance.request(
        'GET',
        '/v1/public/catalogue/review-videos',
        auth: false,
      ) as List<dynamic>;
      return rows
          .cast<Map<String, dynamic>>()
          .map(_fromRow)
          .whereType<CustomerReviewItem>()
          .toList(growable: false);
    } catch (error) {
      BackendHttp.log('CustomerReviewRepository.listActive failed', error: error);
      return null;
    }
  }

  /// Maps one row to a [CustomerReviewItem], or `null` when it has no name or
  /// no clip to play — a row like that has nothing a card can show.
  static CustomerReviewItem? _fromRow(Map<String, dynamic> row) {
    final name = (row['name'] as String?)?.trim() ?? '';
    final video = (row['videoUrl'] as String?)?.trim() ?? '';
    if (name.isEmpty || video.isEmpty) {
      return null;
    }
    final subtitle = (row['subtitle'] as String?)?.trim();
    final thumbnail = (row['thumbnail'] as String?)?.trim();
    final uuid = (row['uuid'] as String?)?.trim();
    return CustomerReviewItem(
      id: (uuid?.isNotEmpty ?? false) ? uuid! : video,
      name: name,
      video: video,
      subtitle: (subtitle == null || subtitle.isEmpty) ? null : subtitle,
      thumbnail: (thumbnail == null || thumbnail.isEmpty) ? null : thumbnail,
    );
  }
}
