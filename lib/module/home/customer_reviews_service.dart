import 'package:flutter/foundation.dart';

import '../../data/neon/customer_review_repository.dart';
import '../../data/neon/neon_http.dart';
import 'customer_reviews.dart';

/// Where the customer-video load has got to.
enum CustomerReviewsStatus {
  /// Not asked for yet.
  idle,

  /// A load is in flight.
  loading,

  /// Loaded, with at least one clip the admin has switched on.
  ready,

  /// Loaded, but the admin has not added (or activated) any clip yet.
  empty,

  /// The database is off, unreachable, or returned an error.
  error,
}

/// "What our customers have to say" — the reel's single source of clips.
///
/// Loads every active row from `app.customer_review_video` once per session
/// (see [CustomerReviewRepository]) and keeps it in memory. [items] is what
/// the reel actually shows: the admin's clips when there are any, and the
/// clips bundled with the app — [CustomerReviews.reviews] — whenever the
/// admin hasn't added one yet or the database can't be reached, so the reel
/// is never blank.
class CustomerReviewsService extends ChangeNotifier {
  CustomerReviewsService._();

  static final CustomerReviewsService instance = CustomerReviewsService._();

  CustomerReviewsStatus _status = CustomerReviewsStatus.idle;
  CustomerReviewsStatus get status => _status;

  List<CustomerReviewItem> _admin = const [];

  /// Whether a load would actually reach the database.
  bool get isConfigured => NeonHttp.isConfigured;

  bool get isLoading => _status == CustomerReviewsStatus.loading;

  /// The clips the reel shows: the admin's, when the admin has switched any
  /// on; the clips bundled with the app otherwise.
  List<CustomerReviewItem> get items =>
      _admin.isNotEmpty ? _admin : CustomerReviews.reviews;

  Future<void>? _inFlight;

  /// Loads the reel the first time it is needed. Safe to call from
  /// `initState`: concurrent calls share one request and a finished load is a
  /// no-op. Call [refresh] to force a reload.
  Future<void> ensureLoaded() {
    if (_isSettled) {
      return Future.value();
    }
    return _inFlight ??= _load();
  }

  /// Drop what was loaded and fetch again — for the admin console's "Add
  /// clip" to show up without a restart, and for pull-to-refresh.
  Future<void> refresh() {
    _inFlight = null;
    _status = CustomerReviewsStatus.idle;
    return ensureLoaded();
  }

  bool get _isSettled =>
      _status == CustomerReviewsStatus.ready ||
      _status == CustomerReviewsStatus.empty ||
      _status == CustomerReviewsStatus.error;

  Future<void> _load() async {
    if (!NeonHttp.isConfigured) {
      _set(CustomerReviewsStatus.error, const []);
      _inFlight = null;
      return;
    }
    _status = CustomerReviewsStatus.loading;
    notifyListeners();
    try {
      final clips = await CustomerReviewRepository.instance.listActive();
      if (clips == null) {
        _set(CustomerReviewsStatus.error, const []);
      } else {
        _set(
          clips.isEmpty
              ? CustomerReviewsStatus.empty
              : CustomerReviewsStatus.ready,
          clips,
        );
      }
    } catch (error) {
      NeonHttp.log('CustomerReviewsService load failed', error: error);
      _set(CustomerReviewsStatus.error, const []);
    } finally {
      _inFlight = null;
    }
  }

  void _set(CustomerReviewsStatus status, List<CustomerReviewItem> clips) {
    _status = status;
    _admin = clips;
    notifyListeners();
  }

  /// Puts [clips] straight in, as if the admin's list had been read — for
  /// widget tests, which have no database. Leaves the service settled, so a
  /// widget's `ensureLoaded()` in `initState` is a no-op and the seed stands.
  @visibleForTesting
  void debugSeed(List<CustomerReviewItem> clips) {
    _inFlight = null;
    _set(
      clips.isEmpty
          ? CustomerReviewsStatus.empty
          : CustomerReviewsStatus.ready,
      List<CustomerReviewItem>.unmodifiable(clips),
    );
  }

  /// Drops any seeded/loaded reel back to the unasked state. Pair with
  /// [debugSeed] in a test `tearDown` so one test's seed does not leak into
  /// the next.
  @visibleForTesting
  void debugReset() {
    _inFlight = null;
    _set(CustomerReviewsStatus.idle, const []);
  }
}
