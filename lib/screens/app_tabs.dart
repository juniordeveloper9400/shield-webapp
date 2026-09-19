import 'package:flutter/material.dart';

/// The bottom-navigation destinations, in display order.
///
/// This enum is the single source of truth for tab order. The shell, the
/// bottom bar, and the menu drawer all resolve positions through it, so
/// inserting or removing a destination cannot leave a hardcoded index
/// pointing at the wrong screen.
enum AppTab {
  home(
    label: 'Home',
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
  ),
  appointments(
    label: 'Appointments',
    icon: Icons.calendar_month_outlined,
    activeIcon: Icons.calendar_month_rounded,
  ),
  orders(
    label: 'My Orders',
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long_rounded,
  ),
  account(
    label: 'Account',
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
  );

  /// One size for every tab now that no destination is drawn larger than its
  /// neighbours. The bar reserves this much for the icon row.
  static const double iconSize = 22;

  final String label;
  final IconData icon;
  final IconData activeIcon;

  const AppTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

