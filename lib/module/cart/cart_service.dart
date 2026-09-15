import 'package:flutter/foundation.dart';

/// One line in the cart.
class CartLine {
  final String name;
  final String pack;
  final double price;
  final double mrp;

  /// `Product.backendId` — the numeric id the backend's cart-line API keys
  /// on. Null for a line whose product couldn't be resolved to a real
  /// catalogue row (a stale/fixture add) — checkout treats that as
  /// unsyncable rather than guessing at an id.
  final int? productId;

  /// Artwork for the product, carried from wherever it was added so the cart
  /// shows the same picture the shelf did. Null for lines with no image —
  /// prescription medicines, or fixtures — which fall back to an icon.
  String? image;
  int qty;

  CartLine({
    required this.name,
    required this.pack,
    required this.price,
    double? mrp,
    this.productId,
    this.image,
    this.qty = 1,
  }) : mrp = mrp ?? price;

  double get lineTotal => price * qty;

  double get lineMrpTotal => mrp * qty;

  /// False for a line that came off a prescription: the pharmacist prices it
  /// once the medicines are confirmed, and a made-up ₹0.00 would read as free.
  bool get isPriced => price > 0;
}

/// The shopping cart, shared by the badge and the cart screen so the count on
/// the icon can never disagree with the contents.
class CartService extends ChangeNotifier {
  CartService._();

  static final CartService instance = CartService._();

  /// The most of any one item a cart line may hold. The typed field accepts up
  /// to this, and [setQty] / [changeQty] cap at it.
  static const int maxLineQty = 999;

  /// How far the quantity picker's shortcut list (radio rows / chips) runs.
  /// Past this a member types the number instead — a 999-row list would be
  /// unusable, and nobody scrolls to pick 400.
  static const int quickPickQty = 20;

  final List<CartLine> _lines = [];

  List<CartLine> get lines => List.unmodifiable(_lines);

  bool get isEmpty => _lines.isEmpty;

  /// Total units, not distinct products: two boxes of one item count as two.
  int get itemCount => _lines.fold(0, (sum, line) => sum + line.qty);

  double get subtotal => _lines.fold(0, (sum, line) => sum + line.lineTotal);

  double get mrpTotal => _lines.fold(0, (sum, line) => sum + line.lineMrpTotal);

  double get discount => (mrpTotal - subtotal).clamp(0, double.infinity);

  /// Delivery is free — always zero, regardless of cart contents.
  double get deliveryFee => 0;

  double get payable => subtotal + deliveryFee;

  int quantityFor(String name) {
    final index = _lines.indexWhere((line) => line.name == name);
    return index < 0 ? 0 : _lines[index].qty;
  }

  /// Adds [qty] units, merging into the existing line when the product is
  /// already in the cart rather than creating a duplicate row.
  ///
  /// [qty] is there for prescriptions, which arrive as a whole run at once —
  /// ninety tablets, not one tapped ninety times.
  void add({
    required String name,
    required String pack,
    required double price,
    double? mrp,
    int? productId,
    String? image,
    int qty = 1,
  }) {
    if (qty <= 0) {
      return;
    }
    final existing = _lines.indexWhere((line) => line.name == name);
    if (existing >= 0) {
      _lines[existing].qty += qty;
      // Fill in the picture if the line was first added without one.
      _lines[existing].image ??= image;
    } else {
      _lines.add(
        CartLine(
          name: name,
          pack: pack,
          price: price,
          mrp: mrp,
          productId: productId,
          image: image,
          qty: qty,
        ),
      );
    }
    notifyListeners();
  }

  /// Steps a line's quantity, removing the line when it reaches zero.
  void changeQty(int index, int delta) {
    if (index < 0 || index >= _lines.length) {
      return;
    }
    final next = _lines[index].qty + delta;
    if (next <= 0) {
      _lines.removeAt(index);
    } else {
      _lines[index].qty = next.clamp(1, maxLineQty);
    }
    notifyListeners();
  }

  /// Sets a line's exact quantity, removing it when [qty] is zero and capping
  /// at [maxLineQty].
  void setQty(String name, int qty) {
    final index = _lines.indexWhere((line) => line.name == name);
    if (index < 0) {
      return;
    }
    if (qty <= 0) {
      _lines.removeAt(index);
    } else {
      _lines[index].qty = qty.clamp(1, maxLineQty);
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  /// Test hook: empties the cart and seeds nothing.
  @visibleForTesting
  void reset() => clear();

  /// Fixture used so the cart is not empty on first open during development.
  void seedSampleLines() {
    if (_lines.isNotEmpty) {
      return;
    }
    _lines.addAll([
      CartLine(
        name: 'Dolo 650mg Tablet',
        pack: 'Strip of 15 tablets',
        price: 32.5,
        qty: 2,
      ),
      CartLine(
        name: 'Shelcal 500 Calcium',
        pack: 'Strip of 15 tablets',
        price: 118,
      ),
    ]);
    notifyListeners();
  }
}
