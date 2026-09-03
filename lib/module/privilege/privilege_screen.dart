import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/neon/wallet_repository.dart';
import '../../theme/app_colors.dart';
import '../auth/auth_flow.dart';
import '../auth/auth_service.dart';
import '../checkout/checkout_order.dart';
import '../checkout/checkout_screen.dart';
import '../registration/registration_flow.dart';
import '../registration/registration_service.dart';
import '../registration/shield_store.dart';
import '../wallet/wallet_service.dart';
import 'privilege_card_face.dart';
import 'privilege_tier.dart';

/// The privilege programme: switch to a card, pick one of its loads, and
/// SHIELD adds 10%.
///
/// Three cards and nothing else above the terms. The card is the thing being
/// bought, so the screen is the card, with that card's loads written under it
/// in its own colour — which is where a member looks for the price of the
/// thing they are already holding.
class PrivilegeScreen extends StatefulWidget {
  const PrivilegeScreen({super.key});

  @override
  State<PrivilegeScreen> createState() => _PrivilegeScreenState();
}

class _PrivilegeScreenState extends State<PrivilegeScreen> {
  /// The card carousel at the top. A fraction under one so the neighbouring
  /// cards show at the edges — which is what says there are more to switch to.
  final PageController _pages = PageController(viewportFraction: 0.86);

  PrivilegeLoad? _selected;

  /// The load last picked on each card, by card name.
  ///
  /// Switching to gold to compare it and switching back must not quietly drop
  /// the ₹30,000 already chosen on silver — the card is put down and picked
  /// up again, not reset.
  final Map<String, int> _chosen = {};

  int _page = 0;

  /// True while the carousel is being driven from a tap rather than a swipe,
  /// so the page callback does not undo the selection that caused the move.
  bool _syncing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Where [tier] stands: the load last picked on it, or its smallest one.
  /// A blank card would be a card with no value written on it.
  PrivilegeLoad _loadFor(PrivilegeTier tier) {
    final amount = _chosen[tier.name];
    return amount == null
        ? tier.entry
        : PrivilegeLoad(tier: tier, amount: amount);
  }

  PrivilegeLoad _faceAt(int index) => _loadFor(PrivilegeProgramme.tiers[index]);

  void _select(PrivilegeLoad load) {
    setState(() {
      _chosen[load.tier.name] = load.amount;
      _selected = load;
    });
    final index = PrivilegeProgramme.tiers.indexWhere(
      (tier) => tier.name == load.tier.name,
    );
    if (index >= 0) {
      _switchTo(index);
    }
  }

  /// Moves the carousel without letting the move re-select anything.
  Future<void> _switchTo(int index) async {
    if (!_pages.hasClients || _page == index) {
      return;
    }
    _syncing = true;
    await _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    _syncing = false;
  }

  /// Swiping to a card picks it: on a wallet of cards, the one in your hand
  /// is the one you are choosing. At whatever load was last picked on it, or
  /// its smallest — the cheapest way in is the safe one to land on.
  void _onPageChanged(int index) {
    setState(() => _page = index);
    if (_syncing) {
      return;
    }
    final tier = PrivilegeProgramme.tiers[index];
    setState(() => _selected = _loadFor(tier));
  }

  Future<void> _activate() async {
    final load = _selected;
    if (load == null) {
      return;
    }

    // Loading a card moves real money, so the member must be signed in and registered.
    await AuthFlow.guard(context, () async {
      if (!RegistrationService.instance.isRegistered) {
        final registered = await RegistrationFlow.show(context);
        if (!registered && !RegistrationService.instance.isRegistered) {
          if (mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text(
                    'Please complete registration to activate the Privilege Programme',
                  ),
                ),
              );
          }
          return;
        }
      }

      if (!mounted) return;

      final done = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CheckoutScreen(
            // The branch is a choice here — this is where a member pins the
            // store their account is served by. Every product and pharmacy
            // checkout after this shows it locked.
            storeSelectable: true,
            order: CheckoutOrder(
              title: load.name,
              subtitle: 'Privilege Programme activation',
              amount: load.amount.toDouble(),
              reference:
                  'PV-${DateTime.now().millisecondsSinceEpoch.remainder(100000)}',
              submitLabel: 'Submit receipt',
              lines: [
                CheckoutLine('Plan amount', load.amount.toDouble()),
                CheckoutLine(
                  'Wallet bonus',
                  load.bonus.toDouble(),
                  isCredit: true,
                ),
                CheckoutLine('Wallet credit', load.credited.toDouble()),
              ],
            ),
            onComplete: (receipt) async {
              // A submission, not an activation: the card is filed for review
              // and credits nothing yet. It shows on the wallet as "awaiting
              // approval"; a Super Admin approves it in the console — that is
              // where the ledger lines and the balance move — and the wallet
              // picks the approval up on its next refresh. The branch chosen
              // here rides along so the approved plan is served by it.
              final submittedAt = DateTime.now();
              WalletService.instance.submitPending(
                load,
                store: StoreDirectory.byId(receipt.storeId),
                on: submittedAt,
              );
              // The durable copy on Neon. Best-effort — a build with no
              // DATABASE_URL, or an unreachable database, must not stop the
              // submission. AuthFlow.guard above has ensured someone is signed
              // in. Awaited only to pin the row's uuid onto the pending card.
              final user = AuthService.instance.currentUser.value;
              if (user != null) {
                final uuid =
                    await WalletRepository.instance.submitCardForApproval(
                  memberPhone: user.phone,
                  memberName: user.name,
                  tierKind: load.tier.kind,
                  amount: load.amount,
                  bonus: load.bonus,
                  cardNumber: load.cardNumber,
                  storeCode: receipt.storeId,
                  receiptReference: receipt.bankReference,
                  receiptFileName: receipt.fileName,
                  receiptImage: receipt.imageDataUrl,
                );
                if (uuid != null) {
                  WalletService.instance
                      .attachPendingRemoteId(submittedAt, uuid);
                }
              }
              // Pin the branch chosen on the checkout to the account, so every
              // product and pharmacy order from here is locked to it. A repeat
              // save is not a second registration reward.
              final profile = RegistrationService.instance.profile;
              if (profile != null && profile.storeId != receipt.storeId) {
                RegistrationService.instance.save(
                  profile.copyWith(storeId: receipt.storeId),
                );
              }
            },
          ),
        ),
      );

      if (!mounted || done != true) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Receipt submitted · ${load.name} is with the counter for '
              'approval. ${load.creditedLabel} lands in your wallet once it is '
              'approved.',
            ),
          ),
        );
      Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final load = _selected;

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Privilege Programme',
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
          _CardCarousel(
            controller: _pages,
            page: _page,
            selected: load,
            holder: RegistrationService.instance.profile?.name ?? '',
            faceAt: _faceAt,
            onPageChanged: _onPageChanged,
            // _select moves the carousel itself, so a tapped pip and a tapped
            // amount travel by exactly the same path.
            onSwitchTo: (index) => _select(_faceAt(index)),
          ),
          const SizedBox(height: 16),
          // The loads of the card currently in hand, under that card and in
          // its colour, so the two read as one object rather than as a card
          // and a separate price list beside it.
          _AmountPanel(
            tier: PrivilegeProgramme.tiers[_page],
            selected: load,
            onSelect: _select,
          ),
          const SizedBox(height: 18),
          const _TermsBox(),
        ],
      ),
      bottomNavigationBar: _ActivateBar(load: load, onActivate: _activate),
    );
  }
}

/// The cards themselves, one to a page, switched by swiping or by tapping a
/// pip beneath them.
///
/// The programme is a set of cards, so the screen opens with the cards rather
/// than with a description of them. Switching repaints the face in that
/// tier's colour, which is the whole difference between silver, gold and
/// platinum said without a word.
class _CardCarousel extends StatelessWidget {
  final PageController controller;
  final int page;
  final PrivilegeLoad? selected;
  final String holder;
  final PrivilegeLoad Function(int index) faceAt;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onSwitchTo;

  const _CardCarousel({
    required this.controller,
    required this.page,
    required this.selected,
    required this.holder,
    required this.faceAt,
    required this.onPageChanged,
    required this.onSwitchTo,
  });

  /// Half the gap between one card and the next.
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final tiers = PrivilegeProgramme.tiers;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The page is a fixed share of the width, so the height that keeps a
        // card card-shaped follows from it rather than being guessed at.
        final faceWidth =
            constraints.maxWidth * controller.viewportFraction - _gap * 2;

        return Column(
          children: [
            SizedBox(
              height: faceWidth / PrivilegeCardFace.aspectRatio,
              child: PageView.builder(
                controller: controller,
                onPageChanged: onPageChanged,
                itemCount: tiers.length,
                itemBuilder: (context, index) {
                  final load = faceAt(index);
                  final isCurrent = index == page;
                  final isSelected = selected?.tier.name == load.tier.name;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _gap),
                    child: AnimatedScale(
                      // The card in hand stands slightly proud of the ones
                      // behind it.
                      scale: isCurrent ? 1 : 0.92,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: GestureDetector(
                        onTap: () => onSwitchTo(index),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: load.accent.withValues(
                                  alpha: isSelected ? 0.45 : 0.2,
                                ),
                                blurRadius: isSelected ? 18 : 10,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          foregroundDecoration: isSelected
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: AppColors.white,
                                    width: 2,
                                  ),
                                )
                              : null,
                          child: PrivilegeCardFace(load: load, holder: holder),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < tiers.length; index++)
                  _SwitchPip(
                    tier: tiers[index],
                    isCurrent: index == page,
                    onTap: () => onSwitchTo(index),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// One pip per card, in that card's colour, and a way to switch to it.
class _SwitchPip extends StatelessWidget {
  final PrivilegeTier tier;
  final bool isCurrent;
  final VoidCallback onTap;

  const _SwitchPip({
    required this.tier,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isCurrent,
      label: tier.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: isCurrent ? 26 : 9,
            height: 7,
            decoration: BoxDecoration(
              color: isCurrent
                  ? tier.accent
                  : tier.accent.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the card in hand can be loaded with.
///
/// Washed in that card's tint and edged in its accent, so the panel reads as
/// the underside of the card above it. Every published load lives on one of
/// the three cards, which is why there is no free-entry amount box: there is
/// no amount to type that is not already a row here.
class _AmountPanel extends StatelessWidget {
  final PrivilegeTier tier;
  final PrivilegeLoad? selected;
  final ValueChanged<PrivilegeLoad> onSelect;

  const _AmountPanel({
    required this.tier,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: tier.tint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tier.accent.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  tier.name,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: tier.accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tier.accent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  tier.rangeLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: tier.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            tier.blurb,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              color: AppColors.textBody,
            ),
          ),
          const SizedBox(height: 10),
          _BenefitsHeadline(tier: tier),
          const SizedBox(height: 12),
          for (final load in tier.loads) ...[
            _AmountRow(
              load: load,
              isSelected: selected == load,
              onTap: () => onSelect(load),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          // The benefits belong to a row, so the panel always has one in mind:
          // whatever is selected on this card, or its entry load before
          // anything is picked and while another card holds the selection.
          _Benefits(
            load: selected != null && selected!.tier.kind == tier.kind
                ? selected!
                : tier.entry,
          ),
        ],
      ),
    );
  }
}

/// "Benefits up to ₹33,000" — the figure the card is sold on.
///
/// Its largest load plus the bonus on it, worked out rather than written
/// down, so it cannot drift from the amounts listed underneath it.
class _BenefitsHeadline extends StatelessWidget {
  final PrivilegeTier tier;

  const _BenefitsHeadline({required this.tier});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.verified_rounded, size: 18, color: tier.accent),
        const SizedBox(width: 7),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Benefits up to '),
                TextSpan(
                  text: tier.benefitsUpToLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: tier.accent,
                  ),
                ),
              ],
            ),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}

/// What the selected amount carries.
///
/// It belongs to the row above it, not to the card. The three silver loads do
/// not carry the same thing — ₹10,000 is one free dental consultation and
/// ₹30,000 is three — so a list stated once for the whole card would be wrong
/// for two of every three amounts on it.
///
/// The list is swapped rather than rebuilt when the amount changes, and
/// animates its height, so the panel does not jump when a row with more
/// benefits than the last is picked.
class _Benefits extends StatelessWidget {
  final PrivilegeLoad load;

  const _Benefits({required this.load});

  @override
  Widget build(BuildContext context) {
    final tier = load.tier;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tier.accent.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 5),
        child: Column(
          key: ValueKey('benefits-${tier.name}-${load.amount}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What ${load.amountLabel} on ${tier.name} includes',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: tier.accent,
              ),
            ),
            const SizedBox(height: 8),
            for (final line in load.benefits)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1, right: 8),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: tier.accent,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: AppColors.textBody,
                        ),
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

/// One load: what is paid, what is added, and what lands in the wallet.
///
/// A price and nothing else. What the amount carries is real and does differ
/// row to row, but it is a seven-line list — printed under all five platinum
/// rows at once it would bury the prices it is meant to justify. So the rows
/// stay prices, and the list under them follows whichever is selected.
class _AmountRow extends StatelessWidget {
  final PrivilegeLoad load;
  final bool isSelected;
  final VoidCallback onTap;

  const _AmountRow({
    required this.load,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final headline = isSelected ? AppColors.white : AppColors.textDark;
    final quiet = isSelected
        ? AppColors.white.withValues(alpha: 0.8)
        : AppColors.textMuted;

    return Material(
      color: isSelected ? load.accent : AppColors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? load.accent
                  : load.accent.withValues(alpha: 0.3),
              width: isSelected ? 1.6 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(11, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: isSelected ? AppColors.white : load.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          load.amountLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: headline,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '+ ${load.bonusLabel} free',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            // The bonus keeps the money-green it shares with every
                            // other saving in the app, except where it sits on the
                            // card's own colour and has to stay legible.
                            color: isSelected
                                ? AppColors.white
                                : AppColors.brandGreenDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        load.creditedLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: headline,
                        ),
                      ),
                      Text(
                        'credited',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: quiet),
                      ),
                    ],
                  ),
                ],
              ),
              // What the amount comes to month by month, on the row being
              // activated. A card is a year of medicine bought up front, and
              // a member weighing ₹10,000 is really asking whether it beats
              // what they already hand over at the counter each month — which
              // is a question ₹10,000 does not answer and ₹916 does.
              //
              // Only on the chosen row: printed under all three it is a fourth
              // figure per row competing with the amount, the bonus and the
              // credit, and the comparison it exists to help with is the one
              // the member has already made by the time they tap.
              if (isSelected) ...[
                const SizedBox(height: 9),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.white.withValues(alpha: 0.26),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.event_repeat_rounded,
                      size: 14,
                      color: AppColors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Covers about ${load.monthlyCoverageLabel} of bills a '
                        'month for ${PrivilegeProgramme.validityMonths} months',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: AppColors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TermsBox extends StatelessWidget {
  const _TermsBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          SizedBox(height: 8),
          _TermLine('Every card adds 10%. A bigger card simply loads more.'),
          _TermLine('The bonus is credited to your SHIELD wallet at once.'),
          _TermLine('Wallet money is spent on orders and lab bookings.'),
          _TermLine('The bonus is store credit, and is not withdrawable.'),
        ],
      ),
    );
  }
}

class _TermLine extends StatelessWidget {
  final String text;

  const _TermLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 5, color: AppColors.brandGreenDark),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivateBar extends StatelessWidget {
  final PrivilegeLoad? load;
  final VoidCallback onActivate;

  const _ActivateBar({required this.load, required this.onActivate});

  @override
  Widget build(BuildContext context) {
    final selected = load;

    return Material(
      color: AppColors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selected == null ? '—' : selected.creditedLabel,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: selected?.accent ?? AppColors.textDark,
                      ),
                    ),
                    Text(
                      selected == null
                          ? 'Pick a card'
                          : 'You pay ${selected.amountLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Disabled until a card is chosen, so this cannot load an amount
              // nobody picked.
              FilledButton(
                onPressed: selected == null ? null : onActivate,
                style: FilledButton.styleFrom(
                  // Wears the chosen card's colour, so the bar and the card
                  // agree on what is about to be activated.
                  backgroundColor: selected?.accent ?? AppColors.brandBlue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Activate',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
