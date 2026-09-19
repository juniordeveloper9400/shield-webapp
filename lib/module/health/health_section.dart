import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/bottom_nav.dart';
import '../dietitian/dietitian_screen.dart';
import '../labtest/lab_test_screen.dart';
import '../labtest/top_packages_screen.dart';

/// Sub-destinations inside the health section.
///
/// Labs and the dietitian are one errand — you book a test, then you talk to
/// someone about what it said — so they share a section rather than competing
/// for two slots in a five-tab bar.
enum HealthSubTab {
  labsTests(label: 'Labs Tests', icon: Icons.colorize_rounded),
  topPackages(label: 'Top Packages', icon: Icons.grid_view_rounded),
  dietitian(label: 'Dietitian', icon: Icons.restaurant_menu_rounded);

  final String label;
  final IconData icon;

  const HealthSubTab({required this.label, required this.icon});
}

/// The lab + dietitian experience, which carries its own bottom bar in place
/// of the app's main one. The leftmost item returns to the app's Home
/// destination.
class HealthSection extends StatelessWidget {
  final HealthSubTab active;
  final ValueChanged<HealthSubTab> onSelectSubTab;

  const HealthSection({
    super.key,
    required this.active,
    required this.onSelectSubTab,
  });

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: active.index,
      children: [
        LabTestScreen(
          onSeeAllPackages: () => onSelectSubTab(HealthSubTab.topPackages),
        ),
        TopPackagesScreen(onBack: () => onSelectSubTab(HealthSubTab.labsTests)),
        const DietitianScreen(),
      ],
    );
  }
}

/// Bottom bar shown while the health section is open.
class HealthBottomBar extends StatelessWidget {
  final HealthSubTab active;
  final ValueChanged<HealthSubTab> onSelectSubTab;
  final VoidCallback onExitToHome;

  const HealthBottomBar({
    super.key,
    required this.active,
    required this.onSelectSubTab,
    required this.onExitToHome,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      // Matches the app's main bar so the section swap is not also a colour
      // change.
      color: AppColors.white,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                Expanded(
                  child: _HealthBarItem(
                    label: 'Home',
                    icon: Icons.arrow_back_rounded,
                    isSelected: false,
                    // Circled glyph marks this as the way out of the section
                    // rather than another destination within it.
                    circled: true,
                    onTap: onExitToHome,
                  ),
                ),
                for (final tab in HealthSubTab.values)
                  Expanded(
                    child: _HealthBarItem(
                      label: tab.label,
                      icon: tab.icon,
                      isSelected: tab == active,
                      onTap: () => onSelectSubTab(tab),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HealthBarItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool circled;
  final VoidCallback onTap;

  const _HealthBarItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.circled = false,
  });

  @override
  Widget build(BuildContext context) {
    // The same muted slate the main bar uses, so the two bars mark their
    // selection identically as one replaces the other.
    final colour = isSelected ? AppColors.brandBlue : AppColors.textMuted;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkWell(
        onTap: onTap,
        // Same short line and ink-only selected state as the app's main bar.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 3,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: 3,
                  width: ShieldBottomNav.indicatorWidth,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? ShieldBottomNav.activeLine
                        : AppColors.transparent,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 30,
              child: Center(
                child: circled
                    ? Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: colour, width: 1.4),
                        ),
                        child: Icon(icon, size: 17, color: colour),
                      )
                    : Icon(icon, size: 23, color: colour),
              ),
            ),
            const SizedBox(height: 3),
            Padding(
              // Four items now share the bar, so the labels sit tighter and
              // scale down rather than ellipsing.
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    color: colour,
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
