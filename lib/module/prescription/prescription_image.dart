import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Shrinks a picked prescription photo to a small JPEG `data:` URI — the form
/// it is stored in (`app.prescription.image`) and rendered from in the
/// pharmacy console.
///
/// A script only has to be *readable* at the counter, not archival, so it is
/// capped at [maxEdge] px on its long side and re-encoded at [quality]. A phone
/// photo that lands at 3-5 MB comes down to roughly 100-250 KB — small enough
/// to sit in a text column and travel over Neon's HTTP endpoint.
///
/// Returns null when the bytes are not a decodable image. Runs the decode /
/// resize / encode on a background isolate so a large photo does not jank the
/// upload screen.
Future<String?> prescriptionImageDataUrl(
  Uint8List bytes, {
  int maxEdge = 1200,
  int quality = 62,
}) {
  return compute(
    _encode,
    _EncodeRequest(bytes: bytes, maxEdge: maxEdge, quality: quality),
  );
}

class _EncodeRequest {
  final Uint8List bytes;
  final int maxEdge;
  final int quality;

  const _EncodeRequest({
    required this.bytes,
    required this.maxEdge,
    required this.quality,
  });
}

String? _encode(_EncodeRequest req) {
  final decoded = img.decodeImage(req.bytes);
  if (decoded == null) {
    return null;
  }
  final longest =
      decoded.width >= decoded.height ? decoded.width : decoded.height;
  final img.Image resized = longest > req.maxEdge
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? req.maxEdge : null,
          height: decoded.height > decoded.width ? req.maxEdge : null,
        )
      : decoded;
  final jpg = img.encodeJpg(resized, quality: req.quality);
  return 'data:image/jpeg;base64,${base64Encode(jpg)}';
}
