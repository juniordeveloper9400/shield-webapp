import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme/app_colors.dart';

/// Opens the platform dialer on a number.
class Dialer {
  const Dialer._();

  /// The launch itself, behind a seam so tests can watch it without a dialer
  /// to open. Reset with [resetForTest] afterwards.
  @visibleForTesting
  static Future<bool> Function(Uri uri) opener = launchUrl;

  @visibleForTesting
  static void resetForTest() => opener = launchUrl;

  /// `tel:` with everything but digits and a leading plus stripped, so a
  /// number written for people — spaces, dashes, brackets — still dials.
  static Uri uriFor(String number) {
    final cleaned = number.replaceAll(RegExp(r'[^0-9+]'), '');
    return Uri(scheme: 'tel', path: cleaned);
  }

  /// Opens the dialer with [number] filled in, ready to place.
  ///
  /// The dialer, not the call: placing one outright needs the CALL_PHONE
  /// permission, and an order line is not worth asking a member for that.
  /// A failure says so rather than doing nothing — on a tablet with no dialer
  /// installed, a silent no-op looks like a broken button.
  static Future<void> call(BuildContext context, String number) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await opener(uriFor(number));
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
          content: Text('Could not open the dialer. Call $number to order.'),
          backgroundColor: AppColors.textDark,
        ),
      );
  }
}

/// Opens a WhatsApp chat with a number, so a member can message the order desk
/// the way they would call it.
///
/// Behind the same kind of seam [Dialer] uses, so a test can see which chat
/// would open without WhatsApp installed. Reset with [resetForTest] afterwards.
class WhatsApp {
  const WhatsApp._();

  @visibleForTesting
  static Future<bool> Function(Uri uri) opener =
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  @visibleForTesting
  static void resetForTest() => opener =
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  /// `https://wa.me/<digits>` — wa.me wants the full international number with
  /// nothing but digits. A ten-digit Indian number written without its country
  /// code gets `91` in front.
  static Uri uriFor(String number) {
    var digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) {
      digits = '91$digits';
    }
    return Uri.parse('https://wa.me/$digits');
  }

  /// Opens the chat. A failure says so rather than doing nothing.
  static Future<void> open(BuildContext context, String number) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await opener(uriFor(number));
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
          content: Text('Could not open WhatsApp. Message $number to order.'),
          backgroundColor: AppColors.textDark,
        ),
      );
  }
}
