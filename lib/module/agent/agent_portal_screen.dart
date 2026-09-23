import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_colors.dart';
import 'agent_direct_sale.dart';
import 'agent_earnings_card.dart';
import 'agent_model.dart';
import 'agent_service.dart';
import 'agent_team_roster_section.dart';
import 'agent_team_sales.dart';
import 'agent_team_skeleton.dart';
import 'agent_team_tree_screen.dart';

/// The agent's home base, opened from the "Agent Portal" card on the feed.
///
/// Top to bottom: the flip earnings card (with the withdrawal request on it),
/// the direct-sale list, the team-sales roll-up, the full team roster — never
/// folded away, unlike the roll-up's own per-tier detail — and the way
/// through to the team tree.
class AgentPortalScreen extends StatefulWidget {
  final Agent agent;

  const AgentPortalScreen({super.key, required this.agent});

  @override
  State<AgentPortalScreen> createState() => _AgentPortalScreenState();
}

class _AgentPortalScreenState extends State<AgentPortalScreen> {
  Agent get agent =>
      AgentService.instance.byId(widget.agent.id) ?? widget.agent;

  @override
  void initState() {
    super.initState();
    AgentService.instance.addListener(_salesChanged);
    AgentService.instance.refresh();
  }

  void _salesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AgentService.instance.removeListener(_salesChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fire-and-forget: ensureLoaded() is idempotent (a no-op once the one
    // remote fetch it ever makes has settled), so calling it here on every
    // build is safe and is what actually starts the team's own data
    // loading — nothing else on the path into this screen does.

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
      body: RefreshIndicator(
        onRefresh: AgentService.instance.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            ListenableBuilder(
              listenable: AgentService.instance,
              builder: (context, _) {
                final error = AgentService.instance.loadError;
                if (error == null) return const SizedBox.shrink();
                return ListTile(
                  title: Text(error),
                  trailing: TextButton(
                    onPressed: AgentService.instance.refresh,
                    child: const Text('Retry'),
                  ),
                );
              },
            ),
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
            ListenableBuilder(
              listenable: AgentService.instance,
              builder: (context, _) => AgentService.instance.isTeamLoaded
                  ? Column(
                      children: [
                        AgentTeamSalesCard(agent: agent),
                        const SizedBox(height: 18),
                        AgentTeamRosterSection(agent: agent),
                      ],
                    )
                  : const AgentTeamSkeleton(),
            ),
          ],
        ),
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

/// Who the portal belongs to: name, tier and code, in the tier's colour —
/// and, underneath, the same code again as an actual invitation: a customer
/// who checks out with it on their order attributes that sale to this agent
/// (see `WalletRepository.submitCardForApproval`'s `agentCode` doc), so the
/// code sitting here as plain text was never actually usable for that —
/// nothing to copy, nothing to send. [_AgentCodeInvite] is what turns it
/// into one.
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          const SizedBox(height: 12),
          Divider(height: 1, color: agent.level.accent.withValues(alpha: 0.25)),
          const SizedBox(height: 12),
          _AgentCodeInvite(agent: agent),
        ],
      ),
    );
  }
}

/// The agent's code, made actually shareable — a customer who enters it at
/// checkout (the "Agent code (optional)" field on the order summary) has
/// their purchase counted as this agent's direct sale. Mirrors
/// `refer_earn_screen.dart`'s `_CodeCard`/`_InviteButton` (same shape, same
/// share-sheet approach) rather than inventing a second way to do this.
class _AgentCodeInvite extends StatelessWidget {
  final Agent agent;

  const _AgentCodeInvite({required this.agent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your agent code',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textBody,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: agent.level.accent.withValues(alpha: 0.5),
                    width: 1.3,
                  ),
                ),
                child: Text(
                  agent.agentCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _AgentInviteButton(agent: agent),
          ],
        ),
      ],
    );
  }
}

class _AgentInviteButton extends StatelessWidget {
  final Agent agent;

  const _AgentInviteButton({required this.agent});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await SharePlus.instance.share(
            ShareParams(
              subject: 'My Sahakar 360 agent code',
              text:
                  "I'm a Sahakar 360 agent — ${agent.name}. Enter my agent code "
                  '${agent.agentCode} when you check out on the Sahakar 360 app '
                  'so your order is placed through me.',
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
      icon: const Icon(Icons.share_rounded, size: 17),
      label: const Text(
        'Invite',
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: agent.level.accent,
        foregroundColor: AppColors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
