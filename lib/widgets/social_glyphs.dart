import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

/// The networks Sahakar 360 publishes on, each with the page it opens.
enum SocialNetwork {
  facebook('Facebook', 'https://www.facebook.com/share/1C8qHEAqDZ/'),
  youtube('YouTube', 'https://youtube.com/@sahakarmedicalsofficial'),
  instagram(
    'Instagram',
    'https://www.instagram.com/sahakar_medicals_official',
  );

  final String label;

  /// The public profile this disc opens, in the browser or the network's app.
  final String url;

  const SocialNetwork(this.label, this.url);
}

/// Opens a [SocialNetwork]'s page in the browser or its app.
///
/// Behind a seam, the same way [Dialer] is, so a widget test can watch which
/// page a disc would open without a browser to hand it to. Reset with
/// [resetForTest] afterwards.
class SocialLinks {
  const SocialLinks._();

  @visibleForTesting
  static Future<bool> Function(Uri uri) opener =
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  @visibleForTesting
  static void resetForTest() => opener =
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  /// Opens [network]'s profile. A failure says so rather than doing nothing —
  /// on a device with no browser a silent no-op looks like a dead button.
  static Future<void> open(BuildContext context, SocialNetwork network) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await opener(Uri.parse(network.url));
    } catch (_) {
      opened = false;
    }
    if (opened) {
      return;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Could not open ${network.label}.'),
          backgroundColor: AppColors.textDark,
        ),
      );
  }
}

/// A brand glyph in white on a solid brand-blue disc.
///
/// The marks are drawn as paths rather than borrowed from the Material set,
/// which carries no YouTube or Instagram glyph — the nearest stand-ins are a
/// play button and a camera, and a camera does not read as Instagram. Paths
/// also keep the three optically consistent: one grid, one stroke weight.
class SocialIcon extends StatelessWidget {
  final SocialNetwork network;
  final VoidCallback? onTap;

  /// Diameter of the disc.
  final double size;

  const SocialIcon({
    super.key,
    required this.network,
    this.onTap,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: network.label,
      child: Material(
        color: AppColors.brandBlue,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: CustomPaint(
                size: Size.square(size * 0.55),
                painter: _SocialGlyphPainter(network),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints one mark, white, on a 24x24 grid scaled to the given size.
class _SocialGlyphPainter extends CustomPainter {
  final SocialNetwork network;

  const _SocialGlyphPainter(this.network);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale);

    final paint = Paint()
      ..color = AppColors.white
      ..isAntiAlias = true;

    canvas.drawPath(switch (network) {
      SocialNetwork.facebook => _facebook(),
      SocialNetwork.youtube => _youtube(),
      SocialNetwork.instagram => _instagram(),
    }, paint);

    canvas.restore();
  }

  /// The lowercase f: a stem, the crossbar through it, and the shoulder that
  /// squares off the top left.
  Path _facebook() {
    return Path()
      ..moveTo(15.6, 4.2)
      ..lineTo(13.1, 4.2)
      // The shoulder: the stem is set on a block that rises from the crossbar.
      ..cubicTo(10.2, 4.2, 8.7, 5.9, 8.7, 8.7)
      ..lineTo(8.7, 11.0)
      ..lineTo(6.0, 11.0)
      ..lineTo(6.0, 14.4)
      ..lineTo(8.7, 14.4)
      ..lineTo(8.7, 22.0)
      ..lineTo(12.4, 22.0)
      ..lineTo(12.4, 14.4)
      ..lineTo(15.4, 14.4)
      ..lineTo(15.9, 11.0)
      ..lineTo(12.4, 11.0)
      ..lineTo(12.4, 9.2)
      // The bar tucks back under the stem rather than meeting it square.
      ..cubicTo(12.4, 7.9, 12.9, 7.4, 14.3, 7.4)
      ..lineTo(15.6, 7.4)
      ..close();
  }

  /// The rounded screen with the play triangle knocked out of it, so the disc
  /// behind shows through the triangle exactly as the real mark does.
  Path _youtube() {
    final screen = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(1.6, 4.8, 22.4, 19.2),
          const Radius.circular(4.6),
        ),
      );
    final play = Path()
      ..moveTo(9.9, 8.5)
      ..lineTo(16.4, 12.0)
      ..lineTo(9.9, 15.5)
      ..close();

    return Path.combine(PathOperation.difference, screen, play);
  }

  /// The rounded square, the lens inside it, and the dot at the top right —
  /// all outlines, so each is a shape minus the shape inside it.
  Path _instagram() {
    const stroke = 2.1;

    final outer = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(2.4, 2.4, 21.6, 21.6),
          const Radius.circular(6.2),
        ),
      );
    final inner = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(
            2.4 + stroke,
            2.4 + stroke,
            21.6 - stroke,
            21.6 - stroke,
          ),
          const Radius.circular(6.2 - stroke),
        ),
      );
    var glyph = Path.combine(PathOperation.difference, outer, inner);

    final lens = Path()
      ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 4.9));
    final lensHole = Path()
      ..addOval(
        Rect.fromCircle(center: const Offset(12, 12), radius: 4.9 - stroke),
      );
    glyph = Path.combine(
      PathOperation.union,
      glyph,
      Path.combine(PathOperation.difference, lens, lensHole),
    );

    final dot = Path()
      ..addOval(Rect.fromCircle(center: const Offset(17.2, 6.8), radius: 1.35));
    return Path.combine(PathOperation.union, glyph, dot);
  }

  @override
  bool shouldRepaint(covariant _SocialGlyphPainter oldDelegate) =>
      oldDelegate.network != network;
}
