import 'package:flutter/material.dart';

import '../../money.dart';
import '../../theme/app_colors.dart';
import '../categories/categories_screen.dart';
import '../home/points_badge.dart' show RewardCoin;
import '../home/refer_earn_card.dart';
import '../refer/refer_earn_access.dart';
import 'rewards_service.dart';

/// The reward-points home, opened from the coin in the header.
///
/// The coin up there only ever said how many points; nothing said what they
/// were for. This screen is that missing half: the hundred-to-a-rupee rate,
/// what those coins are worth as a discount at checkout, and — below the
/// fold — the offers and referral route a member can use to earn more.
///
/// Coins are a discount, not a balance: they come off the bill when the
/// member shops and are never paid out as cash or moved to the wallet.
///
/// Modelled on a rewards wallet a member would already know from other apps:
/// a coloured hero carrying the headline figure, a card notched into its lower
/// edge, then labelled sections for everything else.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  /// Points to a rupee. The one exchange rate in the programme, held on
  /// [RewardsService] so the hero figure, the coin-worth card, the wallet
  /// redemption and the backend can never quote different ones: 100 coins
  /// are worth ₹1.
  static const int pointsPerRupee = RewardsService.pointsPerRupee;

  /// The rate stated in the round numbers a member reads it in.
  static const String rateLabel = '100 = ₹1';

  /// What the "three orders this month" offer coupon is worth.
  static const int milestoneReward = 350;

  /// `124.00` — [points] as a rupee amount, always two decimals.
  static String rupeesFor(int points) =>
      (points / pointsPerRupee).toStringAsFixed(2);

  /// Whole rupees only — the discount rounds down to the nearest ₹1.
  static int wholeRupeesFor(int points) =>
      RewardsService.rupeesForPoints(points);

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  @override
  void initState() {
    super.initState();
    RewardsService.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      body: ListenableBuilder(
        listenable: RewardsService.instance,
        builder: (context, _) {
          final points = RewardsService.instance.balance;

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              _Hero(points: points),
              // Pulled up so it notches into the gradient's lower edge. The
              // shift is paint-only, so the list below keeps flowing from the
              // card's real box — the gap to the next section is that shift
              // plus the small spacer under it.
              Transform.translate(
                offset: const Offset(0, -28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _CoinWorthCard(points: points),
                ),
              ),
              const SizedBox(height: 10),

              // Straight under the coin-worth card, because the offers are the
              // fastest way to grow the balance it just explained.
              const _SectionLabel('EXCLUSIVE OFFERS'),
              const SizedBox(height: 4),
              const Text(
                'JUST FOR YOU',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 18),
              const _ExclusiveOffers(),
              const SizedBox(height: 30),

              // Refer & Earn is the whole of this section, so an agent or
              // investor — who is not offered it — loses the heading too.
              const ReferEarnGate(
                child: Column(
                  children: [
                    _SectionLabel('GET INSTANT COINS'),
                    SizedBox(height: 14),
                    // Carries its own horizontal padding and bottom margin,
                    // unlike the flat card it replaced.
                    ReferEarnCard(),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _NeedHelpRow(),
              ),

              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The coloured head of the screen: the back row and the headline figure. The
/// redeem card that notches into its lower edge is drawn by the list that
/// hosts this, not from here — keeping the overlap a plain paint shift rather
/// than a stack of guessed offsets.
class _Hero extends StatelessWidget {
  final int points;

  const _Hero({required this.points});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.brandBlue, AppColors.brandNavy],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      // Room under the figure for the card to reach up into without touching
      // the text above it.
      padding: const EdgeInsets.only(bottom: 46),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.white,
                  tooltip: 'Back',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '₹${RewardsScreen.rupeesFor(points)}',
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${formatRupees(points)} reward points earned on Sahakar 360',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.85),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The white card notched into the hero: the rate, the balance restated in
/// rupees, and what those coins can and cannot do.
///
/// Coins are a discount, not a balance: they come off the bill at checkout and
/// are never paid out as cash or moved to the wallet. The card says exactly
/// that, and its one button is a way into the shop rather than a way to cash
/// out.
class _CoinWorthCard extends StatelessWidget {
  final int points;

  const _CoinWorthCard({required this.points});

  @override
  Widget build(BuildContext context) {
    final rupees = RewardsScreen.rupeesFor(points);
    final canSpend = RewardsScreen.wholeRupeesFor(points) > 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          // Scaled down rather than wrapped: the rate and the balance each
          // read as one line or not at all, and a test font — or a member at
          // double text size — would otherwise burst the card.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const RewardCoin(size: 15),
                const SizedBox(width: 6),
                Text(
                  RewardsScreen.rateLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const _Dot(),
                const Icon(
                  Icons.local_offer_rounded,
                  size: 13,
                  color: AppColors.brandGreenDeep,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Spent at checkout',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textBody,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: AppColors.border),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const RewardCoin(size: 22),
                const SizedBox(width: 8),
                Text(
                  formatRupees(points),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDark,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    '=',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Text(
                  '₹$rupees off',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.brandBlue,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.greenTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shopping_bag_rounded,
                  size: 22,
                  color: AppColors.brandBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DarkButton(
                  label: canSpend ? 'Shop and use coins' : 'Shop to earn coins',
                  // Coins are only spent inside an order, so the one action
                  // here is a way into the shop — opens the category browser,
                  // where a basket is one tap away.
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CategoriesScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Coins come off your bill at checkout. They can’t be withdrawn '
            'as cash or moved to your wallet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Exclusive offers, just for you": a pair of coupon-style cards, side by
/// side, each a headline reward and one way to claim it.
///
/// Drawn as tickets — a dark body, a badge punched over the top edge, a
/// perforation above a pale action tab — because that is the shape a member
/// already reads as "an offer to claim" rather than "a fact about my account".
class _ExclusiveOffers extends StatelessWidget {
  const _ExclusiveOffers();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 210),
          child: const _OfferCoupon(
            icon: Icons.workspace_premium_rounded,
            headline: 'Win flat',
            amount: RewardsScreen.milestoneReward,
            body: 'on three orders placed this month',
            accent: 'this month',
            cta: 'Start now',
          ),
        ),
      ),
    );
  }
}

class _OfferCoupon extends StatelessWidget {
  final IconData icon;
  final String headline;
  final int amount;
  final String body;

  /// A fragment of [body] to lift into the brand green, the way the reference
  /// card highlights the part that names the thing being rewarded.
  final String accent;
  final String cta;

  const _OfferCoupon({
    required this.icon,
    required this.headline,
    required this.amount,
    required this.body,
    required this.accent,
    required this.cta,
  });

  void _run(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CategoriesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parts = body.split(accent);

    return Padding(
      // Room above the card for the badge that overhangs its top edge.
      padding: const EdgeInsets.only(top: 24),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.textDark,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.fromLTRB(12, 34, 12, 14),
            child: Column(
              children: [
                Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const RewardCoin(size: 18),
                      const SizedBox(width: 6),
                      Text(
                        formatRupees(amount),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: parts.first),
                      TextSpan(
                        text: accent,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandGreen,
                        ),
                      ),
                      if (parts.length > 1) TextSpan(text: parts[1]),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: AppColors.white.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 12),
                const _CouponPerforation(),
                const SizedBox(height: 12),
                _CouponButton(label: cta, onTap: () => _run(context)),
              ],
            ),
          ),
          // The badge, sat half over the top edge of the ticket.
          Positioned(
            top: -24,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.brandGreen, width: 2.4),
              ),
              child: Icon(icon, size: 22, color: AppColors.brandGreenDeep),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dashed tear-line across a coupon, with a notch bitten out of each edge.
class _CouponPerforation extends StatelessWidget {
  const _CouponPerforation();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Notch(),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: _DashedLine(),
          ),
        ),
        _Notch(),
      ],
    );
  }
}

class _Notch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // The page tint showing through, so the ticket reads as punched rather
    // than merely dotted.
    return Container(
      width: 12,
      height: 12,
      decoration: const BoxDecoration(
        color: AppColors.pageTint,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 4.0;
        const gap = 3.0;
        final count = (constraints.maxWidth / (dash + gap)).floor().clamp(0, 60);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(
              width: dash,
              height: 1.4,
              color: AppColors.white.withValues(alpha: 0.35),
            ),
          ),
        );
      },
    );
  }
}

class _CouponButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CouponButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 40,
          width: double.infinity,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DarkButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _DarkButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? AppColors.brandNavy : AppColors.searchBorder,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 46,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                  ),
                ),
              ),
              if (enabled)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.white,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.textMuted,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// A centred caption with a rule running out to either margin.
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          const Expanded(child: Divider(height: 1, color: AppColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const Expanded(child: Divider(height: 1, color: AppColors.border)),
        ],
      ),
    );
  }
}

class _NeedHelpRow extends StatelessWidget {
  const _NeedHelpRow();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _toast(context, 'Our support team will reach out shortly.'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: const Row(
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 20,
                color: AppColors.brandBlue,
              ),
              SizedBox(width: 10),
              Text(
                'Need help?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

