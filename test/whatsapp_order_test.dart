import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/module/home/prescription_card.dart';
import 'package:shield/phone.dart';

void main() {
  group('WhatsApp.uriFor', () {
    test('a ten-digit Indian number gets the 91 country code', () {
      expect(WhatsApp.uriFor('8594000970').toString(), 'https://wa.me/918594000970');
    });

    test('a number already carrying its country code is left as it is', () {
      expect(WhatsApp.uriFor('+91 85940 00970').toString(), 'https://wa.me/918594000970');
    });
  });

  testWidgets('the WhatsApp chip opens a chat to the order desk, not the dialer', (tester) async {
    final chats = <Uri>[];
    final calls = <Uri>[];
    WhatsApp.opener = (uri) async {
      chats.add(uri);
      return true;
    };
    Dialer.opener = (uri) async {
      calls.add(uri);
      return true;
    };
    addTearDown(WhatsApp.resetForTest);
    addTearDown(Dialer.resetForTest);

    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: PrescriptionCard())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Message on WhatsApp to order'));
    await tester.pumpAndSettle();

    expect(chats, [Uri.parse('https://wa.me/918594000970')]);
    expect(calls, isEmpty);
  });
}
