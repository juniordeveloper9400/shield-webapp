import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shield/module/whatsapp/whatsapp_chooser.dart';
import 'package:shield/phone.dart';

void main() {
  late List<Uri> chats;

  setUp(() {
    chats = [];
    WhatsApp.opener = (uri) async {
      chats.add(uri);
      return true;
    };
  });
  tearDown(WhatsApp.resetForTest);

  Future<void> pumpWith(WidgetTester tester, List<WhatsAppOption> options) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => openWhatsAppChooser(context, title: 'Message on WhatsApp', options: options),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('two stores are listed with their names and numbers, and tapping one opens that chat', (tester) async {
    await pumpWith(tester, const [
      WhatsAppOption(name: 'Sahakar 360 Melattur', number: '919895357101'),
      WhatsAppOption(name: 'Sahakar 360 Makkaraparamba', number: '919400525063'),
    ]);

    expect(find.text('Sahakar 360 Melattur'), findsOneWidget);
    expect(find.text('919895357101'), findsOneWidget);
    expect(find.text('Sahakar 360 Makkaraparamba'), findsOneWidget);
    expect(find.text('919400525063'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('whatsapp-option-919400525063')));
    await tester.pumpAndSettle();

    expect(chats, [Uri.parse('https://wa.me/919400525063')]);
  });

  testWidgets('a single option opens its chat straight away, with no sheet', (tester) async {
    await pumpWith(tester, const [
      WhatsAppOption(name: 'Sahakar 360 Melattur', number: '919895357101'),
    ]);

    expect(chats, [Uri.parse('https://wa.me/919895357101')]);
    expect(find.text('Sahakar 360 Melattur'), findsNothing);
  });
}
