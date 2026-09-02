import 'package:flutter/material.dart';

import '../../money.dart';
import '../../theme/app_colors.dart';
import 'agent_model.dart';
import 'agent_service.dart';

/// "Team sales": two sections stacked on this one card. The sales total
/// leads, folded shut over the per-tier breakdown and override commission
/// behind it — detail worth a tap to see, not worth leading with. Underneath
/// it, kept apart on purpose, a second section gives the headcount: how many
/// people make up that total and how many of them are active. A sales figure
/// and a member count answer two different questions, so neither is written
/// as a subtitle of the other.
///
/// The member-by-member roster is a further section again, and never folded;
/// see [AgentTeamRosterSection] in `agent_team_roster_section.dart`.
class AgentTeamSalesCard extends StatefulWidget {
  final Agent agent;

  const AgentTeamSalesCard({super.key, required this.agent});

  @override
  State<AgentTeamSalesCard> createState() => _AgentTeamSalesCardState();
}

class _AgentTeamSalesCardState extends State<AgentTeamSalesCard> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final service = AgentService.instance;
    final agent = widget.agent;
    final total = service.teamSalesTotal(agent);
    final members = service.teamMemberCount(agent);
    final active = service.activeMemberCount(agent);
    // A solid, saturated banner rather than another pale tint — the earnings
    // card above already owns "blue panel, white text", and this borrows it
    // rather than inventing a third look, so the two read as the same money
    // family. The wash underneath stays this card's own, so the white
    // headcount box on it still has something to stand out against.
    const accent = AppColors.brandBlue;

    // The tiers actually present below this agent, deepest-authority first.
    final tiers = AgentLevel.values
        .where((level) => service.teamAtLevel(agent, level).isNotEmpty)
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section one: the sales total, and the switch for the
            // breakdown behind it. Only this banner is the switch — the
            // headcount section below has nothing to do with the arrow.
            Material(
              color: accent,
              child: InkWell(
                key: const ValueKey('team-sales-card'),
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
                          Icons.groups_rounded,
                          size: 20,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          'Team sales ₹${formatRupees(total)}',
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Chevron(expanded: _expanded, accent: AppColors.white),
                    ],
                  ),
                ),
              ),
            ),
            // Everything under the banner sits on its own pale wash, so the
            // white headcount box below still reads as a card of its own
            // rather than blending into the page.
            Container(
              color: AppColors.offerTint,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _expanded
                        ? _SummaryDetails(
                            agent: agent,
                            tiers: tiers,
                            commission: service.teamCommission(agent),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: 12),
                  // Section two: the headcount behind that total. Its own
                  // boxed row rather than a subtitle under the sales figure,
                  // because "what did the team sell" and "who is the team"
                  // are different questions and neither answer belongs
                  // folded into the other.
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.people_alt_outlined,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$members team member${members == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.greenTint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$active active',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandGreenDark,
                            ),
                          ),
                        ),
                      ],
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

/// The detail behind the arrow: per-tier counts and sales, and what the whole
/// downline's volume pays in override commission. The member-by-member roster
/// is a separate section entirely — see [AgentTeamRosterSection] in
/// `agent_team_roster_section.dart`.
class _SummaryDetails extends StatelessWidget {
  final Agent agent;
  final List<AgentLevel> tiers;
  final int commission;

  const _SummaryDetails({
    required this.agent,
    required this.tiers,
    required this.commission,
  });

  @override
  Widget build(BuildContext context) {
    final service = AgentService.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 13),
        Divider(height: 1, color: AppColors.brandBlue.withValues(alpha: 0.2)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.fromLTRB(11, 8, 11, 4),
          child: Column(
            children: [
              for (final level in tiers)
                _BreakdownRow(
                  level: level,
                  members: service.teamAtLevel(agent, level),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(
              Icons.percent_rounded,
              size: 15,
              color: AppColors.brandGreenDeep,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Override commission at ${AgentService.commissionPercent}% of '
                'team sales',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textBody,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.brandGreenDeep,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '₹${formatRupees(commission)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final AgentLevel level;
  final List<Agent> members;

  const _BreakdownRow({required this.level, required this.members});

  @override
  Widget build(BuildContext context) {
    final active = members.where((member) => member.active).length;
    final sales = members.fold<int>(
      0,
      (sum, member) => sum + member.displayPersonalSales,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: level.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              level.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textBody,
              ),
            ),
          ),
          // Flexible rather than bare: a tier with dozens of members and a
          // six-figure total is still a count and an amount, not necessarily
          // one that fits its natural width next to the label.
          Flexible(
            child: Text(
              '${members.length} · $active active',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '₹${formatRupees(sales)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: level.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  final bool expanded;
  final Color accent;

  const _Chevron({required this.expanded, required this.accent});

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
