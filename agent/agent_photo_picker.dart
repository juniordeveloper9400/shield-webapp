import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Opens the camera or the gallery for an agent's profile photo, and returns
/// the picture as bytes ready to draw.
///
/// A class rather than a bare call so it can be stood in for — there is no
/// camera or gallery inside a widget test. Unlike [ReceiptPicker] this
/// returns the actual image bytes rather than a name and a size: a receipt is
/// only ever referenced by its filename, but a profile photo has to be drawn
/// on screen, so a size alone would not do.
class AgentPhotoPicker {
  const AgentPhotoPicker();

  /// Replaces the real picker for the length of a test. Null in production,
  /// and nothing but a test may set it.
  @visibleForTesting
  static Future<Uint8List?> Function(ImageSource source)? debugOverride;

  Future<Uint8List?> pick(ImageSource source) async {
    final override = debugOverride;
    if (override != null) {
      return override(source);
    }
    // Capped well below a camera's native resolution — this is an avatar,
    // not a document, and nothing here has to survive being zoomed into.
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) {
      return null;
    }
    return picked.readAsBytes();
  }
}
