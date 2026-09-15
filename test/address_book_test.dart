// Coverage for AddressBook.hydrateFromBackend — the fix for "a saved address
// disappears on refresh": until now AddressBook was documented as "in memory
// only," so a page reload (web) or a restart lost every address the member
// had actually saved on the backend. hydrateFromBackend is what pulls those
// back in — see AddressRepository.fetchAll's doc for the read side.
import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/location/address_book.dart';

Address _address({String house = 'Flat 4B', String? patientId}) => Address(
  pincode: '682001',
  house: house,
  area: 'Kadavanthra',
  firstName: 'Rahul',
  phone: '9000000002',
  label: AddressLabel.home,
  patientId: patientId,
);

void main() {
  group('AddressBook.hydrateFromBackend', () {
    setUp(() => AddressBook.instance.reset());

    test('adds remote addresses and sets deliverTo to the newest when none was chosen', () {
      final book = AddressBook.instance;
      expect(book.deliverTo, isNull);

      final first = _address(house: 'Flat 4B');
      final second = _address(house: 'Villa 12');
      book.hydrateFromBackend([first, second]);

      expect(book.addresses, hasLength(2));
      // fetchAll's own doc: oldest first — the newest (last) becomes the
      // default delivery target when nothing local had already picked one.
      expect(book.deliverTo?.house, 'Villa 12');
    });

    test('does not duplicate an address already known locally', () {
      final book = AddressBook.instance;
      final saved = _address(house: 'Flat 4B');
      book.add(saved);
      expect(book.addresses, hasLength(1));

      // The same address as it would come back from the backend — a fresh
      // instance, but identical fields.
      book.hydrateFromBackend([_address(house: 'Flat 4B')]);
      expect(book.addresses, hasLength(1));
    });

    test('leaves an explicitly-chosen deliverTo alone', () {
      final book = AddressBook.instance;
      final chosen = _address(house: 'Flat 4B');
      book.add(chosen);

      book.hydrateFromBackend([_address(house: 'Villa 12')]);
      expect(book.deliverTo?.house, 'Flat 4B');
      expect(book.addresses, hasLength(2));
    });

    test('a no-op on an empty remote list', () {
      final book = AddressBook.instance;
      book.add(_address());
      book.hydrateFromBackend(const []);
      expect(book.addresses, hasLength(1));
    });
  });

  group('AddressBook.reset', () {
    test('drops every saved address and the delivery target', () {
      final book = AddressBook.instance;
      book.add(_address());
      expect(book.isEmpty, isFalse);

      book.reset();
      expect(book.isEmpty, isTrue);
      expect(book.deliverTo, isNull);
    });
  });
}
