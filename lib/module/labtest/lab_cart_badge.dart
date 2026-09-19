import 'package:flutter/material.dart';

import '../cart/basket_badge.dart';
import 'lab_cart_screen.dart';
import 'lab_cart_service.dart';

/// The lab basket, shown on the lab pages that book into it.
///
/// Counts bookings rather than units, and reads a separate service from
/// `CartBadge`: the two counts must never be shown against each other's icon.
class LabCartBadge extends StatelessWidget {
  const LabCartBadge({super.key});

  static const Color badgeColour = BasketBadge.badgeColour;

  @override
  Widget build(BuildContext context) {
    return BasketBadge(
      basket: LabCartService.instance,
      count: () => LabCartService.instance.bookingCount,
      tooltip: (count) =>
          count == 0 ? 'Lab bookings' : 'Lab bookings · $count',
      screen: (_) => const LabCartScreen(),
    );
  }
}
