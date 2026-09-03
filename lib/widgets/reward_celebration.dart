import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A full-screen "you earned points" moment: a gold coin springs up to fill the
/// screen, throws off a burst of sparkles, then the point count lands under it.
///
/// Reusable for every earn event — registration, referrals, order rewards.
///
/// ```dart
/// await RewardCelebration.show(context, points: 10);
/// ```
///
/// Resolves when it dismisses (auto after ~2.8s, or on tap), so a caller can
/// wait for the beat before moving on.
class RewardCelebration {
  const RewardCelebration._();

  static Future<void> show(
    BuildContext context, {
    required int points,
    String caption = 'reward points earned',
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.62),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) =>
            _RewardCelebrationView(points: points, caption: caption),
      ),
    );
  }
}

class _RewardCelebrationView extends StatefulWidget {
  final int points;
  final String caption;

  const _RewardCelebrationView({required this.points, required this.caption});

  @override
  State<_RewardCelebrationView> createState() => _RewardCelebrationViewState();
}

class _RewardCelebrationViewState extends State<_RewardCelebrationView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _dismiss();
      }
    });

  late final Animation<double> _coin = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.34, curve: Curves.elasticOut),
  );
  late final Animation<double> _spin = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
  );
  late final Animation<double> _spark = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.20, 0.62, curve: Curves.easeOut),
  );
  late final Animation<double> _text = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.40, 0.72, curve: Curves.easeOutBack),
  );
  late final Animation<double> _fadeOut = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.90, 1.0, curve: Curves.easeIn),
  );

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_leaving || !mounted) {
      return;
    }
    _leaving = true;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    // The base diameter; elasticOut overshoots it, so the coin briefly reads
    // as filling the screen before it settles.
    final coinSize = shortest * 0.62;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismiss,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Opacity(
            opacity: 1 - _fadeOut.value,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Sparkle burst, behind the coin so points read on top.
                CustomPaint(
                  size: Size.square(coinSize * 3.4),
                  painter: _SparkPainter(
                    t: _spark.value,
                    coinRadius: coinSize / 2,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.rotate(
                      angle: (1 - _spin.value) * math.pi * 0.9,
                      child: Transform.scale(
                        scale: _coin.value.clamp(0.0, 1.35),
                        child: _Coin(size: coinSize),
                      ),
                    ),
                    SizedBox(height: coinSize * 0.16),
                    Opacity(
                      opacity: _text.value.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, (1 - _text.value).clamp(0.0, 1.0) * 26),
                        child: _EarnedText(
                          points: (widget.points * _text.value.clamp(0.0, 1.0))
                              .round(),
                          caption: widget.caption,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Coin extends StatelessWidget {
  final double size;

  const _Coin({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 1.0,
          colors: [
            AppColors.coinHighlight,
            AppColors.coinShine,
            AppColors.coinFace,
            AppColors.coinEdge,
          ],
          stops: [0.0, 0.32, 0.7, 1.0],
        ),
        border: Border.all(color: AppColors.coinDeep, width: size * 0.035),
        boxShadow: [
          BoxShadow(
            color: AppColors.coinFace.withValues(alpha: 0.55),
            blurRadius: size * 0.35,
            spreadRadius: size * 0.02,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.74,
        height: size * 0.74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.coinEdge.withValues(alpha: 0.6),
            width: size * 0.018,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.star_rounded,
          size: size * 0.46,
          color: AppColors.coinInk,
          shadows: const [
            Shadow(color: AppColors.coinHighlight, offset: Offset(-1, -1)),
          ],
        ),
      ),
    );
  }
}

class _EarnedText extends StatelessWidget {
  final int points;
  final String caption;

  const _EarnedText({required this.points, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '+$points',
          style: TextStyle(
            fontSize: 46,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -1,
            shadows: [
              Shadow(
                color: AppColors.coinFace.withValues(alpha: 0.9),
                blurRadius: 24,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}

/// A ring of four-point stars flung outward from the coin, growing then fading.
class _SparkPainter extends CustomPainter {
  final double t;
  final double coinRadius;

  const _SparkPainter({required this.t, required this.coinRadius});

  static const int _count = 14;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) {
      return;
    }
    final center = size.center(Offset.zero);
    final travel = coinRadius * 0.55 + coinRadius * 1.9 * Curves.easeOut.transform(t);
    final opacity = (1 - t) * (t < 0.15 ? t / 0.15 : 1.0);
    final starLen = coinRadius * (0.16 - 0.10 * t);

    for (var i = 0; i < _count; i++) {
      final angle = (i / _count) * math.pi * 2 + (i.isEven ? 0.18 : -0.12);
      final wobble = 1.0 + (i % 3) * 0.12;
      final pos = center +
          Offset(math.cos(angle), math.sin(angle)) * travel * wobble;
      final color = (i.isEven ? AppColors.coinHighlight : Colors.white)
          .withValues(alpha: opacity.clamp(0.0, 1.0));
      _drawStar(canvas, pos, starLen * (i.isEven ? 1.0 : 0.7),
          angle + t * 2.0, color);
    }
  }

  void _drawStar(
      Canvas canvas, Offset c, double len, double rot, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    for (var k = 0; k < 4; k++) {
      final a = rot + k * math.pi / 2;
      final tip = c + Offset(math.cos(a), math.sin(a)) * len;
      final l = c + Offset(math.cos(a + 0.35), math.sin(a + 0.35)) * len * 0.28;
      final r = c + Offset(math.cos(a - 0.35), math.sin(a - 0.35)) * len * 0.28;
      if (k == 0) {
        path.moveTo(l.dx, l.dy);
      } else {
        path.lineTo(l.dx, l.dy);
      }
      path.lineTo(tip.dx, tip.dy);
      path.lineTo(r.dx, r.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.t != t;
}
