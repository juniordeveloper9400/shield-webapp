import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'agent_direct_sale.dart';
import 'agent_earnings_card.dart';
import 'agent_model.dart';
import 'agent_team_roster_section.dart';
import 'agent_team_sales.dart';
import 'agent_team_tree_screen.dart';

/// The agent's home base, opened from the "Agent Portal" card on the feed.
///
/// Top to bottom: the flip earnings card (with the withdrawal request on it),
/// the direct-sale list, the team-sales roll-up, the full team roster — never
/// folded away, unlike the roll-up's own per-tier detail — and the way
/// through to the team tree.
class AgentPortalScreen extends StatelessWidget {
  final Agent agent;

  const AgentPortalScreen({super.key, required this.agent});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Agent Portal',
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        children: [
          _AgentStrip(agent: agent),
          const SizedBox(height: 16),
          AgentEarningsCard(agent: agent),
          const SizedBox(height: 22),
          AgentDirectSaleSection(agent: agent),
          const SizedBox(height: 22),
          const Text(
            'Team',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          AgentTeamSalesCard(agent: agent),
          const SizedBox(height: 18),
          AgentTeamRosterSection(agent: agent),
        ],
      ),
      // Pinned to the bottom, always in reach however far the portal is
      // scrolled — the team tree is the screen's main way onward.
      bottomNavigationBar: _MyTeamBar(agent: agent),
    );
  }
}

/// The always-visible "My Team" bar under the portal's scroll area.
class _MyTeamBar extends StatelessWidget {
  final Agent agent;

  const _MyTeamBar({required this.agent});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.pageTint,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AgentTeamTreeScreen(root: agent),
                ),
              ),
              icon: const Icon(Icons.account_tree_rounded, size: 20),
              label: const Text(
                'My Team',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Who the portal belongs to: name, tier and code, in the tier's colour.
class _AgentStrip extends StatelessWidget {
  final Agent agent;

  const _AgentStrip({required this.agent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: agent.level.tint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: agent.level.accent.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: agent.level.accent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              agent.initials,
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
                  agent.name,
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
                  '${agent.level.label} agent · ${agent.agentCode}',
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
