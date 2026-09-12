import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../money.dart';
import '../../theme/app_colors.dart';
import '../privilege/privilege_tier.dart';
import 'journey_map.dart';
import 'referral_level.dart';
import 'referral_service.dart';
import 'reward_graph.dart';

/// Refer & earn: current standing, the shareable code, and the level ladder
/// drawn as a journey map.
///
/// A plain, prop-driven screen — [progress] and [code] are exactly what it
/// renders, nothing more — so it stays trivial to pin to a fixture in a test.
/// The real app never constructs it directly: [ReferEarnScreen.open] pushes
/// it wired to [ReferralService], the signed-in member's actual standing.
class ReferEarnScreen extends StatelessWidget {
  final ReferralProgress progress;
  final String code;

  const ReferEarnScreen({
    super.key,
    this.progress = ReferralLadder.sampleProgress,
    this.code = ReferralLadder.fallbackCode,
  });

  /// Pushes the screen wired to the signed-in member's real standing —
  /// refreshed on the way in, and followed live while the screen stays open,
  /// so a referral that lands mid-visit updates the figures without a trip
  /// back out and in again.
  static void open(BuildContext context) {
    ReferralService.instance.ensureLoaded();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListenableBuilder(
          listenable: ReferralService.instance,
          builder: (context, _) => ReferEarnScreen(
            progress: ReferralService.instance.progress,
            code: ReferralService.instance.code,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const levels = ReferralLadder.levels;
    final cleared = progress.currentLevel(levels);
    final next = progress.nextLevel(levels);
    final standing = ReferralLadder.standingFor(progress);

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Refer & Earn',
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
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _StandingCard(
              cleared: cleared,
              next: next,
              progress: progress,
              totalLevels: levels.length,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const _PlanCommissionCard(),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _CodeCard(code: code, accent: standing.accent),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Your journey',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: Text(
              'Clear each level to unlock the next reward.',
              style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 18),
          JourneyMap(levels: levels, progress: progress),
        ],
      ),
    );
  }
}

/// The second way the programme pays: a share of every privilege plan taken
/// out by somebody who was invited.
///
/// It sits directly under the standing card because it is the answer to the
/// question the "Plans activated" figure up there raises — those activations
/// are worth something, and this says what — and a rule that explains a
/// figure has to be within reach of it.
///
/// Folded to its headline until asked. What the commission pays is three
/// bands and a paragraph, and printed open it pushed the invite code and the
/// whole ladder below the fold. The rate is the part worth seeing every
/// visit; the arithmetic behind it is worth reading once.
///
/// The ladder and this are deliberately separate. Rungs clear on referrals
/// alone, so bringing in somebody who never buys a plan still climbs; the
/// commission is what makes the ones who do buy worth more.
class _PlanCommissionCard extends StatefulWidget {
  const _PlanCommissionCard();

  @override
  State<_PlanCommissionCard> createState() => _PlanCommissionCardState();
}

class _PlanCommissionCardState extends State<_PlanCommissionCard> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.brandGreenDeep;
    final percent = ReferralLadder.planCommissionPercent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        // Green through blue, the same pair the home screen's refer card is
        // washed in — the two surfaces that pay you should look related.
        // Pale, because the three bands inside are drawn in their own cards'
        // colours and a deep ground would swallow silver whole.
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.greenTint, AppColors.offerTint],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Material(
          color: AppColors.transparent,
          child: InkWell(
            key: const ValueKey('commission-card'),
            // The whole card is the switch. A 28px arrow is a small thing to
            // ask a thumb to find, and the arrow is a marker of state rather
            // than the only way to change it.
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.percent_rounded,
                          size: 20,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$percent% on every plan they activate',
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.25,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Paid on top of your level points',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textBody,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CommissionArrow(expanded: _expanded, accent: accent),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _expanded
                        ? _CommissionDetail(percent: percent)
                        : const SizedBox(width: double.infinity),
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

/// What the rate comes to: the rule in words and the three bands. Hidden
/// behind the arrow.
class _CommissionDetail extends StatelessWidget {
  final int percent;

  const _CommissionDetail({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 13),
        Divider(
          height: 1,
          color: AppColors.brandGreenDeep.withValues(alpha: 0.22),
        ),
        const SizedBox(height: 12),
        Text(
          'When someone you invited activates a Health Pass plan, $percent% of '
          'what they load comes back to you as Sahakar money.',
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: AppColors.textBody,
          ),
        ),
        const SizedBox(height: 12),
        // The three bands sit on white rather than straight on the wash. Each
        // figure is drawn in its own card's colour, and silver's slate grey
        // does not carry enough contrast against a tint to be read at this
        // size — on white it does.
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: AppColors.brandGreenDeep.withValues(alpha: 0.18),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // What that comes to on each of the three cards, worked out from
              // the programme's own amounts rather than written down, so the
              // figures cannot drift from what the privilege screen is selling.
              for (final tier in PrivilegeProgramme.tiers)
                _CommissionRow(tier: tier),
            ],
          ),
        ),
      ],
    );
  }
}

/// The fold-out marker on the commission card: an arrow that turns over when
/// the figures behind it are showing.
class _CommissionArrow extends StatelessWidget {
  final bool expanded;
  final Color accent;

  const _CommissionArrow({required this.expanded, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: expanded
          ? 'Hide what the commission pays'
          : 'Show what the commission pays',
      child: Container(
        key: const ValueKey('commission-arrow'),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.7),
          shape: BoxShape.circle,
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        alignment: Alignment.center,
        child: AnimatedRotation(
          turns: expanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: accent,
          ),
        ),
      ),
    );
  }
}

/// One card's band: what it can be loaded with, and what that pays back.
class _CommissionRow extends StatelessWidget {
  final PrivilegeTier tier;

  const _CommissionRow({required this.tier});

  @override
  Widget build(BuildContext context) {
    // The band's ends, not every load on it. Platinum has five amounts and
    // listing all of them would turn a rule into a price list.
    final low = ReferralLadder.planCommissionOn(tier.lowest);
    final high = ReferralLadder.planCommissionOn(tier.highest);
    final range = low == high
        ? '₹${formatRupees(low)}'
        : '₹${formatRupees(low)} – ₹${formatRupees(high)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: tier.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tier.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textBody,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            range,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: tier.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _StandingCard extends StatelessWidget {
  final int cleared;
  final ReferralLevel? next;
  final ReferralProgress progress;
  final int totalLevels;

  const _StandingCard({
    required this.cleared,
    required this.next,
    required this.progress,
    required this.totalLevels,
  });

  @override
  Widget build(BuildContext context) {
    final nextLevel = next;
    final standing = ReferralLadder.standingFor(progress);
    final accent = standing.accent;

    return Container(
      key: const ValueKey('standing-card'),
      decoration: BoxDecoration(
        color: AppColors.brandBlueDeep,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.24)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Current level',
                  style: TextStyle(fontSize: 13, color: Color(0xFFE6EBF3)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$cleared of $totalLevels',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _deepen(accent),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            cleared == 0 ? 'Not started' : 'Level $cleared - ${standing.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              height: 1.12,
              fontWeight: FontWeight.w800,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 12),
          _MetricGrid(progress: progress),
          const SizedBox(height: 14),
          // The four figures above say how far the member has come; the graph
          // says where that leaves them on a ladder of five, and how much
          // steeper the paying gets from here. Neither reads as the other.
          RewardGraph(levels: ReferralLadder.levels, progress: progress),
          if (nextLevel != null) ...[
            const SizedBox(height: 12),
            Text(
              'Refer '
              '${(nextLevel.referralsRequired - progress.directReferrals).clamp(0, 99)}'
              ' more to reach Level ${nextLevel.level} and earn '
              '${nextLevel.pointsLabel}',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: Color(0xFFE6EBF3),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Color _deepen(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness * 0.48).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * 1.05).clamp(0.0, 1.0))
        .toColor();
  }
}

class _MetricGrid extends StatelessWidget {
  final ReferralProgress progress;

  const _MetricGrid({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      runSpacing: 10,
      children: [
        SizedBox(
          width: MediaQuery.sizeOf(context).width / 2 - 32,
          child: _Metric(
            value: '${progress.directReferrals}',
            label: 'Referred',
          ),
        ),
        SizedBox(
          width: MediaQuery.sizeOf(context).width / 2 - 32,
          child: _Metric(
            value: '${progress.plansActivated}',
            label: 'Plans activated',
          ),
        ),
        SizedBox(
          width: MediaQuery.sizeOf(context).width / 2 - 32,
          child: _Metric(
            value: ReferralLadder.pointsEarnedLabel(progress),
            label: 'Points',
          ),
        ),
        SizedBox(
          width: MediaQuery.sizeOf(context).width / 2 - 32,
          child: _Metric(
            value: progress.sahakarMoneyLabel,
            label: 'Sahakar money earned',
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;

  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.white,
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(fontSize: 12, color: Color(0xFFE6EBF3)),
          ),
        ),
      ],
    );
  }
}

class _CodeCard extends StatelessWidget {
  final String code;
  final Color accent;

  const _CodeCard({required this.code, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your invite code',
            style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.pageTint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent, width: 1.3),
                  ),
                  child: Text(
                    code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _InviteButton(code: code),
            ],
          ),
        ],
      ),
    );
  }
}

class _InviteButton extends StatelessWidget {
  final String code;

  const _InviteButton({required this.code});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await SharePlus.instance.share(
            ShareParams(
              subject: 'Join me on SHIELD',
              text:
                  'Join me on SHIELD! Save up to 51% on medicines and unlock Health Pass membership. '
                  'Use my invite code $code when you sign up.',
            ),
          );
        } on Exception {
          // Platforms without a share sheet (some desktop browsers) throw
          // rather than silently doing nothing.
          messenger.showSnackBar(
            const SnackBar(content: Text('Sharing is not available here')),
          );
        }
      },
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
      label: const Text(
        'Invite',
        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brandBlue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
