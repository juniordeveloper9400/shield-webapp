import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'referral_level.dart';

/// Serpentine level map: nodes alternate left and right, joined by a curved
/// connector that is solid where the member has already progressed and dashed
/// where the path is still locked.
class JourneyMap extends StatelessWidget {
  final List<ReferralLevel> levels;
  final ReferralProgress progress;

  const JourneyMap({super.key, required this.levels, required this.progress});

  /// Distance from the edge to the centre of a node.
  static const double nodeInset = 44;
  static const double nodeSize = 56;
  static const double connectorHeight = 46;

  bool _isLeft(int index) => index.isEven;

  @override
  Widget build(BuildContext context) {
    final cleared = progress.currentLevel(levels);

    return Column(
      children: [
        for (var i = 0; i < levels.length; i++) ...[
          if (i > 0)
            SizedBox(
              height: connectorHeight,
              width: double.infinity,
              child: CustomPaint(
                painter: _ConnectorPainter(
                  fromLeft: _isLeft(i - 1),
                  toLeft: _isLeft(i),
                  // Solid once the level the path leads *into* is reachable,
                  // and in the colour of the card it leads to, so the route
                  // changes metal as the ladder does.
                  reached: levels[i].level <= cleared + 1,
                  accent: levels[i].accent,
                ),
              ),
            ),
          _LevelRow(
            level: levels[i],
            progress: progress,
            isLeft: _isLeft(i),
            state: _stateFor(levels[i], cleared),
          ),
        ],
      ],
    );
  }

  _NodeState _stateFor(ReferralLevel level, int cleared) {
    if (level.level <= cleared) {
      return _NodeState.cleared;
    }
    if (level.level == cleared + 1) {
      return _NodeState.current;
    }
    return _NodeState.locked;
  }
}

enum _NodeState { cleared, current, locked }

class _LevelRow extends StatelessWidget {
  final ReferralLevel level;
  final ReferralProgress progress;
  final bool isLeft;
  final _NodeState state;

  const _LevelRow({
    required this.level,
    required this.progress,
    required this.isLeft,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final node = _LevelNode(level: level, state: state);
    final card = _LevelCard(level: level, progress: progress, state: state);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: isLeft
            ? [node, const SizedBox(width: 12), Expanded(child: card)]
            : [Expanded(child: card), const SizedBox(width: 12), node],
      ),
    );
  }
}

class _LevelNode extends StatelessWidget {
  final ReferralLevel level;
  final _NodeState state;

  const _LevelNode({required this.level, required this.state});

  @override
  Widget build(BuildContext context) {
    final accent = level.accent;

    // The node is the card, so it is the card's colour in every state it is
    // reachable in. A locked rung is the same colour drained out of it —
    // which is what makes the ladder read as three metals rather than as
    // three shades of the app.
    final (background, border, foreground) = switch (state) {
      _NodeState.cleared => (accent, accent, AppColors.white),
      _NodeState.current => (accent, accent, AppColors.white),
      _NodeState.locked => (
        AppColors.white,
        accent.withValues(alpha: 0.35),
        accent.withValues(alpha: 0.5),
      ),
    };

    return Container(
      width: JourneyMap.nodeSize,
      height: JourneyMap.nodeSize,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 2),
        boxShadow: state == _NodeState.current
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.32),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: switch (state) {
        _NodeState.cleared => Icon(
          Icons.check_rounded,
          size: 28,
          color: foreground,
        ),
        _NodeState.locked => Icon(
          Icons.lock_outline_rounded,
          size: 22,
          color: foreground,
        ),
        _NodeState.current => Text(
          '${level.level}',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: foreground,
          ),
        ),
      },
    );
  }
}

class _LevelCard extends StatefulWidget {
  final ReferralLevel level;
  final ReferralProgress progress;
  final _NodeState state;

  const _LevelCard({
    required this.level,
    required this.progress,
    required this.state,
  });

  @override
  State<_LevelCard> createState() => _LevelCardState();
}

/// The rung folds. Its name, its bar and what it pays are always on; the rules
/// behind it — what counts as a referral, and in what order — come out under
/// the arrow.
///
/// Five rungs each spelling out three steps is a wall of text, and the ladder
/// has to be readable in one screen before any of it is worth reading.
class _LevelCardState extends State<_LevelCard> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    final progress = widget.progress;
    final state = widget.state;
    final isCurrent = state == _NodeState.current;
    final accent = level.accent;
    final locked = state == _NodeState.locked;

    return Opacity(
      opacity: locked ? 0.62 : 1,
      child: Container(
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrent ? accent : accent.withValues(alpha: 0.36),
            width: isCurrent ? 1.8 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: level.tint,
            child: InkWell(
              key: ValueKey('level-card-${level.level}'),
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LevelBadge(level: level, locked: locked),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      level.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        height: 1.2,
                                        fontWeight: FontWeight.w800,
                                        color: locked
                                            ? AppColors.textBody
                                            : AppColors.textDark,
                                      ),
                                    ),
                                  ),
                                  if (state == _NodeState.cleared) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.verified_rounded,
                                      size: 15,
                                      color: accent,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                level.requirement,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: AppColors.textBody,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _DetailsArrow(
                          level: level.level,
                          accent: accent,
                          locked: locked,
                          expanded: _expanded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _DetailBar(
                      label: 'Transacted',
                      have: progress.directReferrals,
                      need: level.referralsRequired,
                      accent: accent,
                      state: state,
                    ),
                    // Somebody has joined but not paid yet: say so on the rung
                    // being worked on, so a sign-up shows up as progress
                    // waiting to happen, not as no change.
                    if (state == _NodeState.current &&
                        progress.pendingReferrals > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.hourglass_top_rounded,
                            size: 13,
                            color: accent,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '${progress.pendingReferrals} joined — counts once '
                              '${progress.pendingReferrals == 1 ? 'they make' : 'they each make'} '
                              'a transaction',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: _expanded
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 12),
                                Divider(
                                  height: 1,
                                  color: accent.withValues(alpha: 0.28),
                                ),
                                const SizedBox(height: 12),
                                _HowItWorks(level: level, locked: locked),
                              ],
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Earn ${level.pointsLabel}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                        Text(
                          switch (state) {
                            _NodeState.cleared => 'Cleared',
                            _NodeState.current => 'In progress',
                            _NodeState.locked => 'Locked',
                          },
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: switch (state) {
                              _NodeState.cleared => accent,
                              _NodeState.current => accent,
                              _NodeState.locked => AppColors.textMuted,
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The fold-out control on a rung: an arrow that turns over when the rules
/// behind the card are showing.
///
/// It is a marker rather than the tap target — the whole card is the switch,
/// because a 28px circle is a small thing to ask a thumb to find five times.
class _DetailsArrow extends StatelessWidget {
  final int level;
  final Color accent;
  final bool locked;
  final bool expanded;

  const _DetailsArrow({
    required this.level,
    required this.accent,
    required this.locked,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: expanded
          ? 'Hide how level $level works'
          : 'Show how level $level works',
      child: Container(
        key: ValueKey('level-details-arrow-$level'),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: locked ? AppColors.white : accent.withValues(alpha: 0.16),
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
      ),
    );
  }
}

/// What the rung pays for, and the three things that have to happen first.
///
/// Every card can show it, folded away until the arrow is tapped. A rung that
/// says only "Refer 10 members" leaves the reader guessing what counts as a
/// referral — an install, a sign-up, a purchase — and the answer is the
/// difference between a reward that arrives and one that does not.
class _HowItWorks extends StatelessWidget {
  final ReferralLevel level;
  final bool locked;

  const _HowItWorks({required this.level, required this.locked});

  @override
  Widget build(BuildContext context) {
    final steps = ReferralLadder.stepsFor(level);
    final accent = level.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ReferralLadder.howItWorks(level),
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Numbered rather than bulleted: these happen in an order, and
                // a referral that skips one does not count.
                Container(
                  width: 17,
                  height: 17,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: locked ? AppColors.white : accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 1.2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: locked ? accent : AppColors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    steps[i],
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.textBody,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ConnectorPainter extends CustomPainter {
  final bool fromLeft;
  final bool toLeft;
  final bool reached;
  final Color accent;

  _ConnectorPainter({
    required this.fromLeft,
    required this.toLeft,
    required this.reached,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final leftX = JourneyMap.nodeInset;
    final rightX = size.width - JourneyMap.nodeInset;
    final startX = fromLeft ? leftX : rightX;
    final endX = toLeft ? leftX : rightX;

    final path = Path()
      ..moveTo(startX, 0)
      // Mirrored control points give a symmetric S between the two nodes.
      ..cubicTo(
        startX,
        size.height * 0.55,
        endX,
        size.height * 0.45,
        endX,
        size.height,
      );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = reached ? accent : AppColors.searchBorder;

    if (reached) {
      canvas.drawPath(path, paint);
    } else {
      canvas.drawPath(_dashed(path), paint);
    }
  }

  /// Rebuilds [source] as a dashed path by walking its metrics.
  Path _dashed(Path source, {double dash = 7, double gap = 5}) {
    final result = Path();
    for (final ui.PathMetric metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dash;
        result.addPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          Offset.zero,
        );
        distance = next + gap;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter oldDelegate) {
    return oldDelegate.fromLeft != fromLeft ||
        oldDelegate.toLeft != toLeft ||
        oldDelegate.reached != reached ||
        oldDelegate.accent != accent;
  }
}

/// The rung's mark: its number over its name, in the level's own colour.
///
/// A badge, not a card. The ladder used to draw a privilege card face here,
/// which said a level was a card you could buy — it is a count of people you
/// brought in, and it should look like a rank rather than a product.
class _LevelBadge extends StatelessWidget {
  final ReferralLevel level;
  final bool locked;

  const _LevelBadge({required this.level, required this.locked});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 58,
      decoration: BoxDecoration(
        color: locked ? AppColors.white : level.accent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: level.accent, width: 1.4),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            locked ? Icons.lock_outline_rounded : Icons.military_tech_rounded,
            size: 19,
            color: locked ? level.accent : AppColors.white,
          ),
          const SizedBox(height: 2),
          Text(
            'LVL ${level.level}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: locked ? level.accent : AppColors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// One threshold of a level: a label, a `have/need` count, and a bar showing
/// how much of that requirement is met.
class _DetailBar extends StatelessWidget {
  final String label;
  final int have;
  final int need;
  final Color accent;
  final _NodeState state;

  const _DetailBar({
    required this.label,
    required this.have,
    required this.need,
    required this.accent,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final met = have >= need;
    final fraction = need <= 0 ? 1.0 : (have / need).clamp(0.0, 1.0);
    final barColour = state == _NodeState.locked
        ? AppColors.searchBorder
        : accent;
    const textColour = AppColors.textMuted;
    final countColour = state == _NodeState.locked
        ? AppColors.textBody
        : accent;

    return Row(
      children: [
        // Wide enough for "Transacted", and scaled down rather than cut to
        // "Transact…" on a narrow phone or a large text size.
        SizedBox(
          width: 76,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: textColour,
              ),
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            // Glides to the new length when a friend's transaction lands while
            // the page is open, rather than jumping. The first build draws at
            // its value with no animation.
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: fraction),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(barColour),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${have > need ? need : have}/$need',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: met ? countColour : textColour,
          ),
        ),
      ],
    );
  }
}
