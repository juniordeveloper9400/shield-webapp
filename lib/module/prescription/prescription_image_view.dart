import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';

/// A full-screen look at a prescription image, either [bytes] just picked and
/// not yet filed, or [dataUri] read back from a record already on file
/// ([PrescriptionRecord.image]) — exactly one of the two is given.
///
/// The upload card can show a name and a size and a thumbnail, but none of
/// those answer "is this page readable" — so the card opens this, where the
/// picture fills the screen and pinch-zoom brings the small print up close.
class PrescriptionImageView extends StatelessWidget {
  final Uint8List? bytes;
  final String? dataUri;

  /// The file's name, shown in the bar so the member knows which upload they
  /// are looking at when more than one has been added.
  final String name;

  const PrescriptionImageView({
    super.key,
    this.bytes,
    this.dataUri,
    required this.name,
  }) : assert(
         (bytes == null) != (dataUri == null),
         'Provide exactly one of bytes or dataUri',
       );

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
          name,
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
          child: bytes != null
              ? Image.memory(
                  bytes!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const _UnreadableImage(),
                )
              : AppImage(
                  image: dataUri,
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

class _UnreadableImage extends StatelessWidget {
  const _UnreadableImage();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'This image could not be shown.',
        style: TextStyle(color: AppColors.white, fontSize: 14),
      ),
    );
  }
}
