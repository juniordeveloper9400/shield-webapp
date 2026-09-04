import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// How a request for the device's location ended.
enum DeviceLocationOutcome {
  /// Got a fix — [DeviceLocationResult.place] is set.
  ok,

  /// The member said no this time — asking again may still work.
  denied,

  /// The member picked "don't ask again" — only Settings turns it back on.
  deniedForever,

  /// Location services are switched off on the device.
  serviceOff,

  /// Timed out, or the platform / network threw.
  failed,
}

/// A device fix turned into the fields an address form needs. Everything but
/// [latitude] / [longitude] can be blank when the reverse lookup could not
/// name the spot — the coordinates are still good, so the member types the
/// rest.
@immutable
class ResolvedPlace {
  final double latitude;
  final double longitude;
  final String pincode;
  final String area;
  final String city;
  final String state;
  final String road;

  const ResolvedPlace({
    required this.latitude,
    required this.longitude,
    this.pincode = '',
    this.area = '',
    this.city = '',
    this.state = '',
    this.road = '',
  });

  bool get hasPincode => pincode.length == 6 && int.tryParse(pincode) != null;

  /// "MG Road, Andheri East" — the address line to drop into "Area / Locality".
  String get areaLine =>
      [road, area].where((p) => p.isNotEmpty).join(', ');
}

class DeviceLocationResult {
  final DeviceLocationOutcome outcome;
  final ResolvedPlace? place;

  const DeviceLocationResult(this.outcome, [this.place]);

  bool get ok => outcome == DeviceLocationOutcome.ok && place != null;
}

/// Reads the device's current position and reverse-geocodes it to a pincode
/// and locality, for the "Use current location" / "Current Location" actions
/// on the location sheet and the address form.
///
/// Reverse geocoding is OpenStreetMap's Nominatim — no key, no billing, the
/// same source as the branch-picker map tiles. On the web build the position
/// comes from the browser's geolocation prompt; everything else is identical.
class DeviceLocation {
  const DeviceLocation._();

  static const _reverseUrl = 'https://nominatim.openstreetmap.org/reverse';

  /// One call: check services, ask permission, get a fix, name it. Never throws.
  static Future<DeviceLocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const DeviceLocationResult(DeviceLocationOutcome.serviceOff);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const DeviceLocationResult(DeviceLocationOutcome.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        return const DeviceLocationResult(DeviceLocationOutcome.denied);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final place = await _reverseGeocode(position.latitude, position.longitude);
      return DeviceLocationResult(DeviceLocationOutcome.ok, place);
    } catch (error) {
      debugPrint('DeviceLocation: could not get a fix — $error');
      return const DeviceLocationResult(DeviceLocationOutcome.failed);
    }
  }

  static Future<ResolvedPlace> _reverseGeocode(double lat, double lng) async {
    final fallback = ResolvedPlace(latitude: lat, longitude: lng);
    try {
      final uri = Uri.parse(
        '$_reverseUrl?format=jsonv2&addressdetails=1&zoom=18'
        '&lat=$lat&lon=$lng',
      );
      final response = await http.get(
        uri,
        // Nominatim wants a real identifier; the browser sets its own on web
        // and drops this one, which Nominatim accepts for a web origin.
        headers: const {'User-Agent': 'SHIELD-App/1.0 (com.zabnix.shield)'},
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return fallback;
      }
      final body = jsonDecode(response.body);
      final address = body is Map ? body['address'] : null;
      if (address is! Map) {
        return fallback;
      }

      String pick(List<String> keys) {
        for (final key in keys) {
          final value = address[key];
          if (value is String && value.trim().isNotEmpty) {
            return value.trim();
          }
        }
        return '';
      }

      return ResolvedPlace(
        latitude: lat,
        longitude: lng,
        pincode: pick(['postcode']).replaceAll(RegExp(r'\s+'), ''),
        area: pick([
          'suburb',
          'neighbourhood',
          'village',
          'town',
          'city_district',
          'hamlet',
          'quarter',
        ]),
        city: pick(['city', 'town', 'municipality', 'state_district']),
        state: pick(['state']),
        road: pick(['road', 'pedestrian', 'footway']),
      );
    } catch (error) {
      debugPrint('DeviceLocation: reverse geocode failed — $error');
      return fallback;
    }
  }

  /// A one-line reason for the SnackBar when [current] did not return `ok`.
  static String message(DeviceLocationOutcome outcome) {
    switch (outcome) {
      case DeviceLocationOutcome.ok:
        return '';
      case DeviceLocationOutcome.denied:
        return 'Location permission was declined. Allow it to use your '
            'current location.';
      case DeviceLocationOutcome.deniedForever:
        return 'Location is blocked for this app. Turn it on in Settings, '
            'then try again.';
      case DeviceLocationOutcome.serviceOff:
        return 'Location is switched off on this device. Turn it on, then '
            'try again.';
      case DeviceLocationOutcome.failed:
        return 'Could not get your location. Check your connection and try '
            'again.';
    }
  }
}
