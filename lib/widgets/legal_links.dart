import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// The two legal pages every screen that names them actually has to open —
/// plain static files (`web/privacy.html`, `web/terms.html`, served as-is by
/// Vercel, no sign-in and no Flutter runtime involved) on this app's own
/// deployed domain, not a separate Vercel project that can drift or
/// disappear out from under the link.
///
/// Shared between the Account menu (`AccountScreen`) and the sign-in
/// screen's own "Terms of Use and Privacy Policy" note (`LoginScreen`) —
/// one seam each rather than two copies that could quietly point at
/// different URLs.
const String privacyPolicyUrl = 'https://shieldappweb.vercel.app/privacy.html';
const String termsUrl = 'https://shieldappweb.vercel.app/terms.html';

/// Swappable in a test — a widget test cannot actually launch a browser, so
/// this is what a test replaces to record what would have opened instead.
@visibleForTesting
Future<bool> Function(Uri uri) privacyPolicyOpener =
    (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

@visibleForTesting
Future<bool> Function(Uri uri) termsOpener =
    (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Opens the Privacy Policy, best-effort — returns whether it actually
/// opened, so a caller can tell the member when it didn't rather than
/// staying silent about a dead link.
Future<bool> openPrivacyPolicy() async {
  try {
    return await privacyPolicyOpener(Uri.parse(privacyPolicyUrl));
  } catch (_) {
    return false;
  }
}

/// Opens the Terms & Conditions — see [openPrivacyPolicy]'s own doc.
Future<bool> openTerms() async {
  try {
    return await termsOpener(Uri.parse(termsUrl));
  } catch (_) {
    return false;
  }
}
