import 'package:flutter/material.dart';

import '../../dates.dart';
import '../../money.dart';
import '../../theme/app_colors.dart';
import 'agent_customer.dart';
import 'agent_direct_sale.dart';
import 'agent_service.dart';

/// One customer's page: who they are and what their cards are worth in total,
/// then a block per card — its load, what it earned, the two dates that bound
/// its year, a month graph of that year, and what the load itself carries.
/// Reached by tapping a customer card in "Direct sale".
class AgentCustomerDetailScreen extends StatelessWidget {
  final AgentCustomer customer;

  const AgentCustomerDetailScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    final service = AgentService.instance;
    final active = customer.isActive;
    final soldBy = service.byId(customer.agentId);
    final plans = customer.plansByNewest;

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: Text(
          customer.name,
          style: const TextStyle(
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
          // ---- Section 1: the customer and their totals ----
          Container(
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
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: customer.tier.tint,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: customer.tier.accent,
                          width: 1.4,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        customer.initials,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: customer.tier.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.offerTint,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  customer.planCount == 1
                                      ? '1 card'
                                      : '${customer.planCount} cards',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.brandBlue,
                                  ),
                                ),
                              ),
                              PlanStatusPill(active: active),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'TOTAL AMOUNT',
                        value: '₹${formatRupees(customer.totalAmount)}',
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'TOTAL EARNINGS',
                        value:
                            '₹${formatRupees(service.commissionOnSale(customer))}',
                        accent: AppColors.brandGreenDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 12),
                _KeyValue(label: 'Mobile', value: customer.maskedPhone),
                _KeyValue(
                  label: 'Sold by',
                  value: soldBy == null
                      ? '—'
                      : '${soldBy.name} · ${soldBy.agentCode}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            customer.planCount == 1 ? 'The card' : 'The cards',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < plans.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _PlanCard(plan: plans[i]),
          ],
        ],
      ),
    );
  }
}

/// One card, kept small: which plan it is, what it cost, when it was taken
/// out and when it renews or lapsed, and the month graph — nothing this
/// screen's own agent earned off it (that total already sits in the summary
/// above, once for the whole customer, not repeated card by card) and
/// nothing about what the load itself carries. This is the agent checking
/// what a customer holds and whether it is still running, not a copy of the
/// customer's own card statement.
class _PlanCard extends StatelessWidget {
  final CustomerPlan plan;

  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final load = plan.load;
    final live = plan.isActive;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlanBadge(tier: plan.tier, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.tier.name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      load.amountLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PlanStatusPill(active: live),
            ],
          ),
          const SizedBox(height: 10),
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

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;

  const _Metric({required this.label, required this.value, this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: accent ?? AppColors.textDark,
            ),
          ),
        ),
      ],
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
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: warn ? AppColors.danger : AppColors.textDark,
          ),
        ),
      ],
    );
  }
}

class _KeyValue extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

