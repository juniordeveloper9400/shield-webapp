import 'package:flutter/material.dart';

import '../../data/backend/category_repository.dart';
import '../../theme/app_colors.dart';

/// One browsable sub-category — the unit both the home strip and the
/// Categories tab render as a card.
class SubCategory {
  final String label;
  final IconData icon;

  /// Product artwork. Null only where no photograph exists for the entry, in
  /// which case the card falls back to [icon].
  final String? image;

  final String offer;

  const SubCategory(
    this.label,
    this.icon, {
    this.image,
    this.offer = 'Up to 50% off',
  });
}

/// A group of sub-categories, with the artwork and tints the two surfaces need.
class CategoryGroup {
  /// Heading on the Categories tab: 'Personal Care'.
  final String title;

  /// Chip caption on the home strip, pre-wrapped: 'Personal\nCare'.
  final String tabLabel;

  final IconData icon;

  /// Artwork for the home strip's chip.
  final String? image;

  /// Promotional banner artwork displayed at the top of the group's listing.
  final String? bannerImage;

  /// Fill behind this group's panel on the Categories tab, and behind its chip
  /// on the home strip — one pastel per group, selected or not. The reference
  /// gives each group its own, which is what separates one panel from the next
  /// without needing a rule between them.
  final Color panelTint;

  final List<SubCategory> items;

  const CategoryGroup({
    required this.title,
    required this.tabLabel,
    required this.icon,
    required this.panelTint,
    required this.items,
    this.image,
    this.bannerImage,
  });

  /// 'View all personal care products' — the panel's closing link.
  String get viewAllLabel => 'View all $title products';
}

/// The single source of truth behind both the home "Shop by categories" strip
/// and the Categories tab, so the two can never drift apart.
///
/// Every entry that has a photograph carries one. Lab Tests is deliberately
/// the exception and sits last: those are bookings rather than products, and
/// the project has no artwork for them, so its cards fall back to icons.
class CategoryCatalogue {
  const CategoryCatalogue._();

  /// The live catalogue — the admin console's own categories once
  /// [CategoryCatalog] has loaded them, otherwise [_seed].
  static List<CategoryGroup> get groups => CategoryCatalog.instance.groups;

  /// The bundled fallback: the categories Sahakar 360 shipped with. Shown until
  /// (and if) the backend copy loads, and the only list `flutter test` ever
  /// sees (`BackendHttp.isConfigured` is false under test).
  static const List<CategoryGroup> _seed = [
    CategoryGroup(
      title: 'Personal Care',
      tabLabel: 'Personal\nCare',
      icon: Icons.spa_outlined,
      image: 'assets/categories/bundle_personalcare_tab.png',
      bannerImage: 'assets/banners/skincare_banner.jpg',
      panelTint: AppColors.panelGreen,
      items: [
        SubCategory(
          'Skin Care',
          Icons.face_retouching_natural_outlined,
          image: 'assets/categories/bundle_skincare.png',
        ),
        SubCategory(
          'Hair Care',
          Icons.content_cut_rounded,
          image: 'assets/categories/bundle_haircare.png',
        ),
        SubCategory(
          'Oral Care',
          Icons.clean_hands_outlined,
          image: 'assets/categories/bundle_oralcare.png',
        ),
        SubCategory(
          'Bath & Body',
          Icons.shower_outlined,
          image: 'assets/categories/bundle_bathbody.png',
        ),
        SubCategory(
          'Men Grooming',
          Icons.face_outlined,
          image: 'assets/categories/bundle_mengrooming.png',
          offer: 'Up to 25% off',
        ),
        SubCategory(
          'Feminine Care',
          Icons.favorite_outline_rounded,
          image: 'assets/categories/bundle_femininecare.png',
        ),
      ],
    ),
    CategoryGroup(
      title: 'Health Conditions',
      tabLabel: 'Health\nConditions',
      icon: Icons.monitor_heart_outlined,
      image: 'assets/categories/bundle_health_tab.png',
      panelTint: AppColors.panelCream,
      items: [
        SubCategory(
          'Bone and Joint Care',
          Icons.accessibility_new_rounded,
          image: 'assets/categories/bundle_bonejoint.png',
        ),
        SubCategory(
          'Digestive Care',
          Icons.local_dining_outlined,
          image: 'assets/categories/bundle_digestive.png',
        ),
        SubCategory(
          'Eye Care',
          Icons.remove_red_eye_outlined,
          image: 'assets/categories/bundle_eyecare.png',
        ),
        SubCategory(
          'Pain Relief',
          Icons.healing_outlined,
          image: 'assets/categories/bundle_painrelief.png',
        ),
        SubCategory(
          'Smoking Cessation',
          Icons.smoke_free_rounded,
          image: 'assets/categories/bundle_smokingcessation.png',
        ),
        SubCategory(
          'Liver Care',
          Icons.water_drop_outlined,
          image: 'assets/categories/bundle_livercare.png',
        ),
      ],
    ),
    CategoryGroup(
      title: 'Vitamins & Supplements',
      tabLabel: 'Vitamins &\nSupplements',
      icon: Icons.medication_outlined,
      image: 'assets/categories/bundle_vitamins.png',
      panelTint: AppColors.panelBlue,
      items: [
        SubCategory(
          'Multivitamins',
          Icons.medication_liquid_outlined,
          image: 'assets/categories/bundle_multivitamins.png',
        ),
        SubCategory(
          'Vitamin D',
          Icons.wb_sunny_outlined,
          image: 'assets/categories/bundle_vitamind.png',
        ),
        SubCategory(
          'Protein Powder',
          Icons.fitness_center_rounded,
          image: 'assets/categories/bundle_protein.png',
          offer: 'Up to 20% off',
        ),
        SubCategory(
          'Omega & Fish Oil',
          Icons.set_meal_outlined,
          image: 'assets/categories/bundle_omega3.png',
        ),
        SubCategory(
          'Calcium',
          Icons.emoji_food_beverage_outlined,
          image: 'assets/categories/bundle_calcium.png',
        ),
        SubCategory(
          'Immunity',
          Icons.shield_outlined,
          image: 'assets/categories/bundle_immunity.png',
        ),
      ],
    ),
    CategoryGroup(
      title: 'Diabetes Care',
      tabLabel: 'Diabetes\nCare',
      icon: Icons.bloodtype_outlined,
      image: 'assets/categories/bundle_diabetes.png',
      panelTint: AppColors.panelPink,
      items: [
        SubCategory(
          'Glucometers',
          Icons.speed_rounded,
          image: 'assets/categories/bundle_glucometer.png',
          offer: 'Up to 30% off',
        ),
        SubCategory(
          'Test Strips',
          Icons.receipt_long_outlined,
          image: 'assets/categories/bundle_teststrips.png',
        ),
        SubCategory(
          'Sugar Substitutes',
          Icons.coffee_outlined,
          image: 'assets/categories/bundle_sugarsubstitute.png',
        ),
        SubCategory(
          'Diabetic Food',
          Icons.rice_bowl_outlined,
          image: 'assets/categories/bundle_diabeticfood.png',
        ),
        SubCategory(
          'Foot Care',
          Icons.airline_seat_legroom_normal_rounded,
          image: 'assets/categories/bundle_footcare.png',
          offer: 'Up to 25% off',
        ),
        SubCategory(
          'Insulin Support',
          Icons.vaccines_outlined,
          image: 'assets/categories/bundle_insulinsupport.png',
        ),
      ],
    ),
    CategoryGroup(
      title: 'Surgicals',
      tabLabel: 'Surgicals',
      icon: Icons.medical_services_outlined,
      panelTint: AppColors.panelSlate,
      // No photography exists for this group yet, so every card falls back to
      // its icon. The catalogue records that explicitly rather than pointing
      // at assets that are not on disk.
      items: [
        SubCategory('Gloves & Masks', Icons.masks_outlined),
        SubCategory('Bandages & Dressings', Icons.healing_outlined),
        SubCategory('Syringes & Needles', Icons.vaccines_outlined),
        SubCategory('Supports & Braces', Icons.accessibility_new_rounded),
        SubCategory('First Aid Kits', Icons.medical_services_outlined),
        SubCategory('Mobility Aids', Icons.airline_seat_recline_normal_rounded),
      ],
    ),
    CategoryGroup(
      title: 'Lab Tests',
      tabLabel: 'Lab\nTests',
      icon: Icons.biotech_outlined,
      panelTint: AppColors.pageTint,
      items: [
        SubCategory(
          'Full Body Checkup',
          Icons.fact_check_outlined,
          offer: 'Up to 60% off',
        ),
        SubCategory(
          'Blood Tests',
          Icons.bloodtype_outlined,
          offer: 'Up to 60% off',
        ),
        SubCategory(
          'Thyroid Profile',
          Icons.biotech_outlined,
          offer: 'Up to 60% off',
        ),
        SubCategory(
          'Vitamin Tests',
          Icons.science_outlined,
          offer: 'Up to 60% off',
        ),
      ],
    ),
  ];

  /// Groups whose cards fall back to icons because the project holds no
  /// photography for them.
  ///
  /// Lab Tests is permanent: those are bookings, not products on a shelf.
  /// Surgicals is temporary and should be removed from this set once artwork
  /// lands, which is why the exemption is declared here rather than being
  /// hard-coded into a test.
  static const Set<String> withoutArtwork = {'Surgicals', 'Lab Tests'};

  /// The groups the home strip offers as chips, in the order the strip shows
  /// them: everything that is a product you add to a cart, which is all of
  /// them bar the bookings.
  static const List<String> _stripOrder = [
    'Vitamins & Supplements',
    'Personal Care',
    'Health Conditions',
    'Diabetes Care',
    'Surgicals',
  ];

  /// [groups] used to be a fixed const list, so every [_stripOrder] title was
  /// guaranteed to exist. Now that an admin can rename or retire a category,
  /// a title the strip expects can go missing — skip it rather than crash the
  /// home screen; the strip just shows one fewer chip until the admin picks a
  /// replacement.
  static List<CategoryGroup> get shoppable => [
    for (final title in _stripOrder)
      if (groups.any((group) => group.title == title))
        groups.firstWhere((group) => group.title == title),
  ];
}

/// Holds the category list in force and swaps in the backend copy once it has
/// loaded. A [ChangeNotifier] so the Categories tab, the home "Shop by
/// categories" strip and a category's listing screen rebuild when the admin's
/// own categories (their chip and tile images, and banners) arrive.
///
/// The same shape as the member app's `CategoryCatalog`, fed from `backend/api`
/// instead of Neon: warm it once at launch (`main.dart`), let every screen call
/// [ensureLoaded] again in `initState` (they share one request), and fall back
/// to the bundled seed whenever the backend is missing, unreachable, or the
/// tables are empty.
class CategoryCatalog extends ChangeNotifier {
  CategoryCatalog._();

  static final CategoryCatalog instance = CategoryCatalog._();

  List<CategoryGroup> _live = CategoryCatalogue._seed;

  /// The categories in force — the backend copy once [ensureLoaded] has pulled
  /// them, otherwise the bundled seed.
  List<CategoryGroup> get groups => _live;

  bool _loaded = false;
  bool _fromBackend = false;
  bool _attempted = false;
  Future<void>? _inFlight;

  /// Whether [groups] is the backend copy rather than the bundled seed.
  bool get isFromBackend => _fromBackend;

  /// True once a load has finished at least once — success, empty tables, or
  /// failure. Lets a screen tell "still loading" from "loaded, nothing there".
  bool get hasAttempted => _attempted;

  /// Loads the category list from the backend once (best-effort). Safe to call
  /// from every screen's `initState`; only the first call does work unless
  /// [force].
  Future<void> ensureLoaded({bool force = false}) {
    if (force) {
      _loaded = false;
      _inFlight = null;
    }
    if (_loaded) return Future<void>.value();
    return _inFlight ??= _load();
  }

  Future<void> _load() async {
    try {
      final groups = await CategoryRepository.instance.fetchAll();
      if (groups != null && groups.isNotEmpty) {
        _live = groups;
        _fromBackend = true;
        _loaded = true;
      }
      // Otherwise nothing came back — backend not configured, or the tables
      // were empty. Leave [_loaded] false so the next ensureLoaded() retries.
    } catch (error) {
      debugPrint('CategoryCatalog: catalogue load failed — $error');
    } finally {
      _attempted = true;
      _inFlight = null;
      notifyListeners();
    }
  }

  /// Test hook — stand in [groups] for what a backend load would return.
  @visibleForTesting
  void useGroups(List<CategoryGroup> groups) {
    _live = List<CategoryGroup>.unmodifiable(groups);
    _loaded = true;
    _fromBackend = true;
    _attempted = true;
    _inFlight = null;
    notifyListeners();
  }

  /// Test hook — drop back to the bundled seed and forget any load.
  @visibleForTesting
  void reset() {
    _live = CategoryCatalogue._seed;
    _loaded = false;
    _fromBackend = false;
    _attempted = false;
    _inFlight = null;
  }
}
