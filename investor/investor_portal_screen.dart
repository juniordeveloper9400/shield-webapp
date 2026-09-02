import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/neon/investor_repository.dart';
import '../../dates.dart';
import '../../money.dart';
import '../../theme/app_colors.dart';
import '../registration/shield_store.dart';
import 'investor_model.dart';
import 'investor_service.dart';
import 'investor_sparkline.dart';

/// The investor's home base, opened from the "Investor Access" card on the
/// feed or the Portfolio row in Account.
///
/// Top to bottom: who the stake belongs to, the headline figures (units and
/// amount invested), the return on that investment led by the rupee figure
/// itself, the same return read as a fixed yearly-or-monthly plan — set once,
/// when the stake was opened, with a request to admin the only way to move it
/// — the one trend line and history table on the whole screen underneath it,
/// and the one outlet the stake is actually in. An investor's own portfolio,
/// not the customer book behind it — that stays inside the business.
class InvestorPortalScreen extends StatelessWidget {
  final Investor investor;

  const InvestorPortalScreen({super.key, required this.investor});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Portfolio',
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _InvestorStrip(investor: investor),
          const SizedBox(height: 16),
          _StatGrid(investor: investor),
          const SizedBox(height: 18),
          _RoiCard(investor: investor),
          const SizedBox(height: 18),
          _ReturnPlanCard(investor: investor),
          const SizedBox(height: 22),
          const Text(
            'Invested store',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          _InvestedStoreCard(store: investor.investedStore),
        ],
      ),
    );
  }
}

/// Who the portal belongs to: name, code and how long they have held their
/// stake, in the investor tier's own gold.
class _InvestorStrip extends StatelessWidget {
  final Investor investor;

  const _InvestorStrip({required this.investor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.goldTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.goldAccent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              investor.initials,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  investor.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Investor since ${formatDate(investor.investedSince)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textBody,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Units and amount invested — what was put in, not what it is worth now.
class _StatGrid extends StatelessWidget {
  final Investor investor;

  const _StatGrid({required this.investor});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Total units invested', '${investor.totalUnits}'),
      ('Total amount invested', '₹${formatRupees(investor.totalInvested)}'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final tileWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: tileWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tile.$2,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tile.$1,
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
          ],
        );
      },
    );
  }
}

/// Return on investment led by the rupee figure itself — "Total returns" is
/// the whole of what this card says. The trend line behind that figure
/// lives one card down, on the return plan, where it has a history table
/// under it to back it up rather than sitting here a second time with
/// nothing of its own to add.
class _RoiCard extends StatelessWidget {
  final Investor investor;

  const _RoiCard({required this.investor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Return on Investment',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Measured against what was put in, to date.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Text(
            '₹${formatRupees(investor.totalReturns)}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: AppColors.brandGreenDark,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Total returns',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The same return read as a pace rather than a lifetime total — what this
/// stake is earning per year, or per month, at the rate it has run so far.
/// A view of [Investor.totalReturns], not a second figure competing with it.
///
/// Reads [Investor.planType] rather than a toggle of its own — the plan is
/// fixed at whichever it was set to when the stake was opened. The one action
/// on the card sends admin a request to switch to the other cadence; it does
/// not flip the plan itself.
class _ReturnPlanCard extends StatelessWidget {
  final Investor investor;

  const _ReturnPlanCard({required this.investor});

  @override
  Widget build(BuildContext context) {
    final yearly = investor.planType == InvestorPlanType.yearly;
    final amount = yearly ? investor.yearlyReturnPace : investor.monthlyReturnPace;
    final history = investor.returnHistory(yearly: yearly);
    final labels = investor.returnHistoryLabels(yearly: yearly);
    // The same rupee figures the Return History rows print below, set
    // straight onto the graph — what each year (or month) actually earned,
    // not just its shape.
    final pointAmounts = [for (final value in history) '₹${formatRupees(value)}'];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Return Plan',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              _PlanBadge(planType: investor.planType),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'What this stake is earning, at the pace it has run so far.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Text(
            '₹${formatRupees(amount)}',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            yearly ? 'Per year' : 'Per month',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          // The same continuous line the home card teases, here plotted
          // against this stake's own history rather than left decorative —
          // the last six years, or the last six months, whichever
          // [Investor.planType] has fixed it to — with what each point
          // actually earned printed right above it.
          TrendSparkline(values: history, height: 96, valueLabels: pointAmounts),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          const Text(
            'Return History',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          // Most recent first — the order every other history-style list in
          // the app already reads in.
          for (var i = history.length - 1; i >= 0; i--)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      labels[i],
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textBody,
                      ),
                    ),
                  ),
                  Text(
                    '₹${formatRupees(history[i])}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          _PlanChangeAction(investor: investor),
        ],
      ),
    );
  }
}

/// The one control on the return-plan card: a request to admin to move the
/// plan to the other cadence.
///
/// The plan is fixed when the stake is opened, so this cannot flip it — it
/// records a `REQUESTED` row ([InvestorRepository.requestPlanChange], which
/// writes `app.investor_plan_change_request`) and marks the session
/// ([InvestorService.markPlanChangeRequested]) so the button reads back as
/// pending and cannot be sent twice.
class _PlanChangeAction extends StatelessWidget {
  final Investor investor;

  const _PlanChangeAction({required this.investor});

  Future<void> _request(BuildContext context) async {
    final target = investor.planType.other;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Switch to the ${target.label} plan?'),
        content: Text(
          'Your return plan is fixed at ${investor.planType.label}. Our team '
          'will review the request and confirm the switch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    InvestorService.instance.markPlanChangeRequested();
    // Best-effort durable copy — a build with no DATABASE_URL, or an
    // unreachable database, must not swallow the request the investor just
    // confirmed.
    unawaited(
      InvestorRepository.instance.requestPlanChange(
        investorCode: investor.investorCode,
        investorName: investor.name,
        investorPhone: investor.phone,
        currentPlanType: investor.planType,
        requestedPlanType: target,
        investedStoreCode: investor.investedStore.id,
        totalUnits: investor.totalUnits,
        unitPrice: investor.unitPrice,
        investedSince: investor.investedSince,
        roiPercent: investor.roiPercent,
      ),
    );

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Request sent — our team will confirm the switch.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: InvestorService.instance,
      builder: (context, _) {
        if (InvestorService.instance.planChangeRequested) {
          return const Row(
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: AppColors.textMuted),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Change requested — pending admin review',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ),
            ],
          );
        }
        final target = investor.planType.other;
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _request(context),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandGreenDark,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text('Request the ${target.label} plan'),
          ),
        );
      },
    );
  }
}

/// The fixed plan the return figure above is read against — a label, not a
/// choice: nothing on this card lets it be tapped into the other one.
class _PlanBadge extends StatelessWidget {
  final InvestorPlanType planType;

  const _PlanBadge({required this.planType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.brandGreenDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${planType.label} Plan',
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: AppColors.white,
        ),
      ),
    );
  }
}

/// The one outlet this stake is actually in — name, full address and
/// opening hours, the same detail the checkout screen's own store field
/// carries.
class _InvestedStoreCard extends StatelessWidget {
  final ShieldStore store;

  const _InvestedStoreCard({required this.store});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.panelBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              size: 21,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store.name,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  store.addressLine,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        store.hours,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
