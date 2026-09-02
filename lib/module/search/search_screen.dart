import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../cart/cart_bar.dart';
import '../catalogue/catalogue_service.dart';
import '../categories/category_listing_screen.dart' show ProductTile;
import '../home/product_showcase.dart';
import 'search_catalogue.dart';

/// Full-text product search: an autofocused query field over a live-filtered
/// grid, reached from the home search bar and the category listing's search
/// icon.
///
/// [initialQuery], when given, is what a tapped suggestion or "View all"
/// arrives already carrying — the field still owns the text from there on, so
/// typing works exactly the same either way.
class SearchScreen extends StatefulWidget {
  final String initialQuery;

  const SearchScreen({super.key, this.initialQuery = ''});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  late String _query = widget.initialQuery;

  @override
  void initState() {
    super.initState();
    CatalogueService.instance.ensureLoaded();
    _controller.addListener(() {
      if (_controller.text != _query) {
        setState(() => _query = _controller.text);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CatalogueService.instance,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final trimmed = _query.trim();
    final results = SearchCatalogue.search(trimmed);
    final loading = !CatalogueService.instance.isSettled;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.textDark,
        ),
        title: _QueryField(controller: _controller, onClear: () => _setQuery('')),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: Stack(
        children: [
          if (trimmed.isEmpty)
            _Suggestions(onPick: _setQuery)
          else if (results.isEmpty && loading)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.brandBlue,
                ),
              ),
            )
          else if (results.isEmpty)
            _NoResults(query: trimmed)
          else
            _ResultsGrid(query: trimmed, results: results),
          const Positioned(left: 0, right: 0, bottom: 0, child: CartBar()),
        ],
      ),
    );
  }
}

/// The query box itself, living in the app bar's title slot so the back
/// arrow, the box and its clear button all sit on the one row.
class _QueryField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onClear;

  const _QueryField({required this.controller, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search for medicine',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 16),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.brandBlue,
          size: 22,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: AppColors.textMuted,
                  tooltip: 'Clear search',
                ),
        ),
        filled: true,
        fillColor: AppColors.pageTint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.4),
        ),
      ),
      style: const TextStyle(fontSize: 16, color: AppColors.textDark),
    );
  }
}

/// Shown before anything has been typed: a short list of searches worth
/// trying, each one a tap away from its own results.
class _Suggestions extends StatelessWidget {
  final ValueChanged<String> onPick;

  const _Suggestions({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
      children: [
        const Text(
          'Popular searches',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in SearchCatalogue.suggestions)
              ActionChip(
                label: Text(suggestion),
                labelStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
                backgroundColor: AppColors.pageTint,
                side: const BorderSide(color: AppColors.border),
                onPressed: () => onPick(suggestion),
              ),
          ],
        ),
      ],
    );
  }
}

/// Nothing matched. Says so, and names the query rather than leaving a blank
/// grid the member has to interpret for themselves.
class _NoResults extends StatelessWidget {
  final String query;

  const _NoResults({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 46,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              'No results for "$query"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try a different spelling or a shorter search.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal padding either side of the grid, and the gap between columns —
/// the same measurements [ProductCollectionScreen] lays its own grid out on.
const double _gridPad = 12;
const double _gridGap = 12;

double _columnWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width - _gridPad * 2 - _gridGap) / 2;

class _ResultsGrid extends StatelessWidget {
  final String query;
  final List<Product> results;

  const _ResultsGrid({required this.query, required this.results});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              '${results.length} result${results.length == 1 ? '' : 's'} '
              'for "$query"',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(_gridPad, 12, _gridPad, 8),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: _gridGap,
              mainAxisExtent:
                  _columnWidth(context) + ProductTile.detailsExtent,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => ProductTile(product: results[index]),
              childCount: results.length,
            ),
          ),
        ),
        // Clears the floating cart bar so the last row stays reachable.
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}
