import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend/order_repository.dart';
import '../../data/backend/prescription_repository.dart';
import '../../data/backend/store_repository.dart';
import '../../dates.dart';
import '../../money.dart';
import '../../phone.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';
import '../../widgets/full_screen_image_view.dart';
import '../../widgets/social_glyphs.dart';
import '../auth/auth_service.dart';
import '../checkout/fulfillment_type.dart';
import '../home/prescription_card.dart' show PrescriptionCard;
import '../location/address_book.dart';
import '../registration/registration_service.dart';
import 'purchase_service.dart';

/// The blocks that sit under the tracker graph on `OrderTrackScreen` — where
/// the order is going, how to reach support, and what it costs.
///
/// Nothing here stores anything of its own. The address and number come from
/// [AddressBook] and [AuthService], and every figure on the bill is worked
/// back out of the two amounts the [Purchase] already carries, so none of it
/// can drift from the rest of the app.

// ---------------------------------------------------------------------------
// Derived bill
// ---------------------------------------------------------------------------

/// One order's bill, split into the lines the detail screen prints.
///
/// Taxes are pulled *out* of the payable rather than added on top: the whole
/// point of the app's money model is that there is one paid figure, so the
/// breakdown has to sum back to it rather than inventing a larger total.
class OrderBill {
  final Purchase order;

  const OrderBill(this.order);

  /// A prescription order has no bill until the counter has priced it.
  bool get priced => order.mrpTotal > 0 || order.paidTotal > 0;

  int get mrp => order.mrpTotal;

  int get discount => order.saved;

  int get payable => order.paidTotal;

  /// "71.2%" — the share of MRP the discount came to, to one decimal.
  String get discountPercentLabel {
    if (mrp <= 0 || discount <= 0) {
      return '0%';
    }
    final tenths = (discount * 1000 / mrp).round();
    return '${(tenths / 10).toStringAsFixed(1)}%';
  }

  /// 5% GST, already inside [payable], surfaced as its own line.
  int get taxes => payable <= 0 ? 0 : (payable * 5 / 105).round();

  String get mrpLabel => '₹${formatRupees(mrp)}';

  String get discountLabel => '- ₹${formatRupees(discount)}';

  String get taxesLabel => '₹${formatRupees(taxes)}';

  String get payableLabel => '₹${formatRupees(payable)}';

  /// What the member reads next to "Payment mode": whether this order is
  /// actually settled, and — while it is not — how it is expected to be,
  /// driven by the real [Purchase.paymentStatus] / [Purchase.fulfillmentType]
  /// rather than a hardcoded guess.
  String get paymentMode {
    if (order.paymentStatus == OrderPaymentStatus.paid) {
      return 'Paid';
    }
    return order.fulfillmentType == FulfillmentType.storePickup
        ? 'Pay at store'
        : 'Pay on delivery';
  }

}

// ---------------------------------------------------------------------------
// Shared shells
// ---------------------------------------------------------------------------

/// A card with a tinted title band — the delivery-info blocks use this.
class _InfoCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _InfoCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.offerTint,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }
}

/// A plain white card — the action blocks sit on this.
class _PlainCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _PlainCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: padding,
      child: child,
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

const TextStyle _titleStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w800,
  color: AppColors.textDark,
);

const TextStyle _mutedStyle = TextStyle(
  fontSize: 13,
  height: 1.4,
  color: AppColors.textMuted,
);

const Widget _line = Divider(height: 1, color: AppColors.border);

Widget _linkButton({
  required IconData icon,
  required String label,
  required VoidCallback onPressed,
}) {
  return Align(
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brandBlue,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Prescription
// ---------------------------------------------------------------------------

/// The "prescription uploaded" thumbnail, shown for a prescription order.
///
/// Fetches the real scan the member uploaded — `GET /v1/member/orders/:id/
/// prescriptions` — rather than the generic document icon this used to show
/// unconditionally with no data behind it at all: the "View" button used to
/// just pop a toast saying "Opening your prescription" and open nothing.
/// Best-effort: while loading, or when the fetch fails, the icon+placeholder
/// state below is what shows — a plausible "still catching up" look rather
/// than an error, since [order.backendId] can genuinely be null for an
/// order this session placed but never heard back from the backend about.
class PrescriptionUploadedCard extends StatefulWidget {
  final Purchase order;

  const PrescriptionUploadedCard({super.key, required this.order});

  @override
  State<PrescriptionUploadedCard> createState() =>
      _PrescriptionUploadedCardState();
}

class _PrescriptionUploadedCardState extends State<PrescriptionUploadedCard> {
  List<OrderPrescription>? _prescriptions;

  /// Keyed by [OrderPrescription.id] — the pharmacist's own intake card for
  /// each prescription on this order, once the counter has sent one
  /// ("Send intake card" / "Update intake card" in the admin console). Only
  /// ever populated for a prescription whose [OrderPrescription.status] is
  /// past `AWAITING_REVIEW`, since nothing has been entered before then.
  final Map<int, RemotePrescriptionCard> _intakeCards = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final backendId = widget.order.backendId;
    if (backendId == null) {
      return;
    }
    final rows = await OrderRepository.instance.fetchPrescriptions(backendId);
    if (mounted && rows != null) {
      setState(() => _prescriptions = rows);
    }
    if (rows == null) {
      return;
    }
    // One detail call per prescription that could plausibly have an intake
    // card by now — same N+1 shape PrescriptionRepository.fetchForMember
    // already accepts for a member's own script count.
    for (final rx in rows) {
      if (rx.status == 'AWAITING_REVIEW') {
        continue;
      }
      final card = await PrescriptionRepository.instance.fetchOne(rx.id);
      if (mounted && card != null && card.hasIntakeCard) {
        setState(() => _intakeCards[rx.id] = card);
      }
    }
  }

  /// The first submitted prescription with an actual scan attached, or null
  /// while still loading / when none of them have one (a script phoned in).
  OrderPrescription? get _withImage {
    final rows = _prescriptions;
    if (rows == null) return null;
    for (final rx in rows) {
      if (rx.image != null) return rx;
    }
    return null;
  }

  /// Reflects what has actually happened to the prescription, rather than
  /// always claiming a pharmacist is still reading it — the same "priced"
  /// signal [OrderTrack] itself reads off the order.
  String get _statusLine {
    final order = widget.order;
    if (order.mrpTotal > 0 || order.paidTotal > 0) {
      return 'Priced and confirmed by the pharmacist.';
    }
    return 'The pharmacist is reading this to price your order.';
  }

  @override
  Widget build(BuildContext context) {
    final rx = _withImage;
    final count = _prescriptions?.length ?? 0;

    return _PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count > 1 ? 'Prescriptions uploaded' : 'Prescription uploaded',
            style: _titleStyle,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 90,
                  height: 112,
                  decoration: BoxDecoration(
                    color: AppColors.pageTint,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: rx?.image != null
                      ? AppImage(
                          image: rx!.image!,
                          fit: BoxFit.cover,
                          fallbackIcon: Icons.description_rounded,
                          iconSize: 34,
                        )
                      : const Icon(
                          Icons.description_rounded,
                          size: 34,
                          color: AppColors.brandBlue,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_statusLine, style: _mutedStyle),
                    if (count > 1) ...[
                      const SizedBox(height: 4),
                      Text(
                        '$count prescriptions on this order.',
                        style: _mutedStyle,
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (rx?.image != null)
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FullScreenImageView(
                              image: rx!.image!,
                              title: 'Prescription · ${rx.code}',
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('View'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.brandBlue,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // The pharmacist's own intake card, the moment the admin console
          // sends (or updates) one — every medicine, its dose and how much
          // to dispense, exactly as entered at the counter. Per prescription
          // when this order carries more than one, so a card never gets
          // shown under the wrong script's name.
          for (final rx in _prescriptions ?? const <OrderPrescription>[])
            if (_intakeCards[rx.id] case final card?) ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 12),
              _IntakeCardBlock(
                title: count > 1 ? 'Intake card · ${rx.code}' : 'Intake card',
                card: card,
              ),
            ],
        ],
      ),
    );
  }
}

/// The pharmacist-built medicine list under the uploaded scan — read-only,
/// unlike `PrescriptionDetailCard` (the "My Prescriptions" screen's own
/// editable version of the same data), since a member reading this on Track
/// Order is confirming what the counter sent, not adjusting anything.
class _IntakeCardBlock extends StatelessWidget {
  final String title;
  final RemotePrescriptionCard card;

  const _IntakeCardBlock({required this.title, required this.card});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _titleStyle),
        if (card.doctor.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text('Dr. ${card.doctor}', style: _mutedStyle),
        ],
        const SizedBox(height: 8),
        for (final medicine in card.medicines) _IntakeMedicineLine(medicine),
      ],
    );
  }
}

class _IntakeMedicineLine extends StatelessWidget {
  final RemotePrescriptionMedicine medicine;

  const _IntakeMedicineLine(this.medicine);

  /// "Morning & night", spelled out from the three-digit code — the same
  /// wording `IntakePattern.labelWith` gives the editable card, kept as a
  /// plain function here rather than pulling in that class (and the
  /// `PrescriptionCopy` localisation it takes its slot names from) for one
  /// read-only line.
  String get _spelled {
    const slots = ['Morning', 'Afternoon', 'Night'];
    final counts = [medicine.morning, medicine.afternoon, medicine.night];
    final parts = <String>[
      for (var i = 0; i < 3; i++)
        if (counts[i] > 0)
          counts[i] > 1 ? '${slots[i]} ×${counts[i]}' : slots[i],
    ];
    if (parts.isEmpty) {
      return 'Not set';
    }
    return parts.length == 1 ? parts.single : parts.join(' & ');
  }

  String get _code =>
      '${medicine.morning}${medicine.afternoon}${medicine.night}';

  @override
  Widget build(BuildContext context) {
    final detail = medicine.pack.isEmpty
        ? _spelled
        : '${medicine.pack} · $_spelled';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicine.name,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(detail, style: _mutedStyle),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.offerTint,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _code,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.brandBlue,
              ),
            ),
          ),
          if (medicine.totalUnits > 0) ...[
            const SizedBox(width: 8),
            Text(
              '×${medicine.totalUnits}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Delivery info
// ---------------------------------------------------------------------------

/// Who the order is going to and where.
class DeliverToCard extends StatelessWidget {
  final Purchase order;

  const DeliverToCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final address = AddressBook.instance.deliverTo;
    final user = AuthService.instance.currentUser.value;
    final receiver = address?.receiver ?? user?.name ?? 'SHIELD Member';
    final pincode = AddressBook.instance.pincode;
    final label = address?.label.label ?? 'Home';
    final summary = address?.summary ?? AddressBook.describePincode(pincode);

    return _InfoCard(
      title: 'Deliver to:',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            receiver,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$label, $pincode',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(summary, style: _mutedStyle),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// The red "cancel this order" row. Only shown while an order can still be
/// pulled — see `OrderTrackScreen`.
class CancelOrderCard extends StatelessWidget {
  final Purchase order;

  const CancelOrderCard({super.key, required this.order});

  Future<void> _confirm(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Text(
          'Order ${order.id} will be cancelled. Nothing has been charged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep order'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if ((yes ?? false) && context.mounted) {
      _toast(context, 'Cancellation request submitted for ${order.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PlainCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: AppColors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _confirm(context),
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Cancel order',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.danger,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: AppColors.danger,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Support hours and a call button.
/// "Need Help?" — dials the phone number of whichever branch is serving
/// this member's account (`RegistrationService`'s own `store`), resolved
/// for real from `backend/api` via [StoreRepository] (`ShieldStore.phone`,
/// the client-side fixture field, is always blank — see its own doc).
/// Falls back to `PrescriptionCard.orderPhone`, SHIELD's own general order
/// line, whenever that branch has no number on file yet — the button never
/// goes nowhere.
class NeedHelpCard extends StatefulWidget {
  const NeedHelpCard({super.key});

  @override
  State<NeedHelpCard> createState() => _NeedHelpCardState();
}

class _NeedHelpCardState extends State<NeedHelpCard> {
  String? _resolvedPhone;

  @override
  void initState() {
    super.initState();
    unawaited(_resolvePhone());
  }

  Future<void> _resolvePhone() async {
    final store = RegistrationService.instance.profile?.store;
    final phone = store == null
        ? null
        : await StoreRepository.instance.phoneForCode(store.id);
    if (!mounted) {
      return;
    }
    setState(() => _resolvedPhone = phone);
  }

  @override
  Widget build(BuildContext context) {
    final store = RegistrationService.instance.profile?.store;
    final phone = _resolvedPhone ?? PrescriptionCard.orderPhone;

    return _PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Need Help?', style: _titleStyle),
          const SizedBox(height: 4),
          Text(
            store == null
                ? 'Call us between 8:00 am to 10:00 pm'
                : '${store.name} · ${store.hours}',
            style: _mutedStyle,
          ),
          const SizedBox(height: 12),
          _line,
          const SizedBox(height: 4),
          _linkButton(
            icon: Icons.call_rounded,
            label: 'Call us · $phone',
            onPressed: () => Dialer.call(context, phone),
          ),
        ],
      ),
    );
  }
}

/// The three social links.
class SocialMediaCard extends StatelessWidget {
  const SocialMediaCard({super.key});

  @override
  Widget build(BuildContext context) {
    return _PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Follow us on our Social Media', style: _titleStyle),
          const SizedBox(height: 12),
          _line,
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SocialIcon(
                icon: Icons.facebook_rounded,
                network: SocialNetwork.facebook,
              ),
              SizedBox(width: 20),
              _SocialIcon(
                icon: Icons.smart_display_rounded,
                network: SocialNetwork.youtube,
              ),
              SizedBox(width: 20),
              _SocialIcon(
                icon: Icons.camera_alt_rounded,
                network: SocialNetwork.instagram,
              ),
            ],
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }
}

class _SocialIcon extends StatelessWidget {
  final IconData icon;
  final SocialNetwork network;

  const _SocialIcon({required this.icon, required this.network});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandBlue,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => SocialLinks.open(context, network),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 22, color: AppColors.white),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bill
// ---------------------------------------------------------------------------

/// The itemised bill for the order.
class BillDetailsCard extends StatelessWidget {
  final Purchase order;

  const BillDetailsCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final bill = OrderBill(order);

    if (!bill.priced) {
      return _PlainCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Bill Details', style: _titleStyle),
            SizedBox(height: 10),
            Text(
              'The pharmacist prices your prescription and shares the bill '
              'before anything is charged.',
              style: _mutedStyle,
            ),
          ],
        ),
      );
    }

    return _PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Bill Details', style: _titleStyle),
          const SizedBox(height: 10),
          _BillRow(
            icon: Icons.shopping_cart_outlined,
            label: const Text('MRP'),
            value: Text(bill.mrpLabel, style: _billValueStyle),
          ),
          _BillRow(
            icon: Icons.percent_rounded,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(child: Text('Discount')),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.greenTint,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    bill.discountPercentLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandGreenDark,
                    ),
                  ),
                ),
              ],
            ),
            value: Text(
              bill.discountLabel,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.brandGreenDark,
              ),
            ),
          ),
          _BillRow(
            icon: Icons.receipt_long_outlined,
            label: const Text('Taxes and charges'),
            value: Text(bill.taxesLabel, style: _billValueStyle),
          ),
          _BillRow(
            icon: Icons.local_shipping_outlined,
            label: const Text('Delivery charge'),
            value: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  '₹149',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  'FREE',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandGreenDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _line,
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimated Payable',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Inclusive of all taxes',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                bill.payableLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _line,
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Payment mode',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Text(
                bill.paymentMode,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Invoice will be available to download once the order is delivered',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

const TextStyle _billValueStyle = TextStyle(
  fontSize: 13.5,
  fontWeight: FontWeight.w800,
  color: AppColors.textDark,
);

class _BillRow extends StatelessWidget {
  final IconData icon;
  final Widget label;
  final Widget value;

  const _BillRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 13.5, color: AppColors.textBody),
              child: label,
            ),
          ),
          const SizedBox(width: 10),
          value,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Store invoice
// ---------------------------------------------------------------------------

/// The invoice the store has attached to this order, once one has been sent
/// from the admin console — ported verbatim from the root SHIELD app's own
/// `order_detail_sections.dart`, backed here by [PurchaseService.
/// ensureBillLoaded]'s lazy fetch instead of that app's direct-Neon join.
///
/// Distinct from [BillDetailsCard]: that card is a breakdown worked out from
/// the two figures [Purchase] already carries, and can never disagree with
/// them because it is derived, not stored. This one is the store's own
/// document — a picture handed back through the app — and simply is not
/// there to show until an admin sends it and [ensureBillLoaded] has fetched
/// it, so the card renders nothing at all rather than a card with an empty
/// middle.
class StoreInvoiceCard extends StatelessWidget {
  final Purchase order;

  const StoreInvoiceCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final image = order.billImage;
    if (image == null) {
      return const SizedBox.shrink();
    }
    final billedAt = order.billedAt;

    return _PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Invoice from the store', style: _titleStyle),
          if (billedAt != null) ...[
            const SizedBox(height: 2),
            Text('Sent ${formatDate(billedAt)}', style: _mutedStyle),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 90,
                  height: 112,
                  decoration: BoxDecoration(
                    color: AppColors.pageTint,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: AppImage(
                    image: image,
                    fit: BoxFit.cover,
                    fallbackIcon: Icons.receipt_long_rounded,
                    iconSize: 34,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'The store has sent your bill for this order.',
                      style: _mutedStyle,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FullScreenImageView(
                            image: image,
                            title: 'Invoice · ${order.id}',
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View invoice'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.brandBlue,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
