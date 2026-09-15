import 'package:flutter/material.dart';

/// The bone colour every skeleton placeholder in the app is drawn in —
/// shared so a skeleton for one section always reads as the same kind of
/// "still loading" as any other, not a different grey per screen.
const Color skeletonBone = Color(0xFFE3E6F0);

/// Wraps [child] in the same slow fade-in/out pulse every loading skeleton
/// in the app uses (see `agent_team_tree_screen.dart`'s `_HierarchySkeleton`,
/// which this mirrors) — one place for the timing, so every skeleton in the
/// app breathes at the same rate rather than each screen picking its own.
class SkeletonPulse extends StatefulWidget {
  final Widget child;

  const SkeletonPulse({super.key, required this.child});

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.45,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _pulse, child: widget.child);
  }
}

/// One rectangular placeholder "bone" — a name/amount/line stand-in.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: skeletonBone,
        borderRadius: borderRadius ?? BorderRadius.circular(6),
      ),
    );
  }
}
