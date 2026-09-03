import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Unified image widget that renders a remote URL (`http`/`https`), a
/// `data:` URI (a base64 image, which is how the admin console stores product
/// photos in `app.product.image`), or a bundled asset path — with a loading
/// indicator for the network case and a graceful fallback to an icon whenever
/// the source is missing or fails to decode.
class AppImage extends StatelessWidget {
  final String? image;
  final IconData? fallbackIcon;
  final double? iconSize;
  final Color? iconColor;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;

  const AppImage({
    super.key,
    required this.image,
    this.fallbackIcon,
    this.iconSize,
    this.iconColor,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.width,
    this.height,
  });

  static bool isNetwork(String? path) {
    if (path == null) return false;
    final trimmed = path.trim().toLowerCase();
    return trimmed.startsWith('http://') || trimmed.startsWith('https://');
  }

  static bool isDataUri(String? path) =>
      path != null && path.trimLeft().startsWith('data:');

  /// Decoded `data:` URIs, keyed by the raw string. `base64Decode` on every
  /// rebuild would re-decode the bytes and defeat Flutter's image cache (a
  /// fresh `Uint8List` is a cache miss), and `AppImage` rebuilds often — it
  /// sits inside the cart's `ListenableBuilder` on every product card.
  static final Map<String, Uint8List> _dataUriCache = {};

  /// The bytes of a `data:[<mime>][;base64],<payload>` URI, or null when it is
  /// malformed / not base64.
  static Uint8List? _bytesFromDataUri(String uri) {
    final cached = _dataUriCache[uri];
    if (cached != null) return cached;

    final comma = uri.indexOf(',');
    if (comma < 0) return null;
    final meta = uri.substring(0, comma);
    final payload = uri.substring(comma + 1);
    try {
      final bytes = meta.contains(';base64')
          ? base64Decode(payload)
          : Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
      _dataUriCache[uri] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = image?.trim();
    if (imagePath == null || imagePath.isEmpty) {
      return _buildFallback();
    }

    if (isDataUri(imagePath)) {
      final bytes = _bytesFromDataUri(imagePath);
      if (bytes == null || bytes.isEmpty) {
        return _buildFallback();
      }
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildFallback(),
      );
    }

    if (isNetwork(imagePath)) {
      return Image.network(
        imagePath,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: (iconSize ?? 24) * 0.7,
              height: (iconSize ?? 24) * 0.7,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brandBlue,
              ),
            ),
          );
        },
        errorBuilder: (_, _, _) => _buildFallback(),
      );
    }

    return Image.asset(
      imagePath,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      errorBuilder: (_, _, _) => _buildFallback(),
    );
  }

  Widget _buildFallback() {
    if (fallbackIcon != null) {
      return Icon(
        fallbackIcon,
        size: iconSize,
        color: iconColor ?? AppColors.brandBlue,
      );
    }
    return const SizedBox.shrink();
  }
}
