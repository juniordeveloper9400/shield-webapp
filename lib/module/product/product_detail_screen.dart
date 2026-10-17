import 'package:flutter/material.dart';

import '../../data/backend/product_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';
import '../cart/cart_bar.dart';
import '../cart/cart_control.dart';
import '../cart/cart_screen.dart';
import '../cart/cart_service.dart';
import '../home/product_showcase.dart';
import '../search/search_catalogue.dart';
import 'product_detail_content.dart';

/// The full page for one product, reached by tapping any product card or tile.
///
/// The card in a grid or a home row shows the six things that fit — name, pack,
/// price, MRP, discount, artwork. This page always carries that plus ADD — the
/// one thing every product has. Everything below it — what it is, what it
/// treats, how to take it, what to watch for — is exactly what the pharmacy
/// admin filled in for the product in the console (`app.product_detail` /
/// `app.product_faq`), one section per field they used; a field left blank
/// has no section at all, rather than invented copy standing in for it. A
/// product nobody has added detail to yet shows artwork, price and ADD, and
/// nothing else.
class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Product get product => widget.product;

  /// Admin-entered content, once fetched. Null until the load settles or when
  /// the product has no backend id / the backend is off — the page then
  /// shows only the artwork, price and ADD.
  ProductDetailData? _content;

  @override
  void initState() {
    super.initState();
    final backendId = product.backendId;
    if (backendId != null) {
      ProductRepository.instance.detailFor(backendId).then((data) {
        if (mounted && data != null) {
          setState(() => _content = data);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ProductDetail.of(product, content: _content);

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Product Details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        actions: [
          _CartAction(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CartScreen())),
          ),
          const SizedBox(width: 12),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            // Clears the floating cart bar so the disclaimer stays readable.
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              _ArtworkCard(
                product: product,
                images: detail.images,
                discountPercent: detail.discountPercent,
              ),
              _HeaderCard(detail: detail),
              // Everything from here down is admin-entered — present only
              // for the field the admin actually used, never a placeholder.
              if (detail.storage.isNotEmpty)
                _StorageStrip(text: detail.storage),
              // "Highlights" and "Key benefits" are two admin fields from
              // before the console combined them into one "Key uses" field
              // (see ProductsPage.tsx); shown together here so neither an
              // older product's benefits nor a newer one's highlights is lost.
              if (detail.highlights.isNotEmpty || detail.benefits.isNotEmpty)
                _Section(
                  title: 'Key uses',
                  bullets: <String>{...detail.highlights, ...detail.benefits}.toList(),
                  initiallyOpen: true,
                ),
              if (detail.description.isNotEmpty)
                _Section(
                  title: 'Product description',
                  body: detail.description,
                ),
              if (detail.directions.isNotEmpty)
                _Section(
                  title: 'How to use',
                  bullets: detail.directions,
                ),
              if (detail.ingredients.isNotEmpty)
                _Section(title: 'Ingredients', body: detail.ingredients),
              if (detail.safety.isNotEmpty)
                _Section(title: 'Safety information', bullets: detail.safety),
              const _ReviewedStrip(),
              _RelatedRail(current: product),
              if (detail.faqs.isNotEmpty) _FaqCard(faqs: detail.faqs),
              const _Disclaimer(),
            ],
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: CartBar()),
        ],
      ),
    );
  }
}

/// White rounded panel with the page's standard inset — every block on the
/// details page sits in one.
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: padding,
      child: child,
    );
  }
}

class _ArtworkCard extends StatefulWidget {
  final Product product;
  final List<String> images;
  final int discountPercent;

  const _ArtworkCard({
    required this.product,
    required this.images,
    required this.discountPercent,
  });

  @override
  State<_ArtworkCard> createState() => _ArtworkCardState();
}

class _ArtworkCardState extends State<_ArtworkCard> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryImg = widget.product.image;
    final images = widget.images.isNotEmpty
        ? widget.images
        : [if (primaryImg != null && primaryImg.isNotEmpty) primaryImg];

    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: AspectRatio(
              aspectRatio: 1.15,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: images.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(18),
                            child: AppImage(
                              image: widget.product.image,
                              fallbackIcon: widget.product.icon,
                              iconSize: 96,
                              fit: BoxFit.contain,
                            ),
                          )
                        : PageView.builder(
                            controller: _pageController,
                            itemCount: images.length,
                            onPageChanged: (i) => setState(() => _currentIndex = i),
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.all(18),
                              child: AppImage(
                                image: images[i],
                                fallbackIcon: widget.product.icon,
                                iconSize: 96,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                  ),
                  if (widget.discountPercent > 0)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 7, 16, 8),
                        decoration: const BoxDecoration(
                          color: AppColors.brandGreenDark,
                          borderRadius: BorderRadius.only(
                            bottomRight: Radius.circular(14),
                          ),
                        ),
                        child: Text(
                          '${widget.discountPercent}% OFF',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                    ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 8,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(140),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_currentIndex + 1} / ${images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(images.length, (i) {
                          final active = i == _currentIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: active ? 18 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.brandGreenDark
                                  : Colors.white.withAlpha(180),
                              borderRadius: BorderRadius.circular(4),
                              border: active
                                  ? null
                                  : Border.all(color: Colors.black.withAlpha(30)),
                            ),
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (images.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final isSelected = i == _currentIndex;
                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? AppColors.brandGreenDark : AppColors.border,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: AppImage(
                                image: images[i],
                                fallbackIcon: widget.product.icon,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final ProductDetail detail;

  const _HeaderCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final product = detail.product;
    final unitLabel = detail.unitPriceLabel;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product.name,
            style: const TextStyle(
              fontSize: 19,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            product.pack,
            style: const TextStyle(fontSize: 13.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(
                child: Text(
                  detail.manufacturer,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textBody,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              const Icon(
                Icons.verified_rounded,
                size: 15,
                color: AppColors.brandBlue,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (detail.save > 0)
                      Text(
                        'MRP ${detail.mrpLabel}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          detail.priceLabel,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        if (unitLabel != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            unitLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (detail.discountPercent > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.greenTint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${detail.discountPercent}% OFF',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandGreenDark,
                    ),
                  ),
                ),
            ],
          ),
          if (detail.save > 0) ...[
            const SizedBox(height: 6),
            Text(
              'You save ${detail.saveLabel} on this pack',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.brandGreenDark,
              ),
            ),
          ],
          const SizedBox(height: 14),
          CartControl(
            name: product.name,
            pack: product.pack,
            price: product.price,
            mrp: product.mrp,
            productId: product.backendId,
            image: product.image,
          ),
        ],
      ),
    );
  }
}

class _StorageStrip extends StatelessWidget {
  final String text;

  const _StorageStrip({required this.text});

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.ac_unit_rounded,
            size: 20,
            color: AppColors.brandBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A collapsible block. Shows either [body] as a paragraph or [bullets] as a
/// list; exactly one is given.
class _Section extends StatefulWidget {
  final String title;
  final String? body;
  final List<String>? bullets;
  final bool initiallyOpen;

  const _Section({
    required this.title,
    this.body,
    this.bullets,
    this.initiallyOpen = false,
  });

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 4, 14),
              child: widget.body != null
                  ? Text(
                      widget.body!,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: AppColors.textBody,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in widget.bullets ?? const <String>[])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '•  ',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.45,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    line,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      height: 1.45,
                                      color: AppColors.textBody,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _ReviewedStrip extends StatelessWidget {
  const _ReviewedStrip();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.panelBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              size: 20,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reviewed for accuracy',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  "Checked by Sahakar 360's registered pharmacy team",
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Customers also bought" — a horizontal rail of other catalogue products,
/// each one tapping through to its own copy of this screen.
class _RelatedRail extends StatelessWidget {
  final Product current;

  const _RelatedRail({required this.current});

  @override
  Widget build(BuildContext context) {
    final related = SearchCatalogue.all
        .where((product) => product.name != current.name)
        .take(10)
        .toList(growable: false);

    if (related.isEmpty) {
      return const SizedBox.shrink();
    }

    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Customers also bought',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 248,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 8),
              itemCount: related.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) =>
                  _MiniProductCard(product: related[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniProductCard extends StatelessWidget {
  final Product product;

  const _MiniProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(product: product),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 116,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AppImage(
                    image: product.image,
                    fallbackIcon: product.icon,
                    iconSize: 44,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 30,
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Text(
                            '₹${product.price}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '₹${product.mrp}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      CartControl(
                        name: product.name,
                        pack: product.pack,
                        price: product.price,
                        mrp: product.mrp,
                        productId: product.backendId,
                        image: product.image,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  final List<ProductFaq> faqs;

  const _FaqCard({required this.faqs});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      color: AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Text(
              'Frequently asked questions (FAQs)',
              style: TextStyle(
                fontSize: 20,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ),
          for (final faq in faqs) ...[
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            _FaqRow(faq: faq),
          ],
          const Divider(height: 1, thickness: 1, color: AppColors.border),
        ],
      ),
    );
  }
}

class _FaqRow extends StatefulWidget {
  final ProductFaq faq;

  const _FaqRow({required this.faq});

  @override
  State<_FaqRow> createState() => _FaqRowState();
}

class _FaqRowState extends State<_FaqRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: Material(
            color: AppColors.white,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.faq.question,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 28,
                      color: AppColors.textDark,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: Text(
              widget.faq.answer,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: AppColors.textBody,
              ),
            ),
          ),
      ],
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(
        'The information on this page is for awareness only and is not a '
        'substitute for professional medical advice. Always read the label and '
        'consult your doctor or pharmacist before use.',
        style: TextStyle(
          fontSize: 11.5,
          height: 1.5,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

/// Cart circle in the app bar, carrying the live item count.
class _CartAction extends StatelessWidget {
  final VoidCallback onTap;

  const _CartAction({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartService.instance,
      builder: (context, _) {
        final count = CartService.instance.itemCount;
        return Semantics(
          button: true,
          label: count == 0 ? 'Cart' : 'Cart · $count items',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: AppColors.white,
                shape: const CircleBorder(
                  side: BorderSide(color: AppColors.searchBorder),
                ),
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.shopping_cart_outlined,
                      size: 21,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ),
              if (count > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFD93A2B),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
