import 'package:flutter/foundation.dart';

import '../../module/dietitian/dietitian.dart';
import '../../module/labtest/lab_package.dart';
import '../../module/labtest/lab_store.dart';
import 'backend_http.dart';

/// Reads the lab-test catalogue and the dietitian panel from `backend/api`'s
/// public `care` module (`GET /v1/public/care/lab-packages` /
/// `.../dietitians` — `care.controller.ts`/`care.service.ts`), the REST
/// mirror of root's direct-Neon `CareRepository`. Same contract as every
/// other repository here: best-effort, null on an unconfigured backend or a
/// network failure, so a member never sees an error screen for reference
/// data that simply hasn't loaded yet.
class CareRepository {
  const CareRepository._();

  static const CareRepository instance = CareRepository._();

  /// Test-only seams: a widget test can't reach a real backend, so this swaps
  /// in fixture data instead of exercising the network path — mirrors root's
  /// identical hooks on its own, direct-Neon `CareRepository`. Reset to null
  /// in `tearDown`.
  @visibleForTesting
  static Future<List<LabPackage>?> Function()? labPackagesOverride;
  @visibleForTesting
  static Future<List<LabCategory>?> Function()? labCategoriesOverride;
  @visibleForTesting
  static Future<List<LabStore>?> Function()? labStoresOverride;

  bool get isAvailable => BackendHttp.isConfigured;

  /// Every active package, each with its own profiles (and extras) attached
  /// — the package card shows the full breakdown with nothing else to tap,
  /// so the list itself has to carry it.
  Future<List<LabPackage>?> fetchLabPackages() async {
    final override = labPackagesOverride;
    if (override != null) {
      return override();
    }
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows =
          await BackendHttp.instance.request(
                'GET',
                '/v1/public/care/lab-packages',
                auth: false,
              )
              as List<dynamic>;
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          LabPackage(
            id: row['id'].toString(),
            slug: _str(row['slug']),
            name: _str(row['name']),
            categoryId: row['categoryId'] == null
                ? ''
                : row['categoryId'].toString(),
            isProfile: row['sourceTestId'] != null,
            testCount: _int(row['testCount']),
            profileCount: _int(row['profileCount']),
            rating: _str(row['rating']),
            booked: _str(row['booked']),
            reportIn: _str(row['reportIn']),
            price: formatRupees(_amount(row['price'])),
            mrp: formatRupees(_amount(row['mrp'])),
            saved: _amount(row['saved']) > 0
                ? formatRupees(_amount(row['saved']))
                : '',
            profiles: _profiles(row['profiles'], isExtra: false),
            inheritsFrom: _orNull(row['inheritsFrom']),
            inheritsSummary: _orNull(row['inheritsSummary']),
            extrasLabel: _orNull(row['extrasLabel']),
            extras: _profiles(row['profiles'], isExtra: true),
            forWhom: _str(row['forWhom']),
            ageRange: _str(row['ageRange']),
            preparation: _str(row['preparation']),
            sample: _str(row['sample']),
            organs: _stringList(row['organs']),
            about: _str(row['about']),
          ),
      ];
    } catch (error) {
      BackendHttp.log('CareRepository.fetchLabPackages failed', error: error);
      return null;
    }
  }

  /// "Explore by health concern" — every active category, each carrying how
  /// many active packages currently sit under it (`GET
  /// /v1/public/care/lab-categories` — `CareService.listLabCategories`).
  Future<List<LabCategory>?> fetchLabCategories() async {
    final override = labCategoriesOverride;
    if (override != null) {
      return override();
    }
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows =
          await BackendHttp.instance.request(
                'GET',
                '/v1/public/care/lab-categories',
                auth: false,
              )
              as List<dynamic>;
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          LabCategory(
            id: row['id'].toString(),
            name: _str(row['name']),
            image: _str(row['image']),
            testCount: _int(row['testCount']),
          ),
      ];
    } catch (error) {
      BackendHttp.log('CareRepository.fetchLabCategories failed', error: error);
      return null;
    }
  }

  /// Every branch currently open for lab collection (`GET
  /// /v1/public/care/lab-stores` — `BookingService.listLabStores`), for the
  /// lab checkout's "Branch" row. Unlike [fetchLabPackages]/
  /// [fetchLabCategories], there is no bundled fallback for this one: a
  /// branch this app does not yet know about (or one switched off since the
  /// app's own `StoreDirectory` was bundled) must never be offered, so a
  /// failed read simply leaves the picker showing nothing to choose rather
  /// than a stale guess.
  Future<List<LabStore>?> fetchLabStores() async {
    final override = labStoresOverride;
    if (override != null) {
      return override();
    }
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows =
          await BackendHttp.instance.request(
                'GET',
                '/v1/public/care/lab-stores',
                auth: false,
              )
              as List<dynamic>;
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          LabStore(
            id: _int(row['id']),
            code: _str(row['code']),
            name: _str(row['name']),
            area: _str(row['area']),
            city: _str(row['city']),
            pincode: _str(row['pincode']),
          ),
      ];
    } catch (error) {
      BackendHttp.log('CareRepository.fetchLabStores failed', error: error);
      return null;
    }
  }

  /// Every active dietitian. [Dietitian.initials] has no field of its own —
  /// derived from [Dietitian.name] here, matching root's identical rule.
  Future<List<Dietitian>?> fetchDietitians() async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows =
          await BackendHttp.instance.request(
                'GET',
                '/v1/public/care/dietitians',
                auth: false,
              )
              as List<dynamic>;
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          Dietitian(
            id: row['id'].toString(),
            name: _str(row['name']),
            qualification: _str(row['qualification']),
            focus: _stringList(row['focus']),
            experienceYears: _int(row['experienceYears']),
            languages: _stringList(row['languages']),
            fee: _amount(row['fee']),
            nextSlot: _str(row['nextSlot']),
            initials: _initialsFor(_str(row['name'])),
          ),
      ];
    } catch (error) {
      BackendHttp.log('CareRepository.fetchDietitians failed', error: error);
      return null;
    }
  }

  static List<LabProfile> _profiles(Object? raw, {required bool isExtra}) {
    if (raw is! List) {
      return const [];
    }
    return [
      for (final row in raw.cast<Map<String, dynamic>>())
        if (_bool(row['isExtra']) == isExtra)
          LabProfile(
            _str(row['emoji']),
            _str(row['name']),
            _int(row['parameters']),
          ),
    ];
  }

  /// "Dr. Anjali Menon" → "AM" — the first letter of the first two words,
  /// skipping a bare "Dr."/"Mr."/"Mrs." title so the initials are not just
  /// "D" twice over. Mirrors root's identical helper.
  static String _initialsFor(String name) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && w.replaceAll('.', '').isNotEmpty)
        .where(
          (w) => !{
            'dr',
            'mr',
            'mrs',
            'ms',
          }.contains(w.replaceAll('.', '').toLowerCase()),
        )
        .toList();
    if (words.isEmpty) {
      return '';
    }
    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }
    return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }

  static String _str(Object? v) => (v ?? '').toString();

  static List<String> _stringList(Object? v) =>
      v is List ? [for (final item in v) item.toString()] : const [];

  static int _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// A `numeric` column, serialized as a string by the backend — rounded to
  /// whole rupees, same as every price in this catalogue is written and
  /// shown.
  static int _amount(Object? v) {
    final parsed = double.tryParse(v?.toString() ?? '');
    return parsed == null ? 0 : parsed.round();
  }

  static bool _bool(Object? v) => v == true;

  static String? _orNull(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }
}
