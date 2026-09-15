import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_image.dart';

/// A full-screen, pinch-zoomable look at one stored image — a `data:` URI or
/// a network URL, anything [AppImage] already knows how to decode.
///
/// Where the small print on a receipt or an invoice actually becomes
/// readable; the card that opens this only ever shows a thumbnail. Ported
/// from the root SHIELD app's own `lib/widgets/full_screen_image_view.dart`
/// verbatim, for [StoreInvoiceCard] to reuse here the same way.
class FullScreenImageView extends StatelessWidget {
  final String image;

  /// Shown in the app bar, so a member looking at more than one of these in
  /// a row knows which one is open.
  final String title;

  const FullScreenImageView({
    super.key,
    required this.image,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.black,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: AppImage(
            image: image,
            fit: BoxFit.contain,
            fallbackIcon: Icons.broken_image_outlined,
            iconSize: 48,
            iconColor: AppColors.white,
          ),
        ),
      ),
    );
  }
}
