import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Re-exported so this file stays the one import `delete_account_test.dart`
// (and anywhere else that reaches these straight off `AccountScreen`)
// already uses — see `legal_links.dart`'s own doc for why the links
// themselves live there instead, shared with the sign-in screen's note.
export '../../widgets/legal_links.dart';

import '../../theme/app_colors.dart';
import '../../money.dart';
import '../../widgets/legal_links.dart';
import '../agent/agent_portal_screen.dart';
import '../agent/agent_service.dart';
import '../agent/become_agent_screen.dart';
import '../auth/auth_service.dart';
import '../cart/cart_screen.dart';
import '../investor/investor_portal_screen.dart';
import '../investor/investor_service.dart';
import '../location/address_form_screen.dart';
import '../patients/manage_patients_screen.dart';
import '../refer/referral_service.dart';
import '../registration/registration_flow.dart';
import '../registration/registration_service.dart';
import '../wallet/wallet_screen.dart';
import '../wallet/wallet_service.dart';

/// Profile summary plus the account menu.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final phone = AuthService.instance.currentUser.value?.phone;
    final investor = InvestorService.instance.investorForPhone(phone);
    final agent = AgentService.instance.agentForPhone(phone);

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
          // An approved agent gets straight through to their portal; a
          // plain member — the common case — gets the way to apply.
          // Neither shows for a recruit whose application is still with
          // the admin console: BecomeAgentScreen itself reads that status
          // and shows "under review" instead of the form, so this row
          // still opens something useful for them, not a dead end.
          _MenuGroup(
            items: [
              agent != null
                  ? _MenuItem(
                      icon: Icons.badge_rounded,
                      label: 'Agent Portal',
                      trailing: agent.agentCode,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AgentPortalScreen(agent: agent),
                        ),
                      ),
                    )
                  : _MenuItem(
                      icon: Icons.how_to_reg_outlined,
                      label: 'Become a SHIELD Agent',
                      onTap: () => BecomeAgentScreen.open(context),
                    ),
            ],
          ),
          const SizedBox(height: 14),
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
                icon: Icons.headset_mic_outlined,
                label: 'Help & Support',
                onTap: () {},
              ),
              _MenuItem(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                onTap: () => _openPrivacyPolicy(context),
              ),
              _MenuItem(
                icon: Icons.description_outlined,
                label: 'Terms & Conditions',
                onTap: () => _openTerms(context),
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
          const SizedBox(height: 14),
          _MenuGroup(
            items: [
              _MenuItem(
                icon: Icons.delete_forever_rounded,
                label: 'Delete Account',
                isDestructive: true,
                // A second, harder confirm than log out — this one has no
                // way back at all.
                onTap: () => _confirmDeleteAccount(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _openPrivacyPolicy(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final opened = await openPrivacyPolicy();
  if (opened) {
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Could not open the Privacy Policy.'),
        backgroundColor: AppColors.textDark,
      ),
    );
}

Future<void> _openTerms(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final opened = await openTerms();
  if (opened) {
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Could not open the Terms & Conditions.'),
        backgroundColor: AppColors.textDark,
      ),
    );
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

/// Opens the delete-account dialog. The gate swaps back to the login screen
/// once [AuthService.deleteAccount] clears [AuthService.currentUser], the
/// same way [_confirmLogOut] leaves it to happen — nothing here navigates by
/// hand.
Future<void> _confirmDeleteAccount(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DeleteAccountDialog(),
  );
}

/// Asks a member to type DELETE before their account is actually removed —
/// a plain Yes/No is too easy to tap through on an action with no undo at
/// all, unlike [_confirmLogOut]'s.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _typed = TextEditingController();
  bool _deleting = false;

  static const _confirmWord = 'DELETE';

  bool get _canConfirm =>
      _typed.text.trim().toUpperCase() == _confirmWord && !_deleting;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_canConfirm) {
      return;
    }
    setState(() => _deleting = true);
    await AuthService.instance.deleteAccount();
    if (!mounted) {
      return;
    }
    // Closed either way: on success this leaves currentUser already null, so
    // the gate underneath swaps to the login screen the same way it does
    // after a plain log out; on a no-op (nobody was signed in) there is
    // simply nothing left to confirm.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently removes your profile, saved addresses and '
            'patients from SHIELD. It cannot be undone, and you will need '
            'to sign up again — with a fresh account — to use SHIELD on '
            'this number.',
          ),
          const SizedBox(height: 14),
          Text(
            'Type $_confirmWord to confirm.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _typed,
            enabled: !_deleting,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: _confirmWord,
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _deleting
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _canConfirm ? _confirm : null,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFB4322F),
          ),
          child: _deleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Delete Account'),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    // Loads the member's own code the moment this card is first shown,
    // rather than waiting for a visit to Refer & Earn — the Member ID line
    // below needs it just as much as that screen's own invite-code card
    // does, and this is the one place asking for it costs nothing extra
    // (ReferralService.attach() already runs it on sign-in in most cases;
    // this only fills a gap for a session where that hasn't landed yet).
    ReferralService.instance.ensureLoaded();
    // Listens so completing the form fills the store line in, and the real
    // Member ID replaces the placeholder once it loads, without the tab
    // having to be left and come back.
    return ListenableBuilder(
      listenable: Listenable.merge([
        RegistrationService.instance,
        ReferralService.instance,
      ]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final user = AuthService.instance.currentUser.value;
    final store = RegistrationService.instance.profile?.store;
    final memberId = ReferralService.instance.code;
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
                const SizedBox(height: 5),
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: memberId));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('Member ID copied'),
                        ),
                      );
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Member ID: $memberId',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandBlue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.copy_rounded,
                        size: 13,
                        color: AppColors.brandBlue,
                      ),
                    ],
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
