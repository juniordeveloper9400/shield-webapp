import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/module/auth/login_screen.dart';
import 'package:shield/module/auth/auth_service.dart';
import 'package:shield/widgets/legal_links.dart';

class _RecordingOpener {
  Uri? opened;

  Future<bool> call(Uri uri) async {
    opened = uri;
    return true;
  }
}

/// Finds the recognizer attached to the [TextSpan] whose own text is
/// [substring], inside the sign-in screen's own terms note — the *one*
/// [RichText] whose full plain text names both links, not any of the many
/// other [RichText]s a plain [Text] elsewhere on the screen builds down to
/// internally. Tapping inline styled text has no coordinate-based
/// widget-test helper, so invoking the recognizer directly is how this is
/// actually exercised — the same wiring a real tap on that span triggers.
GestureTapCallback _recognizerFor(WidgetTester tester, String substring) {
  final finder = find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText().contains('Terms of Use') && w.text.toPlainText().contains('Privacy Policy'),
  );
  final richText = tester.widget<RichText>(finder);
  InlineSpan? match;
  richText.text.visitChildren((span) {
    if (span is TextSpan && span.text == substring) {
      match = span;
      return false;
    }
    return true;
  });
  final span = match as TextSpan?;
  final recognizer = span?.recognizer;
  expect(recognizer, isA<TapGestureRecognizer>(), reason: 'no "$substring" span found');
  return (recognizer as TapGestureRecognizer).onTap!;
}

void main() {
  setUp(() => AuthService.instance.reset());
  tearDown(() => AuthService.instance.reset());

  testWidgets(
    'the sign-in screen\'s "Terms of Use" and "Privacy Policy" are real, tappable links',
    (tester) async {
      final originalTerms = termsOpener;
      final originalPrivacy = privacyPolicyOpener;
      final termsRecorder = _RecordingOpener();
      final privacyRecorder = _RecordingOpener();
      termsOpener = termsRecorder.call;
      privacyPolicyOpener = privacyRecorder.call;
      addTearDown(() {
        termsOpener = originalTerms;
        privacyPolicyOpener = originalPrivacy;
      });

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();

      _recognizerFor(tester, 'Terms of Use')();
      await tester.pumpAndSettle();
      expect(termsRecorder.opened, Uri.parse(termsUrl));
      expect(privacyRecorder.opened, isNull);

      _recognizerFor(tester, 'Privacy Policy')();
      await tester.pumpAndSettle();
      expect(privacyRecorder.opened, Uri.parse(privacyPolicyUrl));
    },
  );
}
