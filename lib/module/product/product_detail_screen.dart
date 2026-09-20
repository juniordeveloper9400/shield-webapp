import 'package:flutter/material.dart';

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
/// price, MRP, discount, artwork. Everything a shopper wants before committing
/// — what it is, what it treats, how to take it, what to watch for — lives
/// here. The prose is composed by [ProductDetail] from the same fixture the
/// card was built from, so this screen needs no catalogue of its own.
class ProductDetailScreen extends StatelessWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final detail = ProductDetail.of(product);

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
                discountPercent: detail.discountPercent,
              ),
              _HeaderCard(detail: detail),
              _StorageStrip(text: detail.storage),
              _Section(
                title: 'Product highlights',
                bullets: detail.highlights,
                initiallyOpen: true,
              ),
              _Section(title: 'Product description', body: detail.description),
              _Section(title: 'Key benefits', bullets: detail.benefits),
              _Section(title: 'Directions for use', bullets: detail.directions),
              _Section(title: 'Ingredients', body: detail.ingredients),
              _Section(title: 'Safety information', bullets: detail.safety),
              const _ReviewedStrip(),
              _RelatedRail(current: product),
              _FaqCard(faqs: detail.faqs),
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

class _ArtworkCard extends StatelessWidget {
  final Product product;
  final int discountPercent;

  const _ArtworkCard({required this.product, required this.discountPercent});

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: AspectRatio(
          aspectRatio: 1.15,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: AppImage(
                    image: product.image,
                    fallbackIcon: product.icon,
                    iconSize: 96,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              if (discountPercent > 0)
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
                      '$discountPercent% OFF',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.white,
                      ),
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
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _TrustChip('WHO-GMP Certified'),
              _TrustChip('ISO Certified Quality'),
              _TrustChip('100% Genuine'),
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

class _TrustChip extends StatelessWidget {
  final String label;

  const _TrustChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.greenTint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.brandGreenDark,
        ),
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
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Frequently asked questions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < faqs.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            _FaqRow(faq: faqs[i]),
          ],
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
                    widget.faq.question,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                Icon(
                  _open ? Icons.remove_rounded : Icons.add_rounded,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              widget.faq.answer,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
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
