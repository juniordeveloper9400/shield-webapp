import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'privilege_tier.dart';

/// A privilege card drawn the way a card in a wallet looks: rings of the
/// tier's own colour under a frosted panel, a chip, and the figures embossed
/// on the front.
///
/// The colour is not decoration. Silver, gold and platinum are told apart in
/// a wallet by their finish long before anyone reads the name off them, and
/// the card face is built so that switching tier repaints everything —
/// background, rings and chrome — from the one accent the tier owns.
class PrivilegeCardFace extends StatelessWidget {
  /// The card and the amount it is being issued for. A card face without an
  /// amount would be a card nobody could read a value off.
  final PrivilegeLoad load;

  /// Embossed across the front. Falls back to the programme's own name for a
  /// member who has not registered yet, rather than showing an empty line.
  final String holder;

  /// Small enough that the serial and the holder would be unreadable, so it
  /// shows the tier and the amount alone. Used for the cards in the wallet on
  /// the home strip, where all that shows of a card at rest is the strip
  /// above the pocket — which is why the name goes at the top here and the
  /// amount at the bottom, the opposite way round from the full face.
  final bool compact;

  const PrivilegeCardFace({
    super.key,
    required this.load,
    this.holder = '',
    this.compact = false,
  });

  /// The proportions of a card in the hand, and what every face is laid out
  /// against.
  static const double aspectRatio = 245 / 155;

  /// On the contact plate. Named so a test can measure it: the column that
  /// holds it stretches its children, and a chip that inherits that stretch
  /// becomes a gold bar the width of the card.
  static const Key chipKey = Key('privilege-card-chip');

  /// The width a compact face is designed against before being scaled.
  static const double compactReference = 104;

  /// On the card number. Named so a test can measure what share of the card
  /// it takes: the number is scaled to fit a fraction of the width, and the
  /// fraction is the whole of what makes it look like a card number.
  static const Key numberKey = Key('privilege-card-number');

  /// How much of the card's width the number spans.
  ///
  /// A payment card sets its number across roughly three quarters of the
  /// front, not the whole of it. Scaling to a fraction rather than fixing a
  /// point size keeps that proportion on a face drawn at any width.
  static const double numberWidthFactor = 0.76;

  /// Eighteen rings, outermost first, from a light wash of [accent] down to
  /// near-black.
  ///
  /// Built from the accent rather than listed per tier so a new card needs
  /// one colour, not eighteen — and so the ramp can never drift away from the
  /// colour the rest of the app paints that tier in.
  static List<Color> ringsFor(Color accent) {
    final base = HSLColor.fromColor(accent);
    const steps = 18;
    return [
      for (var index = 0; index < steps; index++)
        () {
          final t = index / (steps - 1);
          return HSLColor.fromAHSL(
            1,
            // A slow drift towards the warm end, which is what gives the
            // rings their depth instead of reading as one flat colour.
            (base.hue - 20 * t) % 360,
            (base.saturation * (0.95 + 0.35 * t)).clamp(0.0, 1.0),
            ui.lerpDouble(0.58, 0.11, t)!,
          ).toColor();
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PrivilegeCardSurface(
      load: load,
      borderRadius: BorderRadius.circular(compact ? 9 : 15),
      child: compact
          // Laid out against a fixed card and scaled to whatever box it is
          // given. A compact face is drawn anywhere from a rung of the
          // referral ladder to the home wallet, and type sized for one of
          // those overflows the other.
          ? FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: compactReference,
                height: compactReference / aspectRatio,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _compactBody(),
                ),
              ),
            )
          : Padding(padding: const EdgeInsets.all(16), child: _fullBody()),
    );
  }

  Widget _fullBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Label('Health Pass', ' card')),
            SizedBox(width: 8),
            PrivilegeIssuerMark(),
          ],
        ),
        const SizedBox(height: 9),
        // Aligned rather than sized alone: the column stretches its children,
        // and a stretched chip is a gold bar across the card.
        const Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            key: chipKey,
            height: 26,
            width: 34,
            child: PrivilegeCardChip(),
          ),
        ),
        const SizedBox(height: 10),
        // Set across the front the way a card number is set: left-aligned,
        // monospaced, and spanning a fixed share of the width so it holds the
        // same proportion on a face drawn at any size.
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: numberWidthFactor,
          child: FittedBox(
            key: numberKey,
            fit: BoxFit.fitWidth,
            alignment: Alignment.centerLeft,
            child: Text(
              load.cardNumber,
              maxLines: 1,
              softWrap: false,
              style: onCard(
                20,
                FontWeight.w700,
              ).copyWith(fontFamily: 'monospace', letterSpacing: 2),
            ),
          ),
        ),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HOLDER', style: _caption()),
                  Text(
                    holder.isEmpty ? 'SHIELD MEMBER' : holder.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: onCard(11, FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('LOADED', style: _caption()),
                Text(
                  load.amountLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: onCard(
                    17,
                    FontWeight.w800,
                  ).copyWith(fontFamily: 'monospace', letterSpacing: 1.2),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          // Where a payment card prints its expiry. The bonus is the one
          // figure a member wants off the front of this card.
          '10% BONUS · ${load.bonusLabel}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: onCard(10.5, FontWeight.w700).copyWith(letterSpacing: 0.3),
        ),
      ],
    );
  }

  static TextStyle _caption() => onCard(7.5, FontWeight.w700).copyWith(
    letterSpacing: 0.8,
    color: AppColors.white.withValues(alpha: 0.75),
  );

  Widget _compactBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                // "Gold Shield" is the tier; on a face this size the word
                // Shield is the one that can go, because the card itself
                // says it.
                load.name.split(' ').first.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: onCard(9, FontWeight.w800).copyWith(letterSpacing: 0.9),
              ),
            ),
            const SizedBox(width: 6),
            const SizedBox(height: 14, width: 14, child: PrivilegeCardChip()),
          ],
        ),
        const Spacer(),
        Text(
          load.amountLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: onCard(12.5, FontWeight.w800),
        ),
        Text(
          'SHIELD',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: onCard(7.5, FontWeight.w700).copyWith(letterSpacing: 0.7),
        ),
      ],
    );
  }

  /// Type for anything printed on a card surface.
  ///
  /// White with a soft shadow: the rings run from a pale wash to nearly black
  /// within one card, so no flat colour is legible across the whole of it and
  /// the shadow is what carries the text over the light end.
  static TextStyle onCard(double size, FontWeight weight) {
    return TextStyle(
      fontSize: size,
      height: 1.15,
      fontWeight: weight,
      color: AppColors.white,
      shadows: const [
        Shadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 1)),
      ],
    );
  }
}

/// The card's surface: the rings in its tier's colour, under the frosted
/// panel that keeps white text legible on them.
///
/// Separated from [PrivilegeCardFace] because the card is not only ever shown
/// at card size. The wallet screen is the card the wallet was opened on, and
/// it wears this surface at panel size with its own balance printed on it —
/// one card, drawn the same way wherever it turns up.
class PrivilegeCardSurface extends StatelessWidget {
  final PrivilegeLoad load;
  final BorderRadius borderRadius;

  /// Fills the box it is given when true, which is what a card face wants.
  /// False takes the height of [child], which is what a panel wants.
  final bool expand;

  final Widget child;

  const PrivilegeCardSurface({
    super.key,
    required this.load,
    required this.borderRadius,
    required this.child,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final rings = PrivilegeCardFace.ringsFor(load.accent);

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        // Passthrough hands the panel its own width and lets its height come
        // from what is printed on it; expand fills a card-shaped box.
        fit: expand ? StackFit.expand : StackFit.passthrough,
        children: [
          Positioned.fill(child: CustomPaint(painter: _RingsPainter(rings))),
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 2.8, sigmaY: 2.8),
            child: Container(
              color: AppColors.white.withValues(alpha: 0.18),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// A caption on the card front, emboldening the first word the way the
/// reference card sets "**Credit** card".
class _Label extends StatelessWidget {
  final String head;
  final String tail;

  const _Label(this.head, [this.tail = '']);

  @override
  Widget build(BuildContext context) {
    final base = PrivilegeCardFace.onCard(11.5, FontWeight.w400);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: head,
            style: base.copyWith(fontWeight: FontWeight.w800),
          ),
          if (tail.isNotEmpty) TextSpan(text: tail, style: base),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Concentric rings, laid out the way the reference SVG lays them out: a
/// 1600×800 field scaled to the card's width and centred, with the rings
/// growing from a point up in the top-left corner.
class _RingsPainter extends CustomPainter {
  final List<Color> rings;

  const _RingsPainter(this.rings);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 1600;
    // The field is twice as wide as it is tall; a card is not, so it is
    // centred vertically and the rings run off the top and bottom.
    final dy = (size.height - 800 * scale) / 2;
    final centre = Offset(17 * scale, 263.4 * scale + dy);

    canvas.drawRect(Offset.zero & size, Paint()..color = rings.first);

    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 66.7 * scale
      ..color = const Color(0x0D000000);

    for (var index = 0; index < rings.length; index++) {
      final radius = (1800 - index * 100) * scale;
      canvas.drawCircle(centre, radius, Paint()..color = rings[index]);
      canvas.drawCircle(centre, radius, seam);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.rings != rings;
}

/// The issuer's mark, in the white panel a card badge is printed on.
///
/// The logo is blue and green; the rings behind it run from pale to nearly
/// black, and there is no tier where both halves of the mark would read
/// against them. The panel is what keeps it legible on all three.
class PrivilegeIssuerMark extends StatelessWidget {
  final double size;

  const PrivilegeIssuerMark({super.key, this.size = 27});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      padding: const EdgeInsets.all(1),
      child: Image.asset(
        'assets/logos/shield_mark.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// The contact plate, in the gold every card wears whatever its tier.
class PrivilegeCardChip extends StatelessWidget {
  const PrivilegeCardChip({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _ChipPainter());
  }
}

class _ChipPainter extends CustomPainter {
  const _ChipPainter();

  static const Color gold = Color(0xFFD4AF37);
  static const Color groove = Color(0xFF8A6E1F);

  @override
  void paint(Canvas canvas, Size size) {
    final plate = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.18),
    );
    canvas.drawRRect(plate, Paint()..color = gold);

    final inner = Rect.fromLTWH(
      size.width * 0.27,
      size.height * 0.24,
      size.width * 0.46,
      size.height * 0.52,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.055).clamp(0.8, 2.0)
      ..color = groove;

    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, Radius.circular(size.width * 0.06)),
      line,
    );

    // The four leads running out of the contact area to the plate edge, which
    // is what makes a gold rectangle read as a chip.
    for (final y in [size.height * 0.38, size.height * 0.62]) {
      canvas.drawLine(Offset(0, y), Offset(inner.left, y), line);
      canvas.drawLine(Offset(inner.right, y), Offset(size.width, y), line);
    }
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, inner.top),
      line,
    );
    canvas.drawLine(
      Offset(size.width / 2, inner.bottom),
      Offset(size.width / 2, size.height),
      line,
    );
  }

  @override
  bool shouldRepaint(_ChipPainter old) => false;
}
