import 'package:flutter/material.dart';

import '../../money.dart';
import '../../screens/app_tabs.dart';
import '../../theme/app_colors.dart';
import '../agent/agent_portal_screen.dart';
import '../agent/agent_service.dart';
import '../auth/auth_service.dart';
import '../cart/cart_screen.dart';
import '../cart/cart_service.dart';
import '../categories/categories_screen.dart';
import '../health/health_section.dart';
import '../investment/investment_plan_screen.dart';
import '../labtest/lab_cart_screen.dart';
import '../labtest/lab_cart_service.dart';
import '../rewards/rewards_service.dart';
import '../refer/refer_earn_screen.dart';
import '../rewards/rewards_screen.dart';
import '../wallet/wallet_screen.dart';
import '../wallet/wallet_service.dart';

/// Full-screen navigation menu opened from the header hamburger.
///
/// Takes over the whole viewport: a titled bar with a close affordance, a
/// tinted account strip, an at-a-glance dashboard, the browse links, and a
/// shaded account group pinned to the end of the list.
class MenuDrawer extends StatelessWidget {
  /// Switches the shell to one of the bottom-navigation destinations, and —
  /// for the health destination — to a named page inside it.
  final void Function(int index, {HealthSubTab? subTab}) onSelectTab;

  const MenuDrawer({super.key, required this.onSelectTab});

  static const List<String> _browseLinks = [
    'Medicines',
    'Personal Care',
    'Health Conditions',
    'Diabetes Care',
    'Healthcare Devices',
    'Vitamins & Supplements',
    'Homeopathic Medicine',
    'Health Articles',
    'Diseases & Health Conditions',
    'Health Stories',
    'Ayurveda',
    'Health Library',
  ];

  void _go(BuildContext context, int tab, {HealthSubTab? subTab}) {
    Navigator.of(context).pop();
    onSelectTab(tab, subTab: subTab);
  }

  void _push(BuildContext context, Widget screen) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final agent = AgentService.instance.agentForPhone(
      AuthService.instance.currentUser.value?.phone,
    );

    return Drawer(
      backgroundColor: AppColors.white,
      // Full-bleed: the menu takes over the whole screen rather than sliding
      // partway across it.
      width: MediaQuery.sizeOf(context).width,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _MenuHeader(onClose: () => Navigator.of(context).pop()),
            // The signed-in number, not a fixed one: the gate guarantees a
            // session exists by the time this drawer can be opened.
            _AccountStrip(user: AuthService.instance.currentUser.value),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DashboardPanel(
                    onOpenWallet: () => _push(context, const WalletScreen()),
                    onOpenCart: () => _push(context, const CartScreen()),
                    onOpenLabCart: () =>
                        _push(context, const LabCartScreen()),
                    onOpenOrders: () => _go(context, AppTab.orders.index),
                    onOpenRewards: () => _push(context, const RewardsScreen()),
                  ),
                  // Sits directly under the dashboard: its own call-out row
                  // rather than one of the plain browse links, since it opens
                  // a full feature screen and not a category listing.
                  _InvestmentPlanRow(
                    onTap: () =>
                        _push(context, const InvestmentPlanScreen()),
                  ),
                  // Categories is no longer a tab, so the browse links push
                  // it as a route rather than switching to a destination that
                  // is not in the bar.
                  for (final label in _browseLinks)
                    _MenuRow(
                      label: label,
                      onTap: () => _push(context, const CategoriesScreen()),
                    ),
                  Container(
                    color: const Color(0xFFF3F4F6),
                    child: Column(
                      children: [
                        // Matches the bottom-bar destination.
                        _MenuRow(
                          label: 'Appointments',
                          transparent: true,
                          onTap: () => _go(context, AppTab.appointments.index),
                        ),
                        // Lab tests and the dietitian share the Lab tab,
                        // so the drawer names the inner page rather than
                        // leaving it behind a tab labelled something else.
                        _MenuRow(
                          label: 'Lab tests',
                          transparent: true,
                          onTap: () => _go(
                            context,
                            AppTab.lab.index,
                            subTab: HealthSubTab.labsTests,
                          ),
                        ),
                        _MenuRow(
                          label: 'Dietitian',
                          transparent: true,
                          onTap: () => _go(
                            context,
                            AppTab.lab.index,
                            subTab: HealthSubTab.dietitian,
                          ),
                        ),
                        // Only for a signed-in agent — sits with Refer & earn
                        // because it is that card's counterpart.
                        if (agent != null)
                          _MenuRow(
                            label: 'Agent portal',
                            transparent: true,
                            onTap: () => _push(
                              context,
                              AgentPortalScreen(agent: agent),
                            ),
                          ),
                        _MenuRow(
                          label: 'Refer & earn',
                          transparent: true,
                          onTap: () => _push(context, const ReferEarnScreen()),
                        ),
                        // Orders is a destination now, so the row switches to
                        // it rather than stacking a second copy on top of the
                        // tab that already holds it.
                        _MenuRow(
                          label: 'My orders',
                          transparent: true,
                          onTap: () => _go(context, AppTab.orders.index),
                        ),
                        _MenuRow(
                          label: 'Account',
                          transparent: true,
                          showDivider: false,
                          onTap: () => _go(context, AppTab.account.index),
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
    );
  }
}

class _MenuHeader extends StatelessWidget {
  final VoidCallback onClose;

  const _MenuHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
      child: Row(
        children: [
          Image.asset(
            'assets/logos/shield_logo.png',
            height: 28,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Menu',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          Material(
            color: AppColors.white,
            shape: const CircleBorder(
              side: BorderSide(color: AppColors.searchBorder),
            ),
            child: InkWell(
              onTap: onClose,
              customBorder: const CircleBorder(),
              child: const SizedBox(
                width: 38,
                height: 38,
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

class _AccountStrip extends StatelessWidget {
  final AuthUser? user;

  const _AccountStrip({required this.user});

  @override
  Widget build(BuildContext context) {
    // Blue-to-green sweep, taken from the two logo colours at low opacity.
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFCFE4F7), Color(0xFFE2F4E4)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            user?.phone ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () {},
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Add more user details >',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool transparent;
  final bool showDivider;

  const _MenuRow({
    required this.label,
    required this.onTap,
    this.transparent = false,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: transparent ? AppColors.transparent : AppColors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: showDivider
              ? const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                )
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                size: 24,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Highlighted menu entry for the Investment Plan, pinned right below the
/// dashboard. Tinted and iconned so it reads as a feature, not a browse link.
class _InvestmentPlanRow extends StatelessWidget {
  final VoidCallback onTap;

  const _InvestmentPlanRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.pageTint,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
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
                      'Investment Plan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '100% assured ROI on every unit share',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                size: 24,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// At-a-glance account summary shown at the top of the full-screen menu.
class _DashboardPanel extends StatelessWidget {
  final VoidCallback onOpenWallet;
  final VoidCallback onOpenCart;
  final VoidCallback onOpenLabCart;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenRewards;

  const _DashboardPanel({
    required this.onOpenWallet,
    required this.onOpenCart,
    required this.onOpenLabCart,
    required this.onOpenOrders,
    required this.onOpenRewards,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.pageTint,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dashboard',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              // Two per row on phones, four across once there is room.
              final columns = constraints.maxWidth >= 520 ? 4 : 2;
              const gap = 10.0;
              final tileWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: tileWidth,
                    child: _StatTile(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Wallet balance',
                      value: '₹${formatRupees(WalletService.instance.balance)}',
                      accent: AppColors.brandBlue,
                      onTap: onOpenWallet,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _StatTile(
                      icon: Icons.collections_bookmark_outlined,
                      label: 'Active orders',
                      value: '2',
                      accent: AppColors.brandGreenDeep,
                      onTap: onOpenOrders,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _StatTile(
                      icon: Icons.shopping_cart_outlined,
                      label: 'Product cart',
                      value: '${CartService.instance.itemCount}',
                      accent: AppColors.brandBlue,
                      onTap: onOpenCart,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _StatTile(
                      icon: Icons.biotech_outlined,
                      label: 'Lab cart',
                      value: '${LabCartService.instance.bookingCount}',
                      accent: AppColors.brandGreenDeep,
                      onTap: onOpenLabCart,
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _StatTile(
                      icon: Icons.card_giftcard_rounded,
                      label: 'Reward points',
                      // The live balance: registering credits it, and a
                      // promise the dashboard contradicted would not be one.
                      value: formatRupees(RewardsService.instance.balance),
                      accent: AppColors.brandGreenDeep,
                      onTap: onOpenRewards,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback onTap;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 19, color: accent),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
