import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../money.dart';
import '../auth/auth_service.dart';
import '../cart/cart_screen.dart';
import '../investor/investor_portal_screen.dart';
import '../investor/investor_service.dart';
import '../location/address_form_screen.dart';
import '../patients/manage_patients_screen.dart';
import '../refer/refer_earn_screen.dart';
import '../registration/registration_flow.dart';
import '../registration/registration_service.dart';
import '../wallet/wallet_screen.dart';
import '../wallet/wallet_service.dart';

/// Profile summary plus the account menu.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final investor = InvestorService.instance.investorForPhone(
      AuthService.instance.currentUser.value?.phone,
    );

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/logos/shield_logo.png',
              height: 26,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 10),
            const Text(
              'Account',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const _ProfileCard(),
          // Carries its own spacing and hides itself once registered, so the
          // list below does not have to know whether it is there.
          const _RegisterBanner(),
          const SizedBox(height: 18),
          // Only for a signed-in investor number — everyone else never sees
          // this group at all.
          if (investor != null) ...[
            _MenuGroup(
              items: [
                _MenuItem(
                  icon: Icons.trending_up_rounded,
                  label: 'Portfolio',
                  trailing: investor.investorCode,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => InvestorPortalScreen(investor: investor),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          _MenuGroup(
            items: [
              _MenuItem(
                icon: Icons.badge_outlined,
                label: 'Registration details',
                onTap: () => RegistrationFlow.show(
                  context,
                  isEditing: RegistrationService.instance.isRegistered,
                ),
              ),
              _MenuItem(
                icon: Icons.account_balance_wallet_outlined,
                label: 'My Wallet',
                trailing: '₹${formatRupees(WalletService.instance.balance)}',
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
              ),
              _MenuItem(
                icon: Icons.shopping_cart_outlined,
                label: 'My Cart',
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const CartScreen())),
              ),
              _MenuItem(
                icon: Icons.location_on_outlined,
                label: 'Manage addresses',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddressFormScreen()),
                ),
              ),
              _MenuItem(
                icon: Icons.groups_outlined,
                label: 'Manage patients',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ManagePatientsScreen(),
                  ),
                ),
              ),
              _MenuItem(
                icon: Icons.description_outlined,
                label: 'My Prescriptions',
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 14),
          _MenuGroup(
            items: [
              _MenuItem(
                icon: Icons.card_giftcard_rounded,
                label: 'Refer & Earn',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReferEarnScreen()),
                ),
              ),
              _MenuItem(
                icon: Icons.headset_mic_outlined,
                label: 'Help & Support',
                onTap: () {},
              ),
              _MenuItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 14),
          _MenuGroup(
            items: [
              _MenuItem(
                icon: Icons.logout_rounded,
                label: 'Log out',
                isDestructive: true,
                // Confirm first — the gate swaps back to the login screen on
                // sign-out and there is no undo.
                onTap: () => _confirmLogOut(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for a yes/no before ending the session. Returning early on "Cancel"
/// leaves the user exactly where they were.
Future<void> _confirmLogOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Log out?'),
      content: const Text(
        'You will need to sign in again to use your account on this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFB4322F),
          ),
          child: const Text('Log out'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await AuthService.instance.logOut();
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    // Listens so completing the form fills the store line in without the tab
    // having to be left and come back.
    return ListenableBuilder(
      listenable: RegistrationService.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final user = AuthService.instance.currentUser.value;
    final store = RegistrationService.instance.profile?.store;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: AppColors.pageTint,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            // Initials of whoever signed in, not a fixed monogram.
            child: Text(
              user?.initials ?? '?',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.brandBlue,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reads the session rather than a fixed name, so a member who
                // signs up sees their own details here.
                Text(
                  user?.name ?? 'Guest',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  user?.displayPhone ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                ),
                if (store != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.storefront_rounded,
                        size: 14,
                        color: AppColors.brandGreenDeep,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          store.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandGreenDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => RegistrationFlow.show(
              context,
              isEditing: RegistrationService.instance.isRegistered,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandBlue,
              side: const BorderSide(color: AppColors.brandBlue),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Edit',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Account-side prompt to finish registering.
///
/// Unlike the home card this one survives a skip: the account page is where
/// someone goes looking for their details, and hiding the way in there would
/// leave the reward unreachable for the rest of the session.
class _RegisterBanner extends StatelessWidget {
  const _RegisterBanner();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RegistrationService.instance,
      builder: (context, _) {
        if (RegistrationService.instance.isRegistered) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Material(
            color: AppColors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => RegistrationFlow.show(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [AppColors.offerTint, AppColors.greenTint],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.stars_rounded,
                        size: 22,
                        color: AppColors.brandGreenDeep,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Complete your registration',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Add your details, pick your store, earn '
                            '${RegistrationService.rewardPoints} points',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.3,
                              color: AppColors.textBody,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 24,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MenuGroup extends StatelessWidget {
  final List<_MenuItem> items;

  const _MenuGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            items[i],
            if (i != items.length - 1)
              const Divider(height: 1, indent: 54, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final bool isDestructive;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? const Color(0xFFB4322F) : AppColors.textDark;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isDestructive ? color : AppColors.brandBlue,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandGreenDark,
                ),
              ),
            if (!isDestructive) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
