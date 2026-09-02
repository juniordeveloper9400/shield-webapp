import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../dates.dart';
import '../../money.dart';
import '../../theme/app_colors.dart';
import '../privilege/privilege_tier.dart';
import 'agent_customer.dart';
import 'agent_customer_detail_screen.dart';
import 'agent_model.dart';
import 'agent_service.dart';

/// Muted label text on the customer card's dark background — the same wash
/// the wallet and earnings panels read their own captions in, so every dark
/// panel in the app dims its labels the same way.
const Color _onDarkMuted = Color(0xFFCBD9EE);

/// "Direct sale": the customers this agent personally sold a privilege plan
/// to — not the agents under them, which is what the team tree is for — each
/// with the plan they hold and whether it is still live.
///
/// Leads with a summary — total value, total earned, how many are still
/// active — and folds the customer-by-customer list behind an arrow, the
/// same shape [AgentTeamSalesCard] leads with its own total before the
/// per-tier detail. A wall of customer cards is not what this section needs
/// to open with; the totals are.
class AgentDirectSaleSection extends StatefulWidget {
  final Agent agent;

  const AgentDirectSaleSection({super.key, required this.agent});

  @override
  State<AgentDirectSaleSection> createState() =>
      _AgentDirectSaleSectionState();
}

class _AgentDirectSaleSectionState extends State<AgentDirectSaleSection> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final service = AgentService.instance;
    final agent = widget.agent;
    final customers = service.customersOf(agent);
    const accent = AppColors.brandBlue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Direct sale',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.offerTint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${customers.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Customers you sold a plan to.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        if (customers.isEmpty)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            child: const Text(
              'You have not sold a plan to anyone yet.',
              style: TextStyle(fontSize: 13.5, color: AppColors.textBody),
            ),
          )
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The switch: total value up front, and the arrow that
                  // opens onto every customer that adds up to it.
                  Material(
                    color: accent,
                    child: InkWell(
                      key: const ValueKey('direct-sale-summary'),
                      onTap: _toggle,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: const Icon(
                                Icons.storefront_rounded,
                                size: 20,
                                color: AppColors.white,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                'Direct sale ₹${formatRupees(service.directSaleVolume(agent))}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.25,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SummaryChevron(
                              expanded: _expanded,
                              accent: AppColors.white,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Kept apart from the total on purpose — how much a
                  // customer paid and how many are still active answer
                  // different questions than what it earned this agent.
                  Container(
                    color: AppColors.offerTint,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: _SummaryStat(
                            label: 'CUSTOMERS',
                            value: '${customers.length}',
                          ),
                        ),
                        Expanded(
                          child: _SummaryStat(
                            label: 'ACTIVE',
                            value: '${service.activeCustomerCount(agent)}',
                          ),
                        ),
                        Expanded(
                          child: _SummaryStat(
                            label: 'YOU EARNED',
                            value:
                                '₹${formatRupees(service.directSaleEarnings(agent))}',
                            accent: AppColors.brandGreenDark,
                            alignEnd: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: [
                        for (var i = 0; i < customers.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          _CustomerCard(customer: customers[i]),
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ],
    );
  }
}

/// One figure in the direct-sale summary strip: a small label over the
/// number, so "customers", "active" and "you earned" each get their own
/// column rather than reading as one run-on line.
class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;
  final bool alignEnd;

  const _SummaryStat({
    required this.label,
    required this.value,
    this.accent,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: accent ?? AppColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}

/// The fold arrow on the direct-sale summary — same shape and turn as the
/// one on [AgentTeamSalesCard], so the two "tap to see everything below
/// this total" switches in the portal read as the same control.
class _SummaryChevron extends StatelessWidget {
  final bool expanded;
  final Color accent;

  const _SummaryChevron({required this.expanded, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
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
    );
  }
}

/// One customer, as a card with two sections: a summary of who they are and
/// what their cards are worth in total, then a block per card — its tier,
/// what it earned, its activation and expiry dates, and a month graph of the
/// year it runs. A customer holding more than one card shows one block each.
class _CustomerCard extends StatelessWidget {
  final AgentCustomer customer;

  const _CustomerCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    final service = AgentService.instance;
    final active = customer.isActive;
    final plans = customer.plansByNewest;

    return Material(
      // One colour for the whole card, and the same one on every customer's
      // card in the list — not tied to a plan tier, so the list reads as one
      // consistent kind of card rather than a different colour every scroll.
      // The totals and the plans they total up are one section too, not two:
      // one band behind both rather than a header tint handing off to a
      // second tint for the blocks below it, and individual plan blocks no
      // longer carry their own tier tint either — a customer holding a Gold
      // and a Platinum card is still one customer, one card, one colour.
      //
      // Dark, so the plan blocks sitting on it in a light tint actually read
      // as things placed on the section rather than as another patch of the
      // same pale wash the rest of the portal is already drawn in.
      color: AppColors.brandBlueDeep,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AgentCustomerDetailScreen(customer: customer),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- The customer and their totals, as headed columns
              //      across one row ----
              Align(
                alignment: Alignment.centerRight,
                child: PlanStatusPill(active: active),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: _HeadedCell(
                      head: 'NAME',
                      value: customer.name,
                      accent: AppColors.white,
                      sub: plans.length == 1
                          ? plans.first.tier.name
                          : 'Total ${plans.length} · Active '
                                '${customer.activePlans.length}',
                      subInChip: plans.length > 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: _HeadedCell(
                      head: 'TOTAL AMOUNT',
                      value: '₹${formatRupees(customer.totalAmount)}',
                      accent: AppColors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: _HeadedCell(
                      head: 'TOTAL EARNED',
                      value:
                          '₹${formatRupees(service.commissionOnSale(customer))}',
                      accent: AppColors.planActive,
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // ---- The plans that total up to it, under one subhead ----
              _PlanSectionHead(customer: customer),
              const SizedBox(height: 10),
              for (var i = 0; i < plans.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _PlanBlock(plan: plans[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The subhead over section 2: what the blocks below it are, and how many of
/// them are still live — "Active" is a count here, never a blanket label, so
/// a lapsed plan sitting right under it is never called something it is not.
class _PlanSectionHead extends StatelessWidget {
  final AgentCustomer customer;

  const _PlanSectionHead({required this.customer});

  @override
  Widget build(BuildContext context) {
    final total = customer.planCount;
    final active = customer.activePlans.length;

    return Row(
      children: [
        Text(
          total == 1 ? 'PLAN' : 'PLANS',
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: _onDarkMuted,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.planActive.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.planActive.withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            '$active of $total active',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: AppColors.planActive,
            ),
          ),
        ),
      ],
    );
  }
}

/// One headed column in the customer card's top section: a small uppercase
/// head with its value below, and an optional sub-line — plain muted text, or
/// (with [subInChip]) its own small tinted tag, for a sub-line that is a count
/// worth setting apart from a plain caption.
class _HeadedCell extends StatelessWidget {
  final String head;
  final String value;
  final String? sub;
  final bool subInChip;
  final Color? accent;
  final bool alignEnd;

  const _HeadedCell({
    required this.head,
    required this.value,
    this.sub,
    this.subInChip = false,
    this.accent,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final cross = alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final align = alignEnd ? Alignment.centerRight : Alignment.centerLeft;
    return Column(
      crossAxisAlignment: cross,
      children: [
        Text(
          head,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: _onDarkMuted,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: align,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: accent ?? AppColors.textDark,
            ),
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 4),
          if (subInChip)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.brandBlue.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textBody,
                ),
              ),
            )
          else
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: alignEnd ? TextAlign.end : TextAlign.start,
              style: const TextStyle(fontSize: 11.5, color: _onDarkMuted),
            ),
        ],
      ],
    );
  }
}

/// One card's detail inside the customer card: tier and commission, the two
/// dates that bound its year, and the month graph of that year.
class _PlanBlock extends StatelessWidget {
  final CustomerPlan plan;

  const _PlanBlock({required this.plan});

  @override
  Widget build(BuildContext context) {
    final earned = AgentService.instance.commissionOnPlan(plan);
    final live = plan.isActive;

    return Container(
      // A light tint, not white and not this plan's own tier tint — white
      // would vanish any sense of it sitting on the dark card behind it,
      // and a colour per tier is exactly the "two colours in one section"
      // this block is drawn in one flat wash to avoid.
      decoration: BoxDecoration(
        color: AppColors.pageTint,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlanBadge(tier: plan.tier, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${plan.tier.name} · ₹${formatRupees(plan.amount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹${formatRupees(earned)} earned',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandGreenDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DateCell(
                  label: 'ACTIVATED',
                  value: formatDate(plan.activatedOn),
                ),
              ),
              Expanded(
                child: _DateCell(
                  label: live ? 'RENEWS ON' : 'EXPIRED ON',
                  value: formatDate(plan.expiresOn),
                  alignEnd: true,
                  warn: !live,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PlanTimeline(plan: plan),
        ],
      ),
    );
  }
}

class _DateCell extends StatelessWidget {
  final String label;
  final String value;
  final bool alignEnd;
  final bool warn;

  const _DateCell({
    required this.label,
    required this.value,
    this.alignEnd = false,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final align = alignEnd
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: warn ? AppColors.danger : AppColors.textDark,
          ),
        ),
      ],
    );
  }
}


/// How one month of a plan's run reads on the graph.
enum _Month { covered, current, upcoming, skipped }

/// The plan's validity drawn as a strip of month cells: months already
/// **covered** in green, the month running **now** picked out, months still
/// **upcoming** faint grey, and — for a lapsed plan — the months **skipped**
/// since it ran out, in blue: coverage that went unused, not a debt.
///
/// Month-based rather than a bare Active/Expired pill: an agent sees at a
/// glance how much of a customer's year is left, or how much went unused
/// once it lapsed.
class PlanTimeline extends StatelessWidget {
  final CustomerPlan plan;

  const PlanTimeline({super.key, required this.plan});

  /// Cap on how many skipped months to draw past a lapsed plan's year, so a
  /// very old plan does not stretch the strip off the card.
  static const int _maxSkipShown = 5;

  @override
  Widget build(BuildContext context) {
    const total = PrivilegeProgramme.validityMonths;
    final now = DateTime.now();
    final elapsed =
        ((now.year - plan.activatedOn.year) * 12 +
                (now.month - plan.activatedOn.month))
            .clamp(0, total * 4);
    final covered = elapsed.clamp(0, total);
    final expired = !plan.isActive;
    final overdue = elapsed - total;
    final monthsLeft = total - elapsed;

    // 12 cells while the plan still has road left; 12 plus the skipped tail
    // once it has lapsed.
    final skipShown = expired ? overdue.clamp(0, _maxSkipShown) : 0;
    final cells = total + skipShown;

    _Month stateAt(int m) {
      if (m < covered) {
        return _Month.covered;
      }
      if (m >= total) {
        return _Month.skipped;
      }
      if (!expired && m == covered) {
        return _Month.current;
      }
      return _Month.upcoming;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var m = 0; m < cells; m++) ...[
              if (m > 0) const SizedBox(width: 3),
              Expanded(child: _MonthCell(state: stateAt(m))),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Text(
          expired
              ? (overdue <= 0
                    ? 'Cover ended'
                    // Months past the card's own year, not months missed —
                    // there was never a payment due on them, only coverage
                    // that went unused once the card stopped renewing.
                    : '$overdue month${overdue == 1 ? '' : 's'} unused')
              : 'Month ${covered + 1} of $total · '
                    '${monthsLeft <= 0 ? 'renewal due' : '$monthsLeft month${monthsLeft == 1 ? '' : 's'} left'}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: expired && overdue > 0
                ? AppColors.brandBlue
                : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  final _Month state;

  const _MonthCell({required this.state});

  @override
  Widget build(BuildContext context) {
    final (colour, ring) = switch (state) {
      _Month.covered => (AppColors.brandGreenDark, false),
      _Month.current => (AppColors.brandGreenDark.withValues(alpha: 0.4), true),
      _Month.upcoming => (AppColors.border, false),
      // Blue rather than the app's warning red: a month past the card's own
      // year was never missed or owed, it is coverage that went unused once
      // the card stopped renewing — a different fact from the "EXPIRED ON"
      // date above, which stays red because that one is a warning.
      _Month.skipped => (AppColors.brandBlue, false),
    };

    return Container(
      height: state == _Month.current ? 9 : 6,
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(2),
        border: ring
            ? Border.all(color: AppColors.brandGreenDark, width: 1)
            : null,
      ),
    );
  }
}

/// An agent's photo, once one has been added — drawn to fill whatever
/// circular frame the caller already built, so a tree node and the detail
/// header can each keep their own size, border and fallback.
///
/// Not a widget of its own accord: [fallback] (initials, an icon, whatever
/// the caller was already showing) is what renders while [photoBytes] is
/// null, so adding a photo later changes nothing about a caller that has not
/// added one.
class AgentPhotoFace extends StatelessWidget {
  final Uint8List? photoBytes;
  final double size;
  final Widget fallback;

  const AgentPhotoFace({
    super.key,
    required this.photoBytes,
    required this.size,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = photoBytes;
    if (bytes == null) {
      return fallback;
    }
    return ClipOval(
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// The square, level-coloured tag that leads a sub-agent row and a tree node.
class LevelBadge extends StatelessWidget {
  final AgentLevel level;
  final double size;

  const LevelBadge({super.key, required this.level, this.size = 38});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: level.accent,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        level.code,
        style: TextStyle(
          fontSize: size * 0.26,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          color: AppColors.white,
        ),
      ),
    );
  }
}

/// Active / Inactive, as a pill. Green when working, grey when not.
class ActivePill extends StatelessWidget {
  final bool active;

  const ActivePill({super.key, required this.active});

  @override
  Widget build(BuildContext context) {
    final colour = active ? AppColors.brandGreenDark : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'Active' : 'Inactive',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

/// Active / Expired, for a customer's plan rather than an agent's own
/// standing — the same pill shape as [ActivePill], but a lapsed plan is a
/// refusal rather than a pause, so it reads in the app's one red rather than
/// in grey.
class PlanStatusPill extends StatelessWidget {
  final bool active;

  const PlanStatusPill({super.key, required this.active});

  @override
  Widget build(BuildContext context) {
    final colour = active ? AppColors.brandGreenDark : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'Active' : 'Expired',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

/// The square, tier-coloured tag that leads a customer row — the same shape
/// as [LevelBadge], in the privilege card's own colour rather than the
/// agent-tier ladder's.
class PlanBadge extends StatelessWidget {
  final PrivilegeTier tier;
  final double size;

  const PlanBadge({super.key, required this.tier, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final code = tier.name.split(' ').first.substring(0, 3).toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tier.accent,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        code,
        style: TextStyle(
          fontSize: size * 0.26,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          color: AppColors.white,
        ),
      ),
    );
  }
}
