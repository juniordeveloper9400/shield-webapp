import '../../module/dietitian/dietitian.dart';
import '../../module/labtest/lab_package.dart';
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

  bool get isAvailable => BackendHttp.isConfigured;

  /// Every active package, each with its own profiles (and extras) attached
  /// — the package card shows the full breakdown with nothing else to tap,
  /// so the list itself has to carry it.
  Future<List<LabPackage>?> fetchLabPackages() async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await BackendHttp.instance.request(
        'GET',
        '/v1/public/care/lab-packages',
        auth: false,
      ) as List<dynamic>;
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          LabPackage(
            id: row['id'].toString(),
            slug: _str(row['slug']),
            name: _str(row['name']),
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

  /// Every active dietitian. [Dietitian.initials] has no field of its own —
  /// derived from [Dietitian.name] here, matching root's identical rule.
  Future<List<Dietitian>?> fetchDietitians() async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await BackendHttp.instance.request(
        'GET',
        '/v1/public/care/dietitians',
        auth: false,
      ) as List<dynamic>;
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
          LabProfile(_str(row['emoji']), _str(row['name']), _int(row['parameters'])),
    ];
  }

  /// "Dr. Anjali Menon" → "AM" — the first letter of the first two words,
  /// skipping a bare "Dr."/"Mr."/"Mrs." title so the initials are not just
  /// "D" twice over. Mirrors root's identical helper.
  static String _initialsFor(String name) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && w.replaceAll('.', '').isNotEmpty)
        .where((w) => !{'dr', 'mr', 'mrs', 'ms'}.contains(
              w.replaceAll('.', '').toLowerCase(),
            ))
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
