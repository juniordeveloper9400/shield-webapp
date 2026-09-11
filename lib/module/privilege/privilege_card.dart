import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../wallet/wallet_service.dart';
import 'privilege_cards_launch.dart';
import 'privilege_tier.dart';
import 'privilege_wallet.dart';

/// Home entry point for the privilege programme, sat under the hero banner.
///
/// The cards themselves rather than an icon of them: the programme is three
/// cards, and tapping the strip takes them out of the wallet before opening
/// the screen they are chosen on — so the thing that moves under the finger
/// is the thing the next screen is about.
///
/// It is a call to activate, so it stands down once a plan is active: the
/// wallet is open, and the strip that lives on the wallet screen carries the
/// programme from there. Nothing takes its place on the home feed.
class PrivilegeCard extends StatelessWidget {
  const PrivilegeCard({super.key});

  /// How wide the wallet is drawn on the strip.
  static const double walletWidth = 112;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WalletService.instance,
      builder: (context, _) => WalletService.instance.isActivated ||
              WalletService.instance.hasPendingSubmission
          ? const SizedBox.shrink()
          : const _PrivilegeCallToActivate(),
    );
  }
}

class _PrivilegeCallToActivate extends StatelessWidget {
  const _PrivilegeCallToActivate();

  @override
  Widget build(BuildContext context) {
    final entry = PrivilegeProgramme.tiers.first.entry;
    final top = PrivilegeProgramme.tiers.last.loads.last;

    return PrivilegeCardsLaunch(
      builder: (context, fan, open) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
        child: Material(
          color: AppColors.brandNavy,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: open,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  PrivilegeWallet(fan: fan, width: PrivilegeCard.walletWidth),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Activate your Health Pass Programme',
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Load ${entry.amountLabel}, get ${entry.bonusLabel} '
                          'free. Every card adds 10%.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // The span the three cards cover between them, which is
                        // what the wallet beside it cannot say in numbers at
                        // this size.
                        Text(
                          '${entry.amountLabel} – ${top.amountLabel} · '
                          '${PrivilegeProgramme.tiers.length} cards',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.white,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
