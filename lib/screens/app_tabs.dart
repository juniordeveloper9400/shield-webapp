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
  lab(
    label: 'Lab',
    icon: Icons.biotech_outlined,
    activeIcon: Icons.biotech_rounded,
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

/// Exists purely to be seen by Flutter's icon tree-shaker — never read,
/// never rendered.
///
/// A release build (web included) strips every `IconData` out of the icon
/// font except the ones it can find used as a literal `Icon(Icons.foo)`
/// argument somewhere in the source. [AppTab.icon] / [AppTab.activeIcon] are
/// only ever reached *indirectly* — every call site reads them off an enum
/// value (`tab.icon`, in `ShieldBottomNav`) rather than naming the constant
/// directly — which the tree-shaker's static scan does not trace through.
/// Most of these tabs' icons happen to also appear directly elsewhere in the
/// app and so survive by accident; [Icons.biotech_rounded] (the Lab tab's
/// selected-state icon) does not, so this keeps the whole set safe
/// regardless of where else they are or are not used elsewhere. Mirrors
/// root's identical safeguard.
// ignore: unused_element
const List<IconData> _keepAppTabIconsInTreeShaking = [
  Icons.home_outlined,
  Icons.home_rounded,
  Icons.biotech_outlined,
  Icons.biotech_rounded,
  Icons.calendar_month_outlined,
  Icons.calendar_month_rounded,
  Icons.receipt_long_outlined,
  Icons.receipt_long_rounded,
  Icons.person_outline_rounded,
  Icons.person_rounded,
];
