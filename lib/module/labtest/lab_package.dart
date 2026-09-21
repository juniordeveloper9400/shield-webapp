// formatRupees lives at the app root now that the wallet needs it too. It is
// re-exported here so callers reaching for it through the lab catalogue —
// where every price in this file is grouped by it — keep working.
export '../../money.dart' show formatRupees;

/// "Explore by health concern" — one row of `app.lab_category` (see
/// `CareRepository.fetchLabCategories`), never hardcoded here. [testCount] is
/// how many active [LabPackage]s currently sit under it, worked out by the
/// database at read time.
class LabCategory {
  final String id;
  final String name;

  /// An uploaded data URI; empty shows a plain placeholder tile.
  final String image;
  final int testCount;

  const LabCategory({
    required this.id,
    required this.name,
    this.image = '',
    this.testCount = 0,
  });
}

/// One profile inside a diagnostic package, e.g. "CBC · 24 parameters".
class LabProfile {
  final String emoji;
  final String name;
  final int parameters;

  const LabProfile(this.emoji, this.name, this.parameters);
}

/// A bookable diagnostic package — read from `app.lab_package` (see
/// `CareRepository.fetchLabPackages`), never hardcoded here. What the admin
/// has not filled in for a given package (rating, booked count, an
/// "inherits from" rollup, …) is simply blank, which every reader here
/// already treats as "nothing to show" rather than a placeholder value.
class LabPackage {
  final String id;
  final String slug;
  final String name;

  /// Which "Explore by health concern" tile this sits under; empty when the
  /// package carries no category.
  final String categoryId;

  /// True for the one-test listing the console keeps for a test or group test
  /// switched on with "Show in the app" (`app.lab_package.source_test_id`,
  /// migration 0056) — a profile / test in "Top Profiles and Tests" — and false
  /// for a real package.
  final bool isProfile;
  final int testCount;
  final int profileCount;
  final String rating;
  final String booked;
  final String reportIn;
  final String price;
  final String mrp;

  /// The grouped rupee amount saved, e.g. "333" — blank or zero means
  /// nothing to call out. Use [savedLabel] to render it.
  final String saved;

  /// Profiles listed directly on the card.
  final List<LabProfile> profiles;

  /// Name of a package this one fully contains, shown as a rolled-up row
  /// instead of repeating every profile.
  final String? inheritsFrom;
  final String? inheritsSummary;

  /// Extras beyond the inherited package, e.g. "+ 2 MORE TESTS · DIABETES".
  final String? extrasLabel;
  final List<LabProfile> extras;

  // ---- Detail-screen fields ----

  /// Who the package is for, e.g. 'For Male & Female'.
  final String forWhom;

  /// Eligible age range, e.g. '5-99 yrs'.
  final String ageRange;

  /// What the patient must do beforehand, e.g. '12 hrs fasting'.
  final String preparation;

  /// What is collected, e.g. 'Blood, Urine'.
  final String sample;

  /// Organs and systems the panel covers, shown as chips.
  final List<String> organs;

  final String about;

  const LabPackage({
    required this.id,
    this.slug = '',
    required this.name,
    this.categoryId = '',
    this.isProfile = false,
    required this.testCount,
    required this.profileCount,
    this.rating = '',
    this.booked = '',
    this.reportIn = '',
    required this.price,
    required this.mrp,
    this.saved = '',
    this.profiles = const [],
    this.inheritsFrom,
    this.inheritsSummary,
    this.extrasLabel,
    this.extras = const [],
    this.forWhom = '',
    this.ageRange = '',
    this.preparation = '',
    this.sample = '',
    this.organs = const [],
    this.about = '',
  });

  /// [price] and [mrp] are written pre-grouped for display; these are the
  /// numbers behind them, which is what a multi-patient booking needs.
  int get priceValue => _toInt(price);

  int get mrpValue => _toInt(mrp);

  int get savedValue => _toInt(saved);

  /// "Saved ₹333", or blank when there is nothing to save.
  String get savedLabel => savedValue > 0 ? 'Saved ₹$saved' : '';

  /// '46.67% off', matching the way the reference rounds it.
  String get discountLabel {
    if (mrpValue <= 0 || mrpValue <= priceValue) {
      return '';
    }
    final percent = (mrpValue - priceValue) / mrpValue * 100;
    return '${percent.toStringAsFixed(2)}% off';
  }

  static int _toInt(String amount) =>
      int.tryParse(amount.replaceAll(',', '').trim()) ?? 0;
}
