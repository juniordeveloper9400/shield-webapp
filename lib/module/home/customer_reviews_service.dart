import 'package:flutter/foundation.dart';

import '../../data/backend/backend_http.dart';
import '../../data/backend/customer_review_repository.dart';
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
/// (see [CustomerReviewRepository]) and keeps it in memory. [items] is
/// that list minus any row the in-app player cannot stream (a leftover
/// YouTube link, a bundled asset path that no longer ships) — there is no
/// bundled fallback, so the reel is simply absent until the admin uploads a
/// real video.
class CustomerReviewsService extends ChangeNotifier {
  CustomerReviewsService._();

  static final CustomerReviewsService instance = CustomerReviewsService._();

  CustomerReviewsStatus _status = CustomerReviewsStatus.idle;
  CustomerReviewsStatus get status => _status;

  List<CustomerReviewItem> _admin = const [];

  /// Whether a load would actually reach the backend.
  bool get isConfigured => BackendHttp.isConfigured;

  bool get isLoading => _status == CustomerReviewsStatus.loading;

  /// The clips the reel shows — whatever the admin has switched on and
  /// uploaded a playable video for.
  List<CustomerReviewItem> get items => _admin;

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
    if (!BackendHttp.isConfigured) {
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
        final playable = _playable(clips);
        _set(
          playable.isEmpty
              ? CustomerReviewsStatus.empty
              : CustomerReviewsStatus.ready,
          playable,
        );
      }
    } catch (error) {
      BackendHttp.log('CustomerReviewsService load failed', error: error);
      _set(CustomerReviewsStatus.error, const []);
    } finally {
      _inFlight = null;
    }
  }

  /// Only clips the in-app player can stream — an old row that still points
  /// at YouTube or a bundled file would be a card that does nothing when tapped.
  static List<CustomerReviewItem> _playable(List<CustomerReviewItem> clips) =>
      clips.where((clip) => clip.isPlayable).toList(growable: false);

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
    final playable = _playable(clips);
    _set(
      playable.isEmpty
          ? CustomerReviewsStatus.empty
          : CustomerReviewsStatus.ready,
      List<CustomerReviewItem>.unmodifiable(playable),
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
