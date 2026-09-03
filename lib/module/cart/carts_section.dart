import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../labtest/lab_cart_screen.dart';
import '../labtest/lab_cart_service.dart';
import 'cart_screen.dart';
import 'cart_service.dart';

/// "Your carts": summarizes the two priced carts (Products and Lab tests) on
/// the home screen. Prescriptions are an order-first flow with no basket, so
/// they are not one of these tiles.
class CartsSection extends StatelessWidget {
  const CartsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.textDark.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.pageTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.shopping_bag_outlined,
                    size: 18,
                    color: AppColors.brandBlue,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Your carts',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ListenableBuilder(
                    listenable: CartService.instance,
                    builder: (context, _) {
                      final count = CartService.instance.itemCount;
                      return _CartTile(
                        key: const ValueKey('cart-tile-products'),
                        icon: Icons.shopping_bag_outlined,
                        label: 'Products',
                        countText: count == 0
                            ? 'Empty'
                            : '$count ${count == 1 ? 'item' : 'items'}',
                        isFilled: count > 0,
                        accentColor: AppColors.brandBlue,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CartScreen()),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ListenableBuilder(
                    listenable: LabCartService.instance,
                    builder: (context, _) {
                      final count = LabCartService.instance.bookingCount;
                      return _CartTile(
                        key: const ValueKey('cart-tile-lab'),
                        icon: Icons.biotech_outlined,
                        label: 'Lab tests',
                        countText: count == 0
                            ? 'Empty'
                            : '$count ${count == 1 ? 'booking' : 'bookings'}',
                        isFilled: count > 0,
                        accentColor: const Color(0xFF2F8F7A),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LabCartScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CartTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String countText;
  final bool isFilled;
  final Color accentColor;
  final VoidCallback onTap;

  const _CartTile({
    super.key,
    required this.icon,
    required this.label,
    required this.countText,
    required this.isFilled,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isFilled ? AppColors.pageTint : const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isFilled
                  ? accentColor.withValues(alpha: 0.3)
                  : AppColors.border,
              width: 1.1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: isFilled ? accentColor : AppColors.textMuted,
                  ),
                  const Spacer(),
                  if (isFilled)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  countText,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isFilled ? FontWeight.w700 : FontWeight.w500,
                    color: isFilled ? accentColor : AppColors.textMuted,
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
