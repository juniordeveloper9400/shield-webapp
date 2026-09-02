import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../home/product_showcase.dart';
import 'category_catalogue.dart';
import 'listing_catalogue.dart';

/// The applied state of the listing's filter sheet: a set of ticked
/// sub-categories and a set of ticked brands. Immutable — the screen swaps in a
/// fresh instance every time Apply is tapped.
@immutable
class ListingFilter {
  final Set<String> subCategories;
  final Set<String> brands;

  const ListingFilter({
    this.subCategories = const {},
    this.brands = const {},
  });

  /// The do-nothing filter.
  static const ListingFilter none = ListingFilter();

  bool get isActive => subCategories.isNotEmpty || brands.isNotEmpty;

  /// Total ticked options across every facet — the number shown on the Filter
  /// pill and against each left-rail tab.
  int get count => subCategories.length + brands.length;

  ListingFilter copyWith({
    Set<String>? subCategories,
    Set<String>? brands,
  }) {
    return ListingFilter(
      subCategories: subCategories ?? this.subCategories,
      brands: brands ?? this.brands,
    );
  }

  /// The products this filter leaves for [group].
  ///
  /// [chip] is the sub-category rail's own selection on the listing screen; it
  /// only applies while the sheet's own Sub-categories facet is untouched, so
  /// the two never fight.
  List<Product> resolve(CategoryGroup group, {SubCategory? chip}) {
    final List<Product> base;
    if (subCategories.isNotEmpty) {
      base = [
        for (final item in group.items)
          if (subCategories.contains(item.label))
            ...ListingCatalogue.forSubCategoryIn(group, item),
      ];
    } else if (chip != null) {
      base = ListingCatalogue.forSubCategoryIn(group, chip);
    } else {
      base = ListingCatalogue.forGroup(group);
    }

    if (brands.isEmpty) {
      return base;
    }
    return base
        .where((product) => brands.contains(ListingCatalogue.brandOf(product)))
        .toList();
  }
}

/// The left-rail facets, in the order the rail shows them.
enum _Facet {
  subCategories('Sub-categories'),
  brands('Brands');

  const _Facet(this.label);

  final String label;
}

/// Opens the two-pane filter sheet and resolves to the shopper's applied
/// choice, or null if they dismissed it without applying.
Future<ListingFilter?> showListingFilterSheet(
  BuildContext context, {
  required CategoryGroup group,
  required ListingFilter current,
}) {
  return showModalBottomSheet<ListingFilter>(
    context: context,
    isScrollControlled: true,
    // Fill the screen, less the status bar — no strip of the listing showing
    // through above the sheet.
    useSafeArea: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _FilterSheet(group: group, current: current),
  );
}

class _FilterSheet extends StatefulWidget {
  final CategoryGroup group;
  final ListingFilter current;

  const _FilterSheet({required this.group, required this.current});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ListingFilter _draft = widget.current;
  _Facet _facet = _Facet.subCategories;

  List<String> get _options => switch (_facet) {
    _Facet.subCategories => ListingCatalogue.subCategoryLabels(widget.group),
    _Facet.brands => ListingCatalogue.brandsFor(widget.group),
  };

  /// The heading over the options pane: the group name while picking
  /// sub-categories, matching the reference, and 'Brands' otherwise.
  String get _paneHeading => switch (_facet) {
    _Facet.subCategories => widget.group.title,
    _Facet.brands => 'Brands',
  };

  Set<String> _selectionFor(_Facet facet) => switch (facet) {
    _Facet.subCategories => _draft.subCategories,
    _Facet.brands => _draft.brands,
  };

  void _toggle(String value) {
    final next = {..._selectionFor(_facet)};
    next.contains(value) ? next.remove(value) : next.add(value);
    setState(() {
      _draft = _facet == _Facet.subCategories
          ? _draft.copyWith(subCategories: next)
          : _draft.copyWith(brands: next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: double.infinity,
      child: Column(
        children: [
          _Header(onClose: () => Navigator.of(context).pop()),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 150,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final facet in _Facet.values)
                        _RailTab(
                          label: facet.label,
                          selected: _facet == facet,
                          count: _selectionFor(facet).length,
                          onTap: () => setState(() => _facet = facet),
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, color: AppColors.border),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: AppColors.pageTint,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: Text(
                          _paneHeading,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          children: [
                            for (final option in _options)
                              _OptionRow(
                                label: option,
                                checked: _selectionFor(_facet).contains(option),
                                onTap: () => _toggle(option),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _Footer(
            canClear: _draft.isActive,
            applyCount: _draft.count,
            onClear: () => setState(() => _draft = ListingFilter.none),
            onApply: () => Navigator.of(context).pop(_draft),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;

  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
      child: Row(
        children: [
          const Text(
            'Filters',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const Spacer(),
          Material(
            color: AppColors.white,
            shape: const CircleBorder(
              side: BorderSide(color: AppColors.searchBorder),
            ),
            child: InkWell(
              onTap: onClose,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailTab extends StatelessWidget {
  final String label;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  const _RailTab({
    required this.label,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.pageTint : AppColors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (count > 0) _CountBadge(count),
            ],
          ),
        ),
      ),
    );
  }
}

/// The number tag against a rail tab and, on the listing, the Filter pill.
class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge(this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: AppColors.brandBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.white,
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onTap;

  const _OptionRow({
    required this.label,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(
              checked
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 22,
              color: checked ? AppColors.brandBlue : AppColors.searchBorder,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.25,
                  fontWeight: checked ? FontWeight.w600 : FontWeight.w500,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final bool canClear;
  final int applyCount;
  final VoidCallback onClear;
  final VoidCallback onApply;

  const _Footer({
    required this.canClear,
    required this.applyCount,
    required this.onClear,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            TextButton(
              onPressed: canClear ? onClear : null,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandBlue,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: const Text(
                'Clear',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onApply,
                child: Text(
                  applyCount > 0 ? 'Apply ($applyCount)' : 'Apply',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
