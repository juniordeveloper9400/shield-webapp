import 'package:flutter/foundation.dart';

/// A branch open for lab collection right now — one row of
/// `GET /v1/public/care/lab-stores` (`CareRepository.fetchLabStores`,
/// `BookingService.listLabStores` server-side).
///
/// Deliberately its own small model rather than reusing this app's own
/// [ShieldStore]/[StoreDirectory]: those are a static, bundled list that is
/// never refreshed from the backend (see `shield_store.dart`), so they can
/// neither reflect which branches have lab collection switched off nor pick
/// up a branch the admin console adds later. [LabCartScreen]'s "Branch" row
/// reads this list live instead, every time it opens the picker.
@immutable
class LabStore {
  /// `app.shield_store.id` — what `bookLabTest`'s `storeId` actually wants.
  final int id;
  final String code;
  final String name;
  final String area;
  final String city;
  final String pincode;

  const LabStore({
    required this.id,
    required this.code,
    required this.name,
    required this.area,
    required this.city,
    required this.pincode,
  });

  /// "Melattur, Malappuram · 679326"
  String get addressLine => '$area, $city · $pincode';
}
