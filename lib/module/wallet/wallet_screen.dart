import 'package:flutter/material.dart';

import '../../dates.dart';
import '../../money.dart';
import '../../theme/app_colors.dart';
import '../privilege/plan_status_badge.dart';
import '../auth/auth_service.dart';
import '../privilege/privilege_cards_launch.dart';
import '../privilege/privilege_screen.dart';
import '../privilege/privilege_tier.dart';
import '../privilege/privilege_wallet.dart';
import 'wallet_flip_card.dart';
import 'wallet_service.dart';

/// Filter options for transaction ledger.
enum TransactionFilter { all, inTxn, outTxn }

/// SHIELD wallet: balance, privilege card head, points redemption,
/// quick top-ups, and filtered transaction history (All / In / Out).
///
/// Closed until a privilege card is activated. Money enters this wallet by
/// being loaded onto a card, so before there is a card there is nothing to
/// show and nothing to add to: the balance is masked, the controls are gone,
/// and the screen is the offer to open it. Once open, the wallet leads with
/// its own card: the front carries the balance and this month's allowance,
/// and turning it over lists the privilege cards the money came from.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with WidgetsBindingObserver {
  TransactionFilter _selectedFilter = TransactionFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The app has no push channel, so a plan approved at the counter reaches
    // the member by this screen re-reading the wallet — on open, and again
    // whenever the app comes back to the foreground.
    _refreshFromDatabase();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshFromDatabase();
    }
  }

  void _refreshFromDatabase() {
    final phone = AuthService.instance.currentUser.value?.phone;
    if (phone != null) {
      WalletService.instance.refreshFromDatabase(phone);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Wallet',
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
      body: ListenableBuilder(
        listenable: WalletService.instance,
        builder: (context, _) {
          final allEntries = WalletService.instance.entries;
          final balance = WalletService.instance.balance;
          final card = WalletService.instance.card;

          final filteredEntries = switch (_selectedFilter) {
            TransactionFilter.all => allEntries,
            TransactionFilter.inTxn =>
              allEntries.where((e) => e.isCredit).toList(),
            TransactionFilter.outTxn =>
              allEntries.where((e) => !e.isCredit).toList(),
          };

          final pending = WalletService.instance.pendingCards;

          if (card == null) {
            // Every way into the programme from a shut wallet takes the cards
            // out of the pocket first, the way the home strip does: the lock
            // button, the panel button, and the cards themselves.
            return PrivilegeCardsLaunch(
              builder: (context, fan, open) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  if (pending.isNotEmpty) ...[
                    for (final entry in pending)
                      _PendingCardTile(card: entry),
                    const SizedBox(height: 18),
                  ],
                  _LockedWalletCard(onActivate: open),
                  const SizedBox(height: 18),
                  _ActivatePanel(fan: fan, onOpen: open),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              for (final entry in pending) ...[
                _PendingCardTile(card: entry),
                const SizedBox(height: 12),
              ],
              // The wallet card, and the two things that can be done with
              // what is on it. The actions sit under the card rather than on
              // it: a card that turns over when tapped cannot also carry
              // buttons without one gesture swallowing the other.
              WalletFlipCard(
                cards: WalletService.instance.cards,
                balance: balance,
                monthlyRedeemable: WalletService.instance.monthlyRedeemable,
                redeemed: WalletService.instance.redeemedThisMonth,
                monthlyBalance: WalletService.instance.monthlyBalance,
              ),
              const SizedBox(height: 14),

              // The one control on an open wallet, and the one way money
              // comes in. It used to sit below a points strip and a redeem
              // button; both are gone, so the programme is not competing for
              // the slot any more and takes it outright.
              _TopUpAction(onTopUp: () => _openProgramme(context)),
              const SizedBox(height: 24),

              // Transaction History Section with All / In / Out filter
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Transaction history',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FilterSegment(
                    selected: _selectedFilter,
                    onChanged: (filter) {
                      setState(() => _selectedFilter = filter);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Ledger Transactions List
              Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textDark.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: filteredEntries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 38,
                                color: AppColors.textMuted.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _emptyTextForFilter(_selectedFilter),
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < filteredEntries.length; i++) ...[
                            _TxnRow(entry: filteredEntries[i]),
                            if (i != filteredEntries.length - 1)
                              const Divider(height: 1, color: AppColors.border),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openProgramme(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PrivilegeScreen()));
  }

  String _emptyTextForFilter(TransactionFilter filter) {
    switch (filter) {
      case TransactionFilter.all:
        return 'No transactions yet';
      case TransactionFilter.inTxn:
        return 'No incoming transactions';
      case TransactionFilter.outTxn:
        return 'No outgoing transactions';
    }
  }
}

/// A privilege card the member has submitted that is not on the wallet yet:
/// waiting on the counter, or turned down with a reason.
class _PendingCardTile extends StatelessWidget {
  final PendingWalletCard card;

  const _PendingCardTile({required this.card});

  @override
  Widget build(BuildContext context) {
    final rejected = card.isRejected;
    final accent = rejected ? AppColors.danger : const Color(0xFFB4761A);
    final tint = rejected ? const Color(0xFFFBEBEB) : const Color(0xFFFDF3E0);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                rejected
                    ? Icons.cancel_outlined
                    : Icons.hourglass_bottom_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PlanStatusBadge(status: card.planStatus),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            rejected
                ? (card.note.isEmpty
                      ? 'The counter did not approve this submission.'
                      : card.note)
                : '${card.load.creditedLabel} is added to your wallet once the '
                      'counter approves your receipt. Submitted '
                      '${formatDate(card.submittedAt)}.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textBody,
            ),
          ),
          if (rejected && card.remoteId != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    WalletService.instance.dismissRejected(card.remoteId!),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Dismiss',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The wallet before a card opens it: a figure that exists but cannot be
/// read, and the one control that opens it.
class _LockedWalletCard extends StatelessWidget {
  final VoidCallback onActivate;

  const _LockedWalletCard({required this.onActivate});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF284E94), Color(0xFF1B3564), Color(0xFF132545)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF132545).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Wallet locked',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFBACDE8),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  size: 26,
                  color: AppColors.brandGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Masked rather than zeroed: there is a figure here, it is simply
          // not readable until the wallet is open.
          const Text(
            '₹ ••••••',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 18),
          // One control while the wallet is shut, and it is the way in.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onActivate,
              icon: const Icon(Icons.workspace_premium_rounded, size: 19),
              label: const Text(
                'Activate your Privilege Card',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandGreen,
                foregroundColor: AppColors.textDark,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one thing an open wallet offers: put more on the plan.
///
/// Shield points used to have a strip here and a redeem button under it.
/// Neither earned the room — points are credited elsewhere and were never
/// spent from this screen — and taking them out leaves the programme as the
/// only control, which is also the only way money reaches the balance.
class _TopUpAction extends StatelessWidget {
  final VoidCallback onTopUp;

  const _TopUpAction({required this.onTopUp});

  @override
  Widget build(BuildContext context) {
    final entry = PrivilegeProgramme.tiers.first.entry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onTopUp,
          icon: const Icon(Icons.workspace_premium_rounded, size: 20),
          label: const Text(
            'Top up your Privilege Programme',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandBlue,
            foregroundColor: AppColors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
          ),
        ),
        const SizedBox(height: 8),
        // The terms the button is asking for, kept from the banner it
        // replaced — a call to action that does not say what it costs or
        // what it pays is asking for a decision nobody can make.
        Text(
          'Load ${entry.amountLabel} or more and we add 10%.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: AppColors.textBody),
        ),
      ],
    );
  }
}

class _ActivatePanel extends StatelessWidget {
  final VoidCallback onOpen;

  /// 0 with the cards in the pocket, 1 with them out — driven by whichever
  /// control was tapped.
  final Animation<double> fan;

  const _ActivatePanel({required this.fan, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final silver = PrivilegeProgramme.tiers.first.entry;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        children: [
          // The three cards, in the pocket until they are asked for. The
          // artwork is a control in its own right: it is the cards, and
          // tapping the cards to see the cards is the gesture a finger
          // reaches for before it reads either button.
          Semantics(
            button: true,
            label: 'See the privilege cards',
            child: GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: PrivilegeWallet(fan: fan, width: 190),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Activate your Privilege Card',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your wallet opens with your first card. Start at '
            '${silver.amountLabel} on ${silver.name} and '
            '${silver.creditedLabel} lands in it.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: AppColors.textBody,
            ),
          ),
          const SizedBox(height: 14),
          const _UnlockLine('Spend the balance across the whole app'),
          const _UnlockLine('Pay for orders and lab bookings from it'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'See the cards',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One thing activation unlocks.
class _UnlockLine extends StatelessWidget {
  final String text;

  const _UnlockLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1, right: 8),
            child: Icon(
              Icons.lock_open_rounded,
              size: 15,
              color: AppColors.brandGreenDeep,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// All / In / Out filter tabs segment for transaction ledger.
class _FilterSegment extends StatelessWidget {
  final TransactionFilter selected;
  final ValueChanged<TransactionFilter> onChanged;

  const _FilterSegment({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE2ECF8),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(2.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPill(
            label: 'All',
            isActive: selected == TransactionFilter.all,
            onTap: () => onChanged(TransactionFilter.all),
          ),
          _buildPill(
            label: 'In',
            isActive: selected == TransactionFilter.inTxn,
            onTap: () => onChanged(TransactionFilter.inTxn),
          ),
          _buildPill(
            label: 'Out',
            isActive: selected == TransactionFilter.outTxn,
            onTap: () => onChanged(TransactionFilter.outTxn),
          ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.brandBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.brandBlue.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
            color: isActive ? AppColors.white : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Single transaction ledger item row.
class _TxnRow extends StatelessWidget {
  final WalletEntry entry;

  const _TxnRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: entry.isCredit
                  ? AppColors.greenTint
                  : const Color(0xFFEEF3FA),
              shape: BoxShape.circle,
            ),
            child: Icon(
              entry.isCredit
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              size: 19,
              color: entry.isCredit
                  ? AppColors.brandGreenDark
                  : AppColors.brandBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.date,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${entry.isCredit ? '+' : '-'}₹${formatRupees(entry.amount.abs())}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: entry.isCredit
                  ? AppColors.brandGreenDark
                  : AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
