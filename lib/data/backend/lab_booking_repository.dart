import 'package:flutter/foundation.dart';

import 'backend_http.dart';

/// One lab package to book, plus how many patients it's for. Carried as a
/// plain value so the call site does not have to hand the data layer a cart
/// type.
///
/// The bundled `LabPackage` catalog (`lib/module/labtest/lab_package.dart`)
/// has no backend id of its own — [saveLabBookings] resolves one by matching
/// [name] against the backend's real `app.lab_package` catalog (the same
/// slug derivation the old direct-Neon version used to *create* a package
/// row on the fly with; the backend requires an existing, admin-managed
/// package instead, so a booking for a package the console hasn't added yet
/// simply can't be filed — best-effort, same as every other write here).
@immutable
class LabBookingInput {
  final String name;
  final int unitPrice;
  final int patients;

  const LabBookingInput({
    required this.name,
    required this.unitPrice,
    required this.patients,
  });
}

/// Books lab tests through `backend/api`'s `POST /v1/member/lab-bookings` —
/// see `booking.service.ts`.
///
/// One package = one request, fanned across [LabBookingInput.patients]
/// generic entries (`Patient 1`, `Patient 2`, …) — the old cart only ever
/// collected a headcount, never which named patients a test was for, so a
/// placeholder name carries exactly as much information forward as the old
/// flow had. A "lab cart" of several different packages needs one request
/// per package; the backend has no batch endpoint.
///
/// Best-effort, the same contract as every repository here: an unconfigured
/// backend or the network down leaves the in-memory cart flow exactly as it
/// was — a booking must never fail because the backend is unreachable.
class LabBookingRepository {
  const LabBookingRepository._();

  static const LabBookingRepository instance = LabBookingRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  Future<void> saveLabBookings({
    required List<LabBookingInput> bookings,
    int? addressId,
  }) async {
    if (!BackendHttp.isConfigured || bookings.isEmpty) {
      return;
    }
    final packagesBySlug = await _fetchPackageIdsBySlug();
    for (final booking in bookings) {
      final packageId = packagesBySlug[_slug(booking.name)];
      if (packageId == null) {
        BackendHttp.log(
          'LabBookingRepository.saveLabBookings: no backend package for '
          '"${booking.name}" — skipped',
        );
        continue;
      }
      try {
        await BackendHttp.instance.request(
          'POST',
          '/v1/member/lab-bookings',
          body: {
            'labPackageId': packageId,
            'patients': [
              for (var i = 1; i <= booking.patients; i++) {'name': 'Patient $i'},
            ],
            if (addressId != null) 'addressId': addressId,
          },
        );
      } catch (error) {
        BackendHttp.log('LabBookingRepository.saveLabBookings failed', error: error);
      }
    }
  }

  Future<Map<String, int>> _fetchPackageIdsBySlug() async {
    try {
      final rows = await BackendHttp.instance.request(
        'GET',
        '/v1/public/care/lab-packages',
        auth: false,
      ) as List<dynamic>;
      return {
        for (final row in rows.cast<Map<String, dynamic>>())
          (row['slug'] ?? '').toString(): (row['id'] as num).toInt(),
      };
    } catch (error) {
      BackendHttp.log('LabBookingRepository: fetching lab packages failed', error: error);
      return const {};
    }
  }

  static String _slug(String name) {
    final lower = name.toLowerCase();
    final dashed = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return dashed.replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
