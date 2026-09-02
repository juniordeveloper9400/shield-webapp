import 'package:flutter/material.dart';

import '../../money.dart';
import '../../theme/app_colors.dart';
import 'agent_direct_sale.dart';
import 'agent_model.dart';
import 'agent_registration_screen.dart';
import 'agent_service.dart';

/// One agent's card: who they are, where they sit, and the figures behind
/// them. Reached by tapping a row in "Direct sale" or a node in "My Team".
class AgentDetailScreen extends StatelessWidget {
  final Agent agent;

  const AgentDetailScreen({super.key, required this.agent});

  Future<void> _addSubAgent(BuildContext context) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AgentRegistrationScreen(
          scopeRoot: agent,
          initialParent: agent,
        ),
      ),
    );
    if (added == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agent registered')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: Text(
          agent.name,
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
      body: ListenableBuilder(
        listenable: AgentService.instance,
        builder: (context, _) {
          final service = AgentService.instance;
          // Read fresh off the roster rather than trusting the widget's own
          // field: that field is fixed at the moment this screen was pushed,
          // and a photo added right here has to show up in this same build.
          final agent = service.byId(this.agent.id) ?? this.agent;
          final directCount = service.directSubAgentsOf(agent).length;
          final teamCount = service.teamMemberCount(agent);
          final teamSales = service.teamSalesTotal(agent);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _HeaderCard(agent: agent),
              if (agent.isRegistered) ...[
                const SizedBox(height: 16),
                _RegistrationCard(agent: agent),
              ],
              const SizedBox(height: 16),
              const Text(
                'Performance',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              _StatGrid(
                tiles: [
                  _Stat('Earned', '₹${formatRupees(service.earnedFor(agent))}'),
                  _Stat(
                    'Redeemed',
                    '₹${formatRupees(service.redeemedFor(agent))}',
                  ),
                  _Stat(
                    'Personal sales',
                    '₹${formatRupees(agent.displayPersonalSales)}',
                  ),
                  _Stat('Team sales', '₹${formatRupees(teamSales)}'),
                  _Stat('Plans activated', '${service.customersOf(agent).length}'),
                  _Stat('Direct sub-agents', '$directCount'),
                  _Stat('Team size', '$teamCount'),
                ],
              ),
              if (agent.level != AgentLevel.ward) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _addSubAgent(context),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
                    label: Text('Add an agent under ${agent.name}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandBlue,
                      side: const BorderSide(color: AppColors.brandBlue),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Agent agent;

  const _HeaderCard({required this.agent});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              _AgentAvatar(agent: agent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.name,
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
                            color: agent.level.accent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${agent.level.label} agent',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                        ActivePill(active: agent.active),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          _KeyValue(label: 'Agent code', value: agent.agentCode),
          _KeyValue(label: 'Area', value: agent.area),
          _KeyValue(label: 'Mobile', value: agent.maskedPhone),
        ],
      ),
    );
  }
}

/// The header's avatar: the photo added at registration, or the level tint
/// and initials until one is. Read-only here — the photo is set on the
/// registration screen and this screen never changes or clears it.
class _AgentAvatar extends StatelessWidget {
  final Agent agent;

  const _AgentAvatar({required this.agent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: agent.level.tint,
        shape: BoxShape.circle,
        border: Border.all(color: agent.level.accent, width: 1.4),
      ),
      alignment: Alignment.center,
      child: AgentPhotoFace(
        photoBytes: agent.photoBytes,
        size: 52,
        fallback: Text(
          agent.initials,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: agent.level.accent,
          ),
        ),
      ),
    );
  }
}

/// The KYC captured at registration, for an agent added through the portal.
class _RegistrationCard extends StatelessWidget {
  final Agent agent;

  const _RegistrationCard({required this.agent});

  @override
  Widget build(BuildContext context) {
    return Container(
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
            'Registration',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          _KeyValue(label: 'Date of birth', value: agent.dobLabel),
          _KeyValue(label: 'Aadhaar', value: agent.maskedAadhaar),
          _KeyValue(label: 'PAN', value: agent.pan.isEmpty ? '—' : agent.pan),
          _KeyValue(
            label: 'Address',
            value: agent.address.isEmpty ? '—' : agent.address,
          ),
          _KeyValue(
            label: 'Place',
            value: agent.place.isEmpty ? '—' : agent.place,
          ),
          _KeyValue(
            label: 'PIN code',
            value: agent.pincode.isEmpty ? '—' : agent.pincode,
          ),
          _KeyValue(label: 'Account no.', value: agent.maskedAccount),
        ],
      ),
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

class _Stat {
  final String label;
  final String value;

  const _Stat(this.label, this.value);
}

class _StatGrid extends StatelessWidget {
  final List<_Stat> tiles;

  const _StatGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
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
                          tile.value,
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
                        tile.label,
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
