import '../../dates.dart';
import '../../money.dart';

/// Reads a money value — a `numeric(12,2)` the database sent back as text
/// ("70.00"), or a number — into whole paise, so an invoice adds up exactly
/// instead of drifting by a fraction of a rupee the way doubles do.
int paiseFrom(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().trim() ?? '');
  return parsed == null ? 0 : (parsed * 100).round();
}

/// `₹1,234.50` — paise as rupees with both decimals, the way an invoice prints
/// money (the rest of the app rounds to whole rupees, which an invoice must not).
String formatPaise(int paise) {
  final sign = paise < 0 ? '-' : '';
  final abs = paise.abs();
  final rupees = formatRupees(abs ~/ 100);
  final cents = (abs % 100).toString().padLeft(2, '0');
  return '$sign₹$rupees.$cents';
}

/// One printed row of an invoice.
class InvoiceLine {
  final String name;

  /// The pack size ("Strip of 10"), or empty.
  final String pack;

  final int qty;

  /// Price of one, in paise.
  final int unitPaise;

  const InvoiceLine({
    required this.name,
    this.pack = '',
    required this.qty,
    required this.unitPaise,
  });

  int get amountPaise => unitPaise * qty;
}

/// A store's invoice for one order — what the "Invoice" section of the bill
/// screen prints: who sold it, who it is for, every item with its price, and
/// how the total is made up.
///
/// Built the same way as the admin console's own invoice
/// (`shieldweb/src/lib/invoice.ts buildInvoice`), so the member sees exactly
/// the figures the store issued: the saved bill total is authoritative, and a
/// delivery fee is only listed when it really reconciles to that total.
class BillInvoice {
  /// The order code, which is also the invoice number.
  final String number;

  /// When the store sent the bill (the invoice date); null if unknown.
  final DateTime? billedAt;

  /// When the order was placed.
  final DateTime? placedAt;

  final String customerName;
  final String customerPhone;

  final String storeName;

  /// `Area, City, State, Pincode`, or empty when the order has no store.
  final String storeAddress;
  final String storePhone;

  /// `Home delivery` or `Store pickup`.
  final String fulfillment;

  /// Where a home delivery goes; empty for a pickup or an unknown address.
  final String deliveryAddress;

  /// `Completed`, `Cancelled` or `In progress` — same wording as the console.
  final String orderStatus;

  final bool paid;
  final DateTime? paidAt;

  final List<InvoiceLine> lines;

  final int subtotalPaise;

  /// Only non-zero when it reconciles to [totalPaise] (see the class doc).
  final int deliveryFeePaise;

  /// What is left between the items and the saved total — a discount or an
  /// extra the counter typed in when it priced the bill. Negative for a
  /// discount.
  final int adjustmentPaise;

  final int totalPaise;

  const BillInvoice({
    required this.number,
    this.billedAt,
    this.placedAt,
    this.customerName = '',
    this.customerPhone = '',
    this.storeName = 'SHIELD Pharmacy',
    this.storeAddress = '',
    this.storePhone = '',
    this.fulfillment = 'Home delivery',
    this.deliveryAddress = '',
    this.orderStatus = 'In progress',
    this.paid = false,
    this.paidAt,
    this.lines = const [],
    required this.subtotalPaise,
    this.deliveryFeePaise = 0,
    this.adjustmentPaise = 0,
    required this.totalPaise,
  });

  /// Works the totals out from [lines] and the figures the order and bill
  /// already carry.
  ///
  /// [billPaise] is the saved bill amount (the authority when it is above
  /// zero); [paidTotalPaise] what the order was paid; [deliveryFeePaise] the
  /// order's own delivery fee.
  factory BillInvoice.compose({
    required String number,
    DateTime? billedAt,
    DateTime? placedAt,
    String customerName = '',
    String customerPhone = '',
    String storeName = '',
    String storeAddress = '',
    String storePhone = '',
    bool homeDelivery = true,
    String deliveryAddress = '',
    String orderStatus = 'In progress',
    bool paid = false,
    DateTime? paidAt,
    List<InvoiceLine> lines = const [],
    int billPaise = 0,
    int paidTotalPaise = 0,
    int deliveryFeePaise = 0,
  }) {
    final subtotal = lines.fold<int>(0, (sum, line) => sum + line.amountPaise);
    final total = billPaise > 0
        ? billPaise
        : (paidTotalPaise > 0 ? paidTotalPaise : subtotal + deliveryFeePaise);
    // A delivery fee is only listed when subtotal + fee is exactly the total;
    // the console's bill editor saves the whole payable amount, so most bills
    // carry it inside the total already and must not print it twice.
    final fee = deliveryFeePaise > 0 && subtotal + deliveryFeePaise == total
        ? deliveryFeePaise
        : 0;
    return BillInvoice(
      number: number,
      billedAt: billedAt,
      placedAt: placedAt,
      customerName: customerName,
      customerPhone: customerPhone,
      storeName: storeName.trim().isEmpty ? 'SHIELD Pharmacy' : storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      fulfillment: homeDelivery ? 'Home delivery' : 'Store pickup',
      deliveryAddress: homeDelivery ? deliveryAddress : '',
      orderStatus: orderStatus,
      paid: paid,
      paidAt: paidAt,
      lines: lines,
      subtotalPaise: subtotal,
      deliveryFeePaise: fee,
      adjustmentPaise: total - subtotal - fee,
      totalPaise: total,
    );
  }

  /// This invoice with its payment marked settled — for a bill the member has
  /// just paid, before the next read from the database catches up.
  BillInvoice markPaid([DateTime? at]) => BillInvoice(
    number: number,
    billedAt: billedAt,
    placedAt: placedAt,
    customerName: customerName,
    customerPhone: customerPhone,
    storeName: storeName,
    storeAddress: storeAddress,
    storePhone: storePhone,
    fulfillment: fulfillment,
    deliveryAddress: deliveryAddress,
    orderStatus: orderStatus,
    paid: true,
    paidAt: at ?? paidAt ?? DateTime.now(),
    lines: lines,
    subtotalPaise: subtotalPaise,
    deliveryFeePaise: deliveryFeePaise,
    adjustmentPaise: adjustmentPaise,
    totalPaise: totalPaise,
  );

  /// The date printed on the invoice: when it was sent, else when the order
  /// was placed.
  DateTime? get date => billedAt ?? placedAt;

  /// Whether the store recorded the items — a bill that was only a picture has
  /// none, and the invoice then says so rather than printing an empty table.
  bool get hasItems => lines.isNotEmpty;

  /// The invoice as plain text, for sharing.
  String toShareText() {
    final out = StringBuffer()
      ..writeln('SHIELD Pharmacy — Invoice $number')
      ..writeln(storeName);
    if (storeAddress.isNotEmpty) out.writeln(storeAddress);
    if (date != null) out.writeln('Date: ${formatDateTime12h(date!)}');
    out.writeln('Billed to: $customerName');
    out.writeln();
    for (final line in lines) {
      final pack = line.pack.isEmpty ? '' : ' (${line.pack})';
      out.writeln(
        '${line.name}$pack  ${line.qty} × ${formatPaise(line.unitPaise)}'
        ' = ${formatPaise(line.amountPaise)}',
      );
    }
    if (hasItems) {
      out
        ..writeln()
        ..writeln('Subtotal: ${formatPaise(subtotalPaise)}');
      if (deliveryFeePaise != 0) {
        out.writeln('Delivery fee: ${formatPaise(deliveryFeePaise)}');
      }
      if (adjustmentPaise != 0) {
        out.writeln('Bill adjustment: ${formatPaise(adjustmentPaise)}');
      }
    }
    out
      ..writeln('Total: ${formatPaise(totalPaise)}')
      ..writeln('Payment: ${paid ? 'Paid' : 'Pending'}');
    return out.toString().trimRight();
  }
}
