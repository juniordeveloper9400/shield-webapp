import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/legal_links.dart';
import '../auth/auth_service.dart';
import 'account_menu.dart';

/// Support, legal and account-management items — split out from the main
/// Account menu (Help & Support, Privacy Policy, Terms & Conditions, Delete
/// Account all used to sit there directly) since none of them are things a
/// member reaches for often, the way My Wallet or My Orders are.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          AccountMenuGroup(
            items: [
              AccountMenuItem(
                icon: Icons.headset_mic_outlined,
                label: 'Help & Support',
                onTap: () {},
              ),
              AccountMenuItem(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                onTap: () => _openPrivacyPolicy(context),
              ),
              AccountMenuItem(
                icon: Icons.description_outlined,
                label: 'Terms & Conditions',
                onTap: () => _openTerms(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AccountMenuGroup(
            items: [
              AccountMenuItem(
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

/// Opens the delete-account dialog. The gate swaps back to the login screen
/// once [AuthService.deleteAccount] clears [AuthService.currentUser] —
/// nothing here navigates by hand.
Future<void> _confirmDeleteAccount(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DeleteAccountDialog(),
  );
}

/// Asks a member to type DELETE before their account is actually removed —
/// a plain Yes/No is too easy to tap through on an action with no undo at
/// all.
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
            'patients from Sahakar 360. It cannot be undone, and you will need '
            'to sign up again — with a fresh account — to use Sahakar 360 on '
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
