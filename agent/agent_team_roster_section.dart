import 'package:flutter/material.dart';

import '../../money.dart';
import '../../theme/app_colors.dart';
import 'agent_detail_screen.dart';
import 'agent_direct_sale.dart';
import 'agent_model.dart';
import 'agent_service.dart';

/// "All team members": every agent in the downline, its own section under
/// Team sales rather than tucked inside that card — the roster answers "who
/// is on my team", which is a different question from "what has the team
/// sold", and each earns its own heading rather than sharing one.
class AgentTeamRosterSection extends StatelessWidget {
  final Agent agent;

  const AgentTeamRosterSection({super.key, required this.agent});

  @override
  Widget build(BuildContext context) {
    final count = AgentService.instance.teamMemberCount(agent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'All team members',
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
                '$count',
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
          'Everyone in your downline, grouped by level.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        _TeamRoster(agent: agent),
      ],
    );
  }
}

/// Every agent under [agent], grouped into one foldable section per tier and
/// ordered national → ward, so the downline reads down the chain of authority
/// rather than as one long list. Each section opens and closes on its own
/// header; all start open so the whole team is there at a glance.
class _TeamRoster extends StatefulWidget {
  final Agent agent;

  const _TeamRoster({required this.agent});

  @override
  State<_TeamRoster> createState() => _TeamRosterState();
}

class _TeamRosterState extends State<_TeamRoster> {
  /// Tiers the member has folded shut. Empty means every section is open.
  final Set<AgentLevel> _folded = {};

  void _toggle(AgentLevel level) {
    setState(() {
      if (!_folded.remove(level)) {
        _folded.add(level);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = AgentService.instance.teamOf(widget.agent);

    if (all.isEmpty) {
      return const Text(
        'No one has joined your team yet.',
        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
      );
    }

    // One entry per tier that actually has members, top of the chain first.
    final groups = <MapEntry<AgentLevel, List<Agent>>>[];
    for (final level in AgentLevel.values) {
      final members =
          all.where((agent) => agent.level == level).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      if (members.isNotEmpty) {
        groups.add(MapEntry(level, members));
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < groups.length; i++)
            _TierGroup(
              level: groups[i].key,
              members: groups[i].value,
              open: !_folded.contains(groups[i].key),
              onToggle: () => _toggle(groups[i].key),
              topDivider: i != 0,
            ),
        ],
      ),
    );
  }
}

/// One tier's foldable section: a header that counts the tier and turns its
/// chevron, over the member rows it opens onto.
class _TierGroup extends StatelessWidget {
  final AgentLevel level;
  final List<Agent> members;
  final bool open;
  final VoidCallback onToggle;
  final bool topDivider;

  const _TierGroup({
    required this.level,
    required this.members,
    required this.open,
    required this.onToggle,
    required this.topDivider,
  });

  @override
  Widget build(BuildContext context) {
    final active = members.where((member) => member.active).length;
    final sales = members.fold<int>(
      0,
      (sum, member) => sum + member.displayPersonalSales,
    );

    return Column(
      children: [
        if (topDivider) const Divider(height: 1, color: AppColors.border),
        Material(
          color: level.tint,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              child: Row(
                children: [
                  LevelBadge(level: level, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${level.label} · ${members.length} agent'
                          '${members.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '$active active · ₹${formatRupees(sales)} sales',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: level.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: open
              ? _MemberTable(members: members)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// A tier's members as a table — the name and status leading each row, then
/// what they are worth: plans sold, what those add up to, and the slice of
/// that the viewing agent keeps as override commission. A totals row closes
/// the table, the same way a paper ledger foots its columns, so the tier's
/// earning is read off the table rather than worked out by eye.
///
/// The last column is never the member's own earning — it is what *this*
/// card's agent earns *from* them, which is why it is the one figure in the
/// table picked out in green.
class _MemberTable extends StatelessWidget {
  final List<Agent> members;

  const _MemberTable({required this.members});

  static const double plansWidth = 40;
  static const double amountWidth = 78;
  static const double earningWidth = 78;

  @override
  Widget build(BuildContext context) {
    final service = AgentService.instance;
    final rows = [
      for (final member in members)
        (
          agent: member,
          plans: service.customersOf(member).length,
          amount: member.displayPersonalSales,
          earning: service.commissionFrom(member),
        ),
    ];
    final totalPlans = rows.fold<int>(0, (sum, row) => sum + row.plans);
    final totalAmount = rows.fold<int>(0, (sum, row) => sum + row.amount);
    final totalEarning = rows.fold<int>(0, (sum, row) => sum + row.earning);

    return Column(
      children: [
        const _TableHeaderRow(),
        for (var i = 0; i < rows.length; i++)
          _TableDataRow(
            agent: rows[i].agent,
            plans: rows[i].plans,
            amount: rows[i].amount,
            earning: rows[i].earning,
          ),
        _TableTotalRow(
          plans: totalPlans,
          amount: totalAmount,
          earning: totalEarning,
        ),
      ],
    );
  }
}

const TextStyle _tableHeaderStyle = TextStyle(
  fontSize: 9.5,
  fontWeight: FontWeight.w800,
  letterSpacing: 0.4,
  color: AppColors.textMuted,
);

/// The column headings, so the figures under them never have to be guessed at.
class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.pageTint,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: Row(
        children: [
          const Expanded(child: Text('AGENT', style: _tableHeaderStyle)),
          const SizedBox(
            width: _MemberTable.plansWidth,
            child: Text(
              'PLANS',
              textAlign: TextAlign.center,
              style: _tableHeaderStyle,
            ),
          ),
          const SizedBox(
            width: _MemberTable.amountWidth,
            child: Text(
              'AMOUNT',
              textAlign: TextAlign.right,
              style: _tableHeaderStyle,
            ),
          ),
          const SizedBox(
            width: _MemberTable.earningWidth,
            child: Text(
              'EARNING',
              textAlign: TextAlign.right,
              style: _tableHeaderStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// One agent's row in the table.
class _TableDataRow extends StatelessWidget {
  final Agent agent;
  final int plans;
  final int amount;
  final int earning;

  const _TableDataRow({
    required this.agent,
    required this.plans,
    required this.amount,
    required this.earning,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AgentDetailScreen(agent: agent)),
        ),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: agent.active
                      ? AppColors.brandGreenDark
                      : AppColors.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandBlue,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${agent.level.label} · ${agent.agentCode}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: _MemberTable.plansWidth,
                child: Text(
                  '$plans',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              SizedBox(
                width: _MemberTable.amountWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '₹${formatRupees(amount)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _MemberTable.earningWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '₹${formatRupees(earning)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandGreenDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Foots the table: the tier's plans, amount and — the figure the table
/// exists to answer — total earning, added up under their own columns.
class _TableTotalRow extends StatelessWidget {
  final int plans;
  final int amount;
  final int earning;

  const _TableTotalRow({
    required this.plans,
    required this.amount,
    required this.earning,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.brandGreenDark.withValues(alpha: 0.08),
      ),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Total',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          ),
          SizedBox(
            width: _MemberTable.plansWidth,
            child: Text(
              '$plans',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          ),
          SizedBox(
            width: _MemberTable.amountWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '₹${formatRupees(amount)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ),
          SizedBox(
            width: _MemberTable.earningWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '₹${formatRupees(earning)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppColors.brandGreenDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
