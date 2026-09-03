import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../money.dart';
import '../../theme/app_colors.dart';
import '../rewards/rewards_screen.dart';
import '../rewards/rewards_service.dart';

/// The reward points balance, on a coin, in the home header beside the wallet.
///
/// The points were only ever visible two taps in — behind the menu, on the
/// dashboard tile. A balance nobody can see is a balance nobody spends and
/// nobody works towards, so it now sits in the chrome next to the money it
/// keeps company with: the wallet holds rupees, the coin holds points, and
/// the two are read in one glance.
///
/// A gold coin with the balance struck on a small count badge at its
/// shoulder, the way an app icon carries an unread count — the coin says what,
/// the badge says how many, and neither needs a pill drawn around it. Tapping
/// it opens the rewards screen, where the balance is spelled out and spent.
class PointsBadge extends StatelessWidget {
  /// Matched to the circle actions either side of it, so the header row reads
  /// as one line of controls rather than a coin wedged between two buttons.
  static const double height = 42;

  const PointsBadge({super.key});

  /// What the shoulder badge prints. Grouped in full up to five figures — the
  /// balances a member actually carries — then folded to `12k` / `99k+` so a
  /// runaway number cannot stretch the badge across the header.
  static String _badgeText(int points) {
    if (points < 100000) {
      return formatRupees(points);
    }
    if (points < 100000000) {
      return '${points ~/ 1000}k';
    }
    return '99k+';
  }

  @override
  Widget build(BuildContext context) {
    // The live balance from the reward-points ledger, not a figure printed
    // once: registering and every paid order credit it, and the coin has to be
    // seen to move when they do.
    return ListenableBuilder(
      listenable: RewardsService.instance,
      builder: (context, _) {
        final points = RewardsService.instance.balance;
        final label = formatRupees(points);

        return Tooltip(
          message: 'Reward points · $label',
          child: Semantics(
            button: true,
            label: '$label reward points',
            // The coin and the count are both said in the label above, so a
            // screen reader is not handed the number twice.
            excludeSemantics: true,
            child: SizedBox(
              width: 44,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Material(
                    color: AppColors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RewardsScreen(),
                        ),
                      ),
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: RewardCoin(size: 32, shimmer: true),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -1,
                    right: -2,
                    child: _CountBadge(label: _badgeText(points)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The small count that rides at the coin's shoulder — the balance itself,
/// on a blue chip with a white keyline so it stays legible against whatever
/// the coin's gold is doing behind it.
class _CountBadge extends StatelessWidget {
  final String label;

  const _CountBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.brandBlue,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandNavy.withValues(alpha: 0.30),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          fontSize: 9.5,
          height: 1,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: AppColors.white,
        ),
      ),
    );
  }
}

/// A struck gold coin: a milled rim caught in a sweep of light, a domed face
/// lit from the top-left, and an embossed star.
///
/// Drawn rather than an asset, so it scales to whatever size it is asked for
/// and stays crisp — and so the one place deciding what a point looks like in
/// this app is a handful of colours in [AppColors].
///
/// With [shimmer] on, a glint crosses the face every few seconds. Each pass
/// is a single short animation fired off a timer, not a running loop, so the
/// coin never holds a widget test open in `pumpAndSettle`.
class RewardCoin extends StatefulWidget {
  final double size;
  final bool shimmer;

  const RewardCoin({super.key, required this.size, this.shimmer = false});

  @override
  State<RewardCoin> createState() => _RewardCoinState();
}

class _RewardCoinState extends State<RewardCoin>
    with SingleTickerProviderStateMixin {
  // Both are null until [shimmer] asks for them: a static coin — the far more
  // common case — carries no controller and no timer, and nothing to look up
  // an ancestor for while the tree is being torn down.
  AnimationController? _glint;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.shimmer) {
      _enableGlint();
    }
  }

  void _enableGlint() {
    _glint ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _timer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      final glint = _glint;
      if (mounted && glint != null && !glint.isAnimating) {
        glint.forward(from: 0);
      }
    });
  }

  void _disableGlint() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didUpdateWidget(RewardCoin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shimmer) {
      _enableGlint();
    } else {
      _disableGlint();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _glint?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = _CoinFace(size: widget.size);
    final glint = _glint;
    if (glint == null) {
      return face;
    }
    return ClipOval(
      child: Stack(
        alignment: Alignment.center,
        children: [
          face,
          AnimatedBuilder(
            animation: glint,
            builder: (context, _) => glint.isAnimating
                ? _CoinGlint(size: widget.size, t: glint.value)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _CoinFace extends StatelessWidget {
  final double size;

  const _CoinFace({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // A sweep around the rim — light on the top-left, shade opposite, the
        // tone turning a couple of times between — so the edge reads as milled
        // metal rather than a flat ring.
        gradient: const SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: [
            AppColors.coinEdge,
            AppColors.coinShine,
            AppColors.coinFace,
            AppColors.coinDeep,
            AppColors.coinEdge,
            AppColors.coinShine,
            AppColors.coinDeep,
            AppColors.coinEdge,
          ],
          stops: [0.0, 0.14, 0.30, 0.44, 0.58, 0.72, 0.87, 1.0],
        ),
        border: Border.all(color: AppColors.coinInk, width: size * 0.04),
        boxShadow: [
          BoxShadow(
            color: AppColors.coinInk.withValues(alpha: 0.35),
            blurRadius: size * 0.13,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.76,
          height: size * 0.76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // The domed table of the coin, lit from the top-left.
            gradient: const RadialGradient(
              center: Alignment(-0.4, -0.5),
              radius: 1.0,
              colors: [
                AppColors.coinHighlight,
                AppColors.coinFace,
                AppColors.coinEdge,
              ],
              stops: [0.0, 0.55, 1.0],
            ),
            border: Border.all(color: AppColors.coinEdge, width: size * 0.03),
          ),
          child: Center(
            child: SizedBox(
              width: size * 0.52,
              height: size * 0.52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The cut, thrown down and to the right.
                  Transform.translate(
                    offset: Offset(size * 0.024, size * 0.032),
                    child: Icon(
                      Icons.star_rounded,
                      size: size * 0.46,
                      color: AppColors.coinInk.withValues(alpha: 0.55),
                    ),
                  ),
                  // The lit bevel on the near side.
                  Transform.translate(
                    offset: Offset(-size * 0.018, -size * 0.022),
                    child: Icon(
                      Icons.star_rounded,
                      size: size * 0.46,
                      color: AppColors.coinHighlight,
                    ),
                  ),
                  // The star itself.
                  Icon(
                    Icons.star_rounded,
                    size: size * 0.44,
                    color: AppColors.coinInk,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A diagonal band of light drawn across the coin during a glint.
class _CoinGlint extends StatelessWidget {
  final double size;

  /// 0 → 1 as the band travels from one side of the face to the other.
  final double t;

  const _CoinGlint({required this.size, required this.t});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset((t * 2 - 1) * size * 1.25, 0),
      child: Transform.rotate(
        angle: -0.42,
        child: Container(
          width: size * 0.46,
          height: size * 2.4,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.white.withValues(alpha: 0),
                AppColors.white.withValues(alpha: 0.62),
                AppColors.white.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
