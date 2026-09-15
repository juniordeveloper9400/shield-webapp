// formatRupees lives at the app root now that the wallet needs it too. It is
// re-exported here so callers reaching for it through the lab catalogue —
// where every price in this file is grouped by it — keep working.
export '../../money.dart' show formatRupees;

/// One profile inside a diagnostic package, e.g. "CBC · 24 parameters".
class LabProfile {
  final String emoji;
  final String name;
  final int parameters;

  const LabProfile(this.emoji, this.name, this.parameters);
}

/// A bookable diagnostic package.
class LabPackage {
  final String name;
  final int testCount;
  final int profileCount;
  final String rating;
  final String booked;
  final String reportIn;
  final String price;
  final String mrp;
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
    required this.name,
    required this.testCount,
    required this.profileCount,
    required this.rating,
    required this.booked,
    required this.reportIn,
    required this.price,
    required this.mrp,
    required this.saved,
    this.profiles = const [],
    this.inheritsFrom,
    this.inheritsSummary,
    this.extrasLabel,
    this.extras = const [],
    this.forWhom = 'For Male & Female',
    this.ageRange = '5-99 yrs',
    this.preparation = '12 hrs fasting',
    this.sample = 'Blood, Urine',
    this.organs = const [],
    this.about = '',
  });

  /// [price] and [mrp] are written pre-grouped for display; these are the
  /// numbers behind them, which is what a multi-patient booking needs.
  int get priceValue => _toInt(price);

  int get mrpValue => _toInt(mrp);

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

/// Published packages and individual tests.
class LabCatalogue {
  const LabCatalogue._();

  static const LabPackage preventivePlus = LabPackage(
    name: 'Preventive Plus',
    testCount: 83,
    profileCount: 8,
    rating: '4.83',
    booked: '12k+ booked',
    reportIn: '15 hr',
    price: '999',
    mrp: '2,498',
    saved: 'Saved ₹333 with coupon code',
    preparation: '10 hrs fasting',
    organs: [
      'Liver',
      'Kidneys',
      'Heart',
      'Thyroid Gland',
      'Blood Vessels',
      'Bones',
    ],
    about:
        'A broad first look at how the body is running: blood counts, liver '
        'and kidney function, cholesterol, thyroid, blood sugar, and the two '
        'vitamins most commonly found short. Suited to a yearly check when '
        'there is nothing specific to investigate.',
    profiles: [
      LabProfile('🩸', 'CBC', 24),
      LabProfile('🫀', 'LFT', 12),
      LabProfile('🧪', 'Urine Routine', 21),
      LabProfile('🫁', 'KFT', 11),
      LabProfile('🥗', 'Lipid Profile', 9),
      LabProfile('🦋', 'Thyroid Profile', 3),
      LabProfile('💊', 'Blood Glucose', 1),
      LabProfile('💊', 'Vitamin B12', 1),
      LabProfile('☀️', 'Vitamin D', 1),
    ],
  );

  static const LabPackage activeLife = LabPackage(
    name: 'Active Life',
    testCount: 85,
    profileCount: 8,
    rating: '4.92',
    booked: '8k+ booked',
    reportIn: '15 hr',
    price: '1,299',
    mrp: '3,248',
    saved: 'Saved ₹433 with coupon code',
    inheritsFrom: 'Everything in Preventive Plus',
    inheritsSummary: 'All 83 tests · 8 profiles',
    extrasLabel: '+ 2 MORE TESTS · DIABETES',
    organs: [
      'Liver',
      'Kidneys',
      'Pancreas',
      'Heart',
      'Blood Vessels',
      'Thyroid Gland',
    ],
    about:
        'Everything in Preventive Plus, plus the two markers that show how '
        'blood sugar has behaved over the past three months rather than on '
        'the morning of the test.',
    extras: [
      LabProfile('🩸', 'HbA1c', 0),
      LabProfile('💠', 'Average blood glucose', 0),
    ],
  );

  static const LabPackage completeCare = LabPackage(
    name: 'Complete Care',
    testCount: 92,
    profileCount: 10,
    rating: '4.88',
    booked: '5k+ booked',
    reportIn: '18 hr',
    price: '1,799',
    mrp: '4,100',
    saved: 'Saved ₹560 with coupon code',
    inheritsFrom: 'Everything in Active Life',
    inheritsSummary: 'All 85 tests · 8 profiles',
    extrasLabel: '+ 7 MORE TESTS · HEART & IRON',
    preparation: '12 hrs fasting',
    sample: 'Blood, Urine',
    organs: [
      'Liver',
      'Kidneys',
      'Pancreas',
      'Heart',
      'Blood Vessels',
      'Thyroid Gland',
      'Bone Marrow',
    ],
    about:
        'Everything in Active Life, with cardiac risk markers and iron '
        'studies added. The fullest panel offered, and the one to choose '
        'when heart risk or anaemia is the reason for testing.',
    extras: [
      LabProfile('🫀', 'Cardiac Risk Markers', 5),
      LabProfile('🧲', 'Iron Studies', 2),
    ],
  );

  /// The lab's real special-package price list — fixed-price panels for a
  /// named clinical purpose (an anaemia work-up, a fertility panel, a
  /// pre-surgical or post-COVID panel, …), each priced against the actual
  /// lab price list rather than a bundled/discount-code scheme. [price] is
  /// what the lab actually charges for the panel; [mrp] is its listed price
  /// as billed test-by-test, so [discountLabel] still reads correctly. Every
  /// parameter is counted as one test — the price list does not break a
  /// named profile (e.g. "Lipid profile") down into its own analyte count,
  /// so [testCount] and [profileCount] both equal how many parameters are
  /// listed for that panel.
  static const List<LabPackage> specialPackages = [
    LabPackage(
      name: 'Anemia Profile',
      testCount: 6,
      profileCount: 6,
      rating: '4.7',
      booked: '900+ booked',
      reportIn: '24 hrs',
      price: '1,780',
      mrp: '2,580',
      saved: 'Saved ₹800',
      about:
          'Checks for anaemia and why it might be happening — blood count, '
          'how fast new red cells are being made, iron stores, and the two '
          'vitamins most often behind a low count.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'CBC', 1),
        LabProfile('🧪', 'Reticulocyte Count', 1),
        LabProfile('🧪', 'Iron Studies', 1),
        LabProfile('🧪', 'Vit B12', 1),
        LabProfile('🧪', 'Folic acid', 1),
        LabProfile('🧪', 'CRP', 1),
      ],
    ),
    LabPackage(
      name: 'Anemia Profile - Nutritional',
      testCount: 5,
      profileCount: 5,
      rating: '4.7',
      booked: '700+ booked',
      reportIn: '24 hrs',
      price: '1,880',
      mrp: '2,680',
      saved: 'Saved ₹800',
      about:
          'The nutritional side of an anaemia work-up: blood count, iron '
          'stores and how much of it is actually available, plus B12 and '
          'folate.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'CBC', 1),
        LabProfile('🧪', 'Iron Studies', 1),
        LabProfile('🧪', 'Vit B12', 1),
        LabProfile('🧪', 'Folic acid', 1),
        LabProfile('🧪', 'Ferritin', 1),
      ],
    ),
    LabPackage(
      name: 'Bad Obstetric History Panel',
      testCount: 6,
      profileCount: 6,
      rating: '4.6',
      booked: '300+ booked',
      reportIn: '48 hrs',
      price: '5,100',
      mrp: '6,350',
      saved: 'Saved ₹1,250',
      about:
          'For a history of pregnancy loss — thyroid, autoimmune and clotting '
          'markers that are screened for together when a cause is being '
          'investigated.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      forWhom: 'For Female',
      profiles: [
        LabProfile('🧪', 'TSH', 1),
        LabProfile('🧪', 'ANA', 1),
        LabProfile('🧪', 'ACLA IgG & IgM', 1),
        LabProfile('🧪', 'APLA IgG & IgM', 1),
        LabProfile('🧪', 'TORCH IgG & IgM', 1),
        LabProfile('🧪', 'Lupus Anticoagulant', 1),
      ],
    ),
    LabPackage(
      name: 'Cancer Detection Panel - Male',
      testCount: 8,
      profileCount: 8,
      rating: '4.6',
      booked: '400+ booked',
      reportIn: '48 hrs',
      price: '3,950',
      mrp: '4,900',
      saved: 'Saved ₹950',
      about:
          'A tumour-marker screen for the cancers most relevant to men, '
          'alongside a blood count and smear.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      forWhom: 'For Male',
      profiles: [
        LabProfile('🧪', 'AFP', 1),
        LabProfile('🧪', 'BHCG', 1),
        LabProfile('🧪', 'CEA', 1),
        LabProfile('🧪', 'PSA - Total & Free', 1),
        LabProfile('🧪', 'CA 19-9', 1),
        LabProfile('🧪', 'Thyroglobulin', 1),
        LabProfile('🧪', 'CBC', 1),
        LabProfile('🧪', 'Peripheral Smear', 1),
      ],
    ),
    LabPackage(
      name: 'Cancer Detection Panel - Female',
      testCount: 8,
      profileCount: 8,
      rating: '4.6',
      booked: '400+ booked',
      reportIn: '48 hrs',
      price: '3,400',
      mrp: '4,350',
      saved: 'Saved ₹950',
      about:
          'A tumour-marker screen for the cancers most relevant to women, '
          'alongside a blood count and smear.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      forWhom: 'For Female',
      profiles: [
        LabProfile('🧪', 'AFP', 1),
        LabProfile('🧪', 'BHCG', 1),
        LabProfile('🧪', 'CEA', 1),
        LabProfile('🧪', 'CA 125', 1),
        LabProfile('🧪', 'CA 19-9', 1),
        LabProfile('🧪', 'Thyroglobulin', 1),
        LabProfile('🧪', 'CBC', 1),
        LabProfile('🧪', 'Peripheral Smear', 1),
      ],
    ),
    LabPackage(
      name: 'Excessive Hair Growth (Hirsutism) Panel',
      testCount: 6,
      profileCount: 6,
      rating: '4.6',
      booked: '500+ booked',
      reportIn: '24 hrs',
      price: '2,250',
      mrp: '3,200',
      saved: 'Saved ₹950',
      about:
          'The hormone panel behind unusual hair growth — pituitary, thyroid '
          'and androgen markers read together.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      forWhom: 'For Female',
      profiles: [
        LabProfile('🧪', 'FSH', 1),
        LabProfile('🧪', 'LH', 1),
        LabProfile('🧪', 'Prolactin', 1),
        LabProfile('🧪', 'TSH', 1),
        LabProfile('🧪', 'Testosterone - Total & Free', 1),
        LabProfile('🧪', 'DHEAS', 1),
      ],
    ),
    LabPackage(
      name: 'Immunoglobulin Profile',
      testCount: 4,
      profileCount: 4,
      rating: '4.6',
      booked: '600+ booked',
      reportIn: '24 hrs',
      price: '1,350',
      mrp: '2,000',
      saved: 'Saved ₹650',
      about:
          'The four immunoglobulin classes — a first look at how the immune '
          'system is responding.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'IgA', 1),
        LabProfile('🧪', 'IgE', 1),
        LabProfile('🧪', 'IgG', 1),
        LabProfile('🧪', 'IgM', 1),
      ],
    ),
    LabPackage(
      name: 'Ovarian Reserve Panel',
      testCount: 4,
      profileCount: 4,
      rating: '4.7',
      booked: '700+ booked',
      reportIn: '48 hrs',
      price: '2,100',
      mrp: '2,750',
      saved: 'Saved ₹650',
      about:
          'Reads how many eggs remain and how the cycle is being driven — the '
          'standard panel for a fertility work-up.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      forWhom: 'For Female',
      profiles: [
        LabProfile('🧪', 'FSH', 1),
        LabProfile('🧪', 'LH', 1),
        LabProfile('🧪', 'E2', 1),
        LabProfile('🧪', 'AMH', 1),
      ],
    ),
    LabPackage(
      name: 'Prostate Profile',
      testCount: 2,
      profileCount: 2,
      rating: '4.7',
      booked: '1.2k+ booked',
      reportIn: '24 hrs',
      price: '970',
      mrp: '1,450',
      saved: 'Saved ₹480',
      about: 'PSA, total and free, and the ratio between them.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      forWhom: 'For Male',
      profiles: [
        LabProfile('🧪', 'PSA - Total & Free', 1),
        LabProfile('🧪', 'Ratio', 1),
      ],
    ),
    LabPackage(
      name: 'Osteoporosis Profile',
      testCount: 8,
      profileCount: 8,
      rating: '4.6',
      booked: '500+ booked',
      reportIn: '48 hrs',
      price: '2,200',
      mrp: '3,160',
      saved: 'Saved ₹960',
      about:
          'Everything bone health turns on: the minerals bone is built from, '
          'the hormones that regulate them, and vitamin D.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'Calcium', 1),
        LabProfile('🧪', 'Phosphorus', 1),
        LabProfile('🧪', 'ALP', 1),
        LabProfile('🧪', '25-OH Vitamin D', 1),
        LabProfile('🧪', 'PTH', 1),
        LabProfile('🧪', 'E2', 1),
        LabProfile('🧪', 'Magnesium', 1),
        LabProfile('🧪', 'Zinc', 1),
      ],
    ),
    LabPackage(
      name: 'Diabetic Panel 1',
      testCount: 4,
      profileCount: 4,
      rating: '4.8',
      booked: '2k+ booked',
      reportIn: '24 hrs',
      price: '405',
      mrp: '670',
      saved: 'Saved ₹265',
      about: 'A quick diabetes and kidney-risk check.',
      preparation: 'Fasting required (8-10 hrs)',
      sample: 'Blood, Urine',
      profiles: [
        LabProfile('🧪', 'FBS', 1),
        LabProfile('🧪', 'Cholesterol', 1),
        LabProfile('🧪', 'HbA1c', 1),
        LabProfile('🧪', 'Urine ACR', 1),
      ],
    ),
    LabPackage(
      name: 'Viral Hepatitis Panel',
      testCount: 4,
      profileCount: 4,
      rating: '4.7',
      booked: '900+ booked',
      reportIn: '24 hrs',
      price: '1,470',
      mrp: '2,200',
      saved: 'Saved ₹730',
      about: 'Screens for the four hepatitis viruses most often tested for together.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'HAV IgM', 1),
        LabProfile('🧪', 'HBsAg', 1),
        LabProfile('🧪', 'HCV', 1),
        LabProfile('🧪', 'HEV IgM', 1),
      ],
    ),
    LabPackage(
      name: 'Fertility Panel',
      testCount: 7,
      profileCount: 7,
      rating: '4.7',
      booked: '800+ booked',
      reportIn: '24 hrs',
      price: '1,450',
      mrp: '2,350',
      saved: 'Saved ₹900',
      about: 'The core hormone panel behind a fertility work-up.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'FSH', 1),
        LabProfile('🧪', 'LH', 1),
        LabProfile('🧪', 'Prolactin', 1),
        LabProfile('🧪', 'E2', 1),
        LabProfile('🧪', 'E3', 1),
        LabProfile('🧪', 'TSH', 1),
        LabProfile('🧪', 'Testosterone', 1),
      ],
    ),
    LabPackage(
      name: 'Infertility Profile - Male',
      testCount: 9,
      profileCount: 9,
      rating: '4.6',
      booked: '500+ booked',
      reportIn: '24 hrs',
      price: '1,350',
      mrp: '2,210',
      saved: 'Saved ₹860',
      about: 'A full infertility work-up for a male partner.',
      preparation: 'Fasting required (8-10 hrs)',
      sample: 'Blood, Urine, Semen',
      forWhom: 'For Male',
      profiles: [
        LabProfile('🧪', 'CBC & ESR', 1),
        LabProfile('🧪', 'Blood Group', 1),
        LabProfile('🧪', 'FBS', 1),
        LabProfile('🧪', 'Urine RE', 1),
        LabProfile('🧪', 'Semen Analysis', 1),
        LabProfile('🧪', 'TSH', 1),
        LabProfile('🧪', 'FSH', 1),
        LabProfile('🧪', 'LH', 1),
        LabProfile('🧪', 'Prolactin', 1),
      ],
    ),
    LabPackage(
      name: 'Infertility Profile - Female',
      testCount: 8,
      profileCount: 8,
      rating: '4.6',
      booked: '500+ booked',
      reportIn: '24 hrs',
      price: '850',
      mrp: '1,320',
      saved: 'Saved ₹470',
      about: 'A full infertility work-up for a female partner.',
      preparation: 'Fasting required (8-10 hrs)',
      sample: 'Blood, Urine',
      forWhom: 'For Female',
      profiles: [
        LabProfile('🧪', 'CBC & ESR', 1),
        LabProfile('🧪', 'Blood Group', 1),
        LabProfile('🧪', 'FBS', 1),
        LabProfile('🧪', 'Urine RE', 1),
        LabProfile('🧪', 'TSH', 1),
        LabProfile('🧪', 'FSH', 1),
        LabProfile('🧪', 'LH', 1),
        LabProfile('🧪', 'Prolactin', 1),
      ],
    ),
    LabPackage(
      name: 'Liver Function Test (LFT) Max',
      testCount: 5,
      profileCount: 5,
      rating: '4.7',
      booked: '1.2k+ booked',
      reportIn: '24 hrs',
      price: '850',
      mrp: '1,320',
      saved: 'Saved ₹470',
      about: 'The full liver panel, with the extra markers a basic LFT leaves out.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'LFT', 1),
        LabProfile('🧪', 'PT-INR', 1),
        LabProfile('🧪', 'Gamma GT', 1),
        LabProfile('🧪', 'LDH', 1),
        LabProfile('🧪', 'HBsAg', 1),
      ],
    ),
    LabPackage(
      name: 'Kidney Function Test (RFT) Max',
      testCount: 11,
      profileCount: 11,
      rating: '4.7',
      booked: '900+ booked',
      reportIn: '24 hrs',
      price: '1,300',
      mrp: '1,850',
      saved: 'Saved ₹550',
      about: 'The full kidney panel, well beyond a basic RFT.',
      preparation: 'Fasting required (8-10 hrs)',
      sample: 'Blood, Urine',
      profiles: [
        LabProfile('🧪', 'CBC & ESR', 1),
        LabProfile('🧪', 'Urine RE', 1),
        LabProfile('🧪', 'FBS', 1),
        LabProfile('🧪', 'Electrolytes - 4', 1),
        LabProfile('🧪', 'Total Protein', 1),
        LabProfile('🧪', 'Albumin', 1),
        LabProfile('🧪', 'Globulin', 1),
        LabProfile('🧪', 'ALP', 1),
        LabProfile('🧪', 'Calcium', 1),
        LabProfile('🧪', 'Phosphorus', 1),
        LabProfile('🧪', 'RFT & eGFR', 1),
      ],
    ),
    LabPackage(
      name: 'Thyroid Profile 2',
      testCount: 5,
      profileCount: 5,
      rating: '4.7',
      booked: '1.5k+ booked',
      reportIn: '24 hrs',
      price: '1,010',
      mrp: '1,750',
      saved: 'Saved ₹740',
      about: 'The extended thyroid panel, including the autoimmune markers a basic TFT leaves out.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'TFT', 1),
        LabProfile('🧪', 'FT3', 1),
        LabProfile('🧪', 'FT4', 1),
        LabProfile('🧪', 'ATPO', 1),
        LabProfile('🧪', 'ATG', 1),
      ],
    ),
    LabPackage(
      name: 'Diabetic Panel 2',
      testCount: 11,
      profileCount: 11,
      rating: '4.7',
      booked: '1.1k+ booked',
      reportIn: '24 hrs',
      price: '1,900',
      mrp: '2,790',
      saved: 'Saved ₹890',
      about: 'A complete diabetes work-up — sugar control, insulin response, and what long-term diabetes touches.',
      preparation: 'Fasting required (8-10 hrs)',
      sample: 'Blood, Urine',
      profiles: [
        LabProfile('🧪', 'CBC & ESR', 1),
        LabProfile('🧪', 'FBS', 1),
        LabProfile('🧪', 'PPBS', 1),
        LabProfile('🧪', 'HbA1c', 1),
        LabProfile('🧪', 'Lipid Profile', 1),
        LabProfile('🧪', 'RFT', 1),
        LabProfile('🧪', 'Electrolytes - 4', 1),
        LabProfile('🧪', 'Insulin', 1),
        LabProfile('🧪', 'C-Peptide', 1),
        LabProfile('🧪', 'Urine RE', 1),
        LabProfile('🧪', 'Urine ACR', 1),
      ],
    ),
    LabPackage(
      name: 'Dialysis Panel',
      testCount: 10,
      profileCount: 10,
      rating: '4.6',
      booked: '300+ booked',
      reportIn: '24 hrs',
      price: '950',
      mrp: '1,450',
      saved: 'Saved ₹500',
      about: 'The panel run before and through dialysis.',
      preparation: 'Fasting required (8-10 hrs)',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'CBC & ESR', 1),
        LabProfile('🧪', 'FBS', 1),
        LabProfile('🧪', 'Electrolytes - 4', 1),
        LabProfile('🧪', 'Total Protein', 1),
        LabProfile('🧪', 'Albumin', 1),
        LabProfile('🧪', 'Globulin', 1),
        LabProfile('🧪', 'Calcium', 1),
        LabProfile('🧪', 'Phosphorus', 1),
        LabProfile('🧪', 'RFT', 1),
        LabProfile('🧪', 'BUN', 1),
      ],
    ),
    LabPackage(
      name: 'Sexually Transmitted Disease (STD) Panel',
      testCount: 4,
      profileCount: 4,
      rating: '4.6',
      booked: '600+ booked',
      reportIn: '48 hrs',
      price: '3,050',
      mrp: '3,950',
      saved: 'Saved ₹900',
      about: 'Screens for the infections most commonly tested for as one panel.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'TPHA', 1),
        LabProfile('🧪', 'HSV I & II IgG & IgM', 1),
        LabProfile('🧪', 'Chlamydia IgG & IgM', 1),
        LabProfile('🧪', 'HIV I & II', 1),
      ],
    ),
    LabPackage(
      name: 'Hypertension Panel',
      testCount: 4,
      profileCount: 4,
      rating: '4.7',
      booked: '1.3k+ booked',
      reportIn: '24 hrs',
      price: '500',
      mrp: '820',
      saved: 'Saved ₹320',
      about: 'What a new or existing blood-pressure diagnosis is usually screened against.',
      preparation: 'Fasting required (8-10 hrs)',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'RBS', 1),
        LabProfile('🧪', 'Lipid Profile', 1),
        LabProfile('🧪', 'RFT', 1),
        LabProfile('🧪', 'Electrolytes - 4', 1),
      ],
    ),
    LabPackage(
      name: 'Thrombophilia Panel',
      testCount: 4,
      profileCount: 4,
      rating: '4.6',
      booked: '250+ booked',
      reportIn: '48 hrs',
      price: '3,250',
      mrp: '4,200',
      saved: 'Saved ₹950',
      about: 'The clotting-risk panel raised after an unexplained clot or repeated pregnancy loss.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'ACLA IgG & IgM', 1),
        LabProfile('🧪', 'APLA IgG & IgM', 1),
        LabProfile('🧪', 'Lupus Anticoagulant', 1),
        LabProfile('🧪', 'ANA', 1),
      ],
    ),
    LabPackage(
      name: 'Macrocytic Anemia Panel',
      testCount: 3,
      profileCount: 3,
      rating: '4.7',
      booked: '400+ booked',
      reportIn: '24 hrs',
      price: '1,125',
      mrp: '1,750',
      saved: 'Saved ₹625',
      about: 'Checks for the two vitamin deficiencies behind a large-cell anaemia.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'Vit B9', 1),
        LabProfile('🧪', 'Vit B12', 1),
        LabProfile('🧪', 'Peripheral Smear', 1),
      ],
    ),
    LabPackage(
      name: 'PCOD Profile 2',
      testCount: 7,
      profileCount: 7,
      rating: '4.7',
      booked: '900+ booked',
      reportIn: '48 hrs',
      price: '3,800',
      mrp: '4,770',
      saved: 'Saved ₹970',
      about: 'The extended hormone panel for PCOD — cycle-driving and androgen hormones read together.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      forWhom: 'For Female',
      profiles: [
        LabProfile('🧪', 'FSH', 1),
        LabProfile('🧪', 'LH', 1),
        LabProfile('🧪', 'Prolactin', 1),
        LabProfile('🧪', 'DHEAS', 1),
        LabProfile('🧪', 'E2', 1),
        LabProfile('🧪', 'Progesterone', 1),
        LabProfile('🧪', 'Testosterone - Total & Free', 1),
      ],
    ),
    LabPackage(
      name: 'Autoimmune Panel',
      testCount: 8,
      profileCount: 8,
      rating: '4.6',
      booked: '400+ booked',
      reportIn: '48 hrs',
      price: '3,050',
      mrp: '4,000',
      saved: 'Saved ₹950',
      about: 'The standard first panel for an autoimmune or rheumatological work-up.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'RA', 1),
        LabProfile('🧪', 'ASO', 1),
        LabProfile('🧪', 'CRP', 1),
        LabProfile('🧪', 'ANA', 1),
        LabProfile('🧪', 'ACCP', 1),
        LabProfile('🧪', 'IgG', 1),
        LabProfile('🧪', 'IgM', 1),
        LabProfile('🧪', 'IgA', 1),
      ],
    ),
    LabPackage(
      name: 'Pancreas Panel',
      testCount: 4,
      profileCount: 4,
      rating: '4.7',
      booked: '350+ booked',
      reportIn: '24 hrs',
      price: '1,150',
      mrp: '1,800',
      saved: 'Saved ₹650',
      about: 'The panel behind a pancreatic work-up — the two enzymes, and how insulin is responding.',
      preparation: 'Fasting required (8-10 hrs)',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'Amylase', 1),
        LabProfile('🧪', 'Lipase', 1),
        LabProfile('🧪', 'Insulin', 1),
        LabProfile('🧪', 'C-Peptide', 1),
      ],
    ),
    LabPackage(
      name: 'Vitamin Profile',
      testCount: 6,
      profileCount: 6,
      rating: '4.8',
      booked: '1.8k+ booked',
      reportIn: '24 hrs',
      price: '2,750',
      mrp: '3,650',
      saved: 'Saved ₹900',
      about: 'The vitamins and minerals most often found short — read together rather than one at a time.',
      preparation: 'No special preparation needed',
      sample: 'Blood',
      profiles: [
        LabProfile('🧪', 'Vitamin D', 1),
        LabProfile('🧪', 'Vitamin B12', 1),
        LabProfile('🧪', 'Vitamin B9', 1),
        LabProfile('🧪', 'Ionized Calcium', 1),
        LabProfile('🧪', 'Magnesium', 1),
        LabProfile('🧪', 'PTH', 1),
      ],
    ),
    LabPackage(
      name: 'Cardiac Profile',
      testCount: 14,
      profileCount: 14,
      rating: '4.8',
      booked: '1.5k+ booked',
      reportIn: '24 hrs',
      price: '4,550',
      mrp: '5,500',
      saved: 'Saved ₹950',
      about: 'A full cardiac-risk work-up — sugar control, lipids, kidney function, cardiac risk markers and an ECG, together.',
      preparation: 'Fasting required (8-10 hrs)',
      sample: 'Blood, ECG',
      organs: ['Heart', 'Blood Vessels', 'Kidneys'],
      profiles: [
        LabProfile('🧪', 'CBC & ESR', 1),
        LabProfile('🧪', 'FBS', 1),
        LabProfile('🧪', 'PPBS', 1),
        LabProfile('🧪', 'HbA1c', 1),
        LabProfile('🧪', 'Lipid Profile', 1),
        LabProfile('🧪', 'RFT', 1),
        LabProfile('🧪', 'Homocysteine', 1),
        LabProfile('🧪', 'Lipoprotein-A', 1),
        LabProfile('🧪', 'hs-CRP', 1),
        LabProfile('🧪', 'Iron Studies', 1),
        LabProfile('🧪', 'BUN', 1),
        LabProfile('🧪', 'Vitamin D', 1),
        LabProfile('🧪', 'Vitamin B12', 1),
        LabProfile('🧪', 'ECG', 1),
      ],
    ),
    LabPackage(
      name: 'Post-COVID-19 Panel - Basic',
      testCount: 5,
      profileCount: 5,
      rating: '4.6',
      booked: '600+ booked',
      reportIn: '24 hrs',
      price: '1,150',
      mrp: '1,880',
      saved: 'Saved ₹730',
      about: 'The basic panel for lingering symptoms after a COVID-19 infection.',
      preparation: 'No special preparation needed',
      sample: 'Blood, Chest X-ray',
      profiles: [
        LabProfile('🧪', 'CBC & ESR', 1),
        LabProfile('🧪', 'RFT', 1),
        LabProfile('🧪', 'LFT', 1),
        LabProfile('🧪', 'CRP', 1),
        LabProfile('🧪', 'D-Dimer & Chest X-ray', 1),
      ],
    ),
    LabPackage(
      name: 'Post-COVID-19 Panel - General',
      testCount: 7,
      profileCount: 7,
      rating: '4.6',
      booked: '400+ booked',
      reportIn: '48 hrs',
      price: '2,150',
      mrp: '3,130',
      saved: 'Saved ₹980',
      about: 'The general panel for lingering symptoms after a COVID-19 infection.',
      preparation: 'No special preparation needed',
      sample: 'Blood, Chest X-ray',
      profiles: [
        LabProfile('🧪', 'CBC & ESR', 1),
        LabProfile('🧪', 'RFT', 1),
        LabProfile('🧪', 'LFT', 1),
        LabProfile('🧪', 'CRP', 1),
        LabProfile('🧪', 'D-Dimer', 1),
        LabProfile('🧪', 'SARS-CoV-2 (COVID-19) Antibody IgG', 1),
        LabProfile('🧪', 'Ferritin & Chest X-ray', 1),
      ],
    ),
    LabPackage(
      name: 'Post-COVID-19 Panel - Advanced',
      testCount: 9,
      profileCount: 9,
      rating: '4.6',
      booked: '250+ booked',
      reportIn: '48 hrs',
      price: '6,500',
      mrp: '7,880',
      saved: 'Saved ₹1,380',
      about: 'The advanced panel for more significant lingering symptoms after a COVID-19 infection.',
      preparation: 'No special preparation needed',
      sample: 'Blood, Chest X-ray',
      profiles: [
        LabProfile('🧪', 'CBC & ESR', 1),
        LabProfile('🧪', 'RFT', 1),
        LabProfile('🧪', 'LFT', 1),
        LabProfile('🧪', 'LDH', 1),
        LabProfile('🧪', 'D-Dimer', 1),
        LabProfile('🧪', 'SARS-CoV-2 (COVID-19) Antibody IgG', 1),
        LabProfile('🧪', 'PCT', 1),
        LabProfile('🧪', 'IL-6', 1),
        LabProfile('🧪', 'Ferritin & Chest X-ray', 1),
      ],
    ),
  ];

  static const List<LabPackage> packages = [
    preventivePlus,
    activeLife,
    completeCare,
    ...specialPackages,
  ];

  /// Individually bookable profiles listed under the packages.
  static const List<LabProfile> topProfiles = [
    LabProfile('🩸', 'Complete Blood Count', 24),
    LabProfile('🦋', 'Thyroid Profile', 3),
    LabProfile('🥗', 'Lipid Profile', 9),
    LabProfile('🫁', 'Kidney Function Test', 11),
    LabProfile('🫀', 'Liver Function Test', 12),
    LabProfile('☀️', 'Vitamin D', 1),
  ];
}
