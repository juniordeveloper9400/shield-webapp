import 'package:flutter/material.dart';

import '../wallet/wallet_service.dart';

/// The one pill that shows a privilege plan's status — pending, rejected,
/// active or expired — the same shape and colour wherever a plan is listed
/// (the wallet's submitted-card tiles, the plan card faces).
class PlanStatusBadge extends StatelessWidget {
  final PlanStatus status;

  /// Smaller type for the tight card faces; the default suits a list tile.
  final bool dense;

  const PlanStatusBadge({super.key, required this.status, this.dense = false});

  static const Map<PlanStatus, Color> _colour = {
    PlanStatus.pending: Color(0xFFB4761A),
    PlanStatus.rejected: Color(0xFFB4322F),
    PlanStatus.active: Color(0xFF3E8635),
    PlanStatus.expired: Color(0xFF6B7B95),
  };

  /// The dot-and-label colour for [status] — exposed so a caller that draws
  /// its own status text (a card face) can stay in step.
  static Color colourOf(PlanStatus status) => _colour[status]!;

  @override
  Widget build(BuildContext context) {
    final colour = _colour[status]!;
    final fontSize = dense ? 10.0 : 11.5;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dense ? 5 : 6,
            height: dense ? 5 : 6,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          SizedBox(width: dense ? 5 : 6),
          Text(
            status.label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}
