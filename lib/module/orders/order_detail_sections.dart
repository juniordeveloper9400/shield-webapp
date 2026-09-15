import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/backend/order_repository.dart';
import '../../money.dart';
import '../../theme/app_colors.dart';
import '../../widgets/social_glyphs.dart';
import '../auth/auth_service.dart';
import '../checkout/fulfillment_type.dart';
import '../location/address_book.dart';
import '../wallet/wallet_service.dart';
import 'order_contact_service.dart';
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

  /// Whether a "Pay now" button belongs on this bill: a prescription that has
  /// actually been priced and is still owed.
  bool get canPayNow =>
      order.kind == OrderKind.prescription &&
      (order.billAmount ?? 0) > 0 &&
      order.billStatus == OrderPaymentStatus.pending;
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
class PrescriptionUploadedCard extends StatelessWidget {
  const PrescriptionUploadedCard({super.key});

  @override
  Widget build(BuildContext context) {
    return _PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Prescription uploaded', style: _titleStyle),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 90,
                height: 112,
                decoration: BoxDecoration(
                  color: AppColors.pageTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  size: 34,
                  color: AppColors.brandBlue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'The pharmacist is reading this to price your order.',
                      style: _mutedStyle,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () =>
                          _toast(context, 'Opening your prescription'),
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

/// Where order updates are emailed. Reads [OrderContactService]: a link to
/// add one until it is set, then the address itself with change/remove.
class EmailIdCard extends StatelessWidget {
  const EmailIdCard({super.key});

  Future<void> _edit(BuildContext context) async {
    final contacts = OrderContactService.instance;
    final value = await _promptForText(
      context,
      title: contacts.hasEmail ? 'Edit email ID' : 'Add email ID',
      label: 'Email ID',
      hint: 'you@example.com',
      initialValue: contacts.email,
      keyboardType: TextInputType.emailAddress,
      validate: _validateEmail,
    );
    if (value != null) {
      contacts.setEmail(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Email ID',
      child: ListenableBuilder(
        listenable: OrderContactService.instance,
        builder: (context, _) {
          final email = OrderContactService.instance.email;
          if (email == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'We will send all updates related to your order to this '
                  'email ID',
                  style: _mutedStyle,
                ),
                const SizedBox(height: 12),
                _line,
                const SizedBox(height: 4),
                _linkButton(
                  icon: Icons.add_rounded,
                  label: 'Add email ID',
                  onPressed: () => _edit(context),
                ),
              ],
            );
          }
          return _SavedContactRow(
            value: email,
            caption: 'Order updates are sent here',
            onEdit: () => _edit(context),
            onRemove: () => OrderContactService.instance.setEmail(null),
          );
        },
      ),
    );
  }
}

/// The number order updates go to, plus a second one added from here.
class DeliveryUpdatesCard extends StatelessWidget {
  final Purchase order;

  const DeliveryUpdatesCard({super.key, required this.order});

  Future<void> _edit(BuildContext context) async {
    final contacts = OrderContactService.instance;
    final value = await _promptForText(
      context,
      title: contacts.hasAlternateNumber
          ? 'Edit alternate number'
          : 'Add alternate number',
      label: 'Alternate number',
      hint: '10-digit mobile number',
      initialValue: contacts.alternateNumber,
      keyboardType: TextInputType.phone,
      formatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      validate: (text) => AuthService.validatePhone(text),
    );
    if (value != null) {
      contacts.setAlternateNumber(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser.value;
    final phone =
        user?.phone ?? AddressBook.instance.deliverTo?.phone ?? '9400000000';

    return _InfoCard(
      title: 'Get delivery updates on',
      child: ListenableBuilder(
        listenable: OrderContactService.instance,
        builder: (context, _) {
          final alternate = OrderContactService.instance.alternateNumber;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Registered number',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  Text(
                    phone,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _line,
              const SizedBox(height: 4),
              if (alternate == null)
                _linkButton(
                  icon: Icons.add_rounded,
                  label: 'Add alternate number',
                  onPressed: () => _edit(context),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _SavedContactRow(
                    value: alternate,
                    caption: 'Alternate number',
                    onEdit: () => _edit(context),
                    onRemove: () =>
                        OrderContactService.instance.setAlternateNumber(null),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A saved email or number: the value, a one-line caption, and change/remove.
class _SavedContactRow extends StatelessWidget {
  final String value;
  final String caption;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _SavedContactRow({
    required this.value,
    required this.caption,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        _CompactButton(label: 'Change', onPressed: onEdit),
        _CompactButton(label: 'Remove', onPressed: onRemove, danger: true),
      ],
    );
  }
}

class _CompactButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  const _CompactButton({
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: danger ? AppColors.danger : AppColors.brandBlue,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
      child: Text(label),
    );
  }
}

/// Null when [value] is a usable email address.
String? _validateEmail(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return 'Email is required';
  }
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
    return 'Enter a valid email address';
  }
  return null;
}

/// Pops a one-field dialog and resolves to the entered text, or null if the
/// member backed out. [validate] returns null when the text is acceptable.
Future<String?> _promptForText(
  BuildContext context, {
  required String title,
  required String label,
  required String hint,
  required String? Function(String) validate,
  String? initialValue,
  TextInputType keyboardType = TextInputType.text,
  List<TextInputFormatter> formatters = const [],
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _InputDialog(
      title: title,
      label: label,
      hint: hint,
      initialValue: initialValue,
      keyboardType: keyboardType,
      formatters: formatters,
      validate: validate,
    ),
  );
}

class _InputDialog extends StatefulWidget {
  final String title;
  final String label;
  final String hint;
  final String? initialValue;
  final TextInputType keyboardType;
  final List<TextInputFormatter> formatters;
  final String? Function(String) validate;

  const _InputDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.keyboardType,
    required this.formatters,
    required this.validate,
  });

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    final error = widget.validate(text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.formatters,
        onChanged: (_) {
          if (_error != null) {
            setState(() => _error = null);
          }
        },
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
          child: const Text('Save'),
        ),
      ],
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
class NeedHelpCard extends StatelessWidget {
  const NeedHelpCard({super.key});

  @override
  Widget build(BuildContext context) {
    return _PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Need Help?', style: _titleStyle),
          const SizedBox(height: 4),
          const Text(
            'Call us between 8:00 am to 10:00 pm',
            style: _mutedStyle,
          ),
          const SizedBox(height: 12),
          _line,
          const SizedBox(height: 4),
          _linkButton(
            icon: Icons.call_rounded,
            label: 'Call us',
            onPressed: () => _toast(context, 'Connecting you to SHIELD support'),
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
// Cross-sell
// ---------------------------------------------------------------------------

/// The lab-package promo strip.
class LabPackagePromoCard extends StatelessWidget {
  const LabPackagePromoCard({super.key});

  static const int _price = 999;
  static const int _listPrice = 2498;

  // Whole-percent, rounded down the same way every other discount in the app
  // is — a promise is not overstated by a rounding rule.
  static int get _percentOff =>
      ((_listPrice - _price) * 100 ~/ _listPrice);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.creamTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // A faint watermark of what the card is selling, the same touch
          // the wallet and earnings cards use behind their own headline.
          Positioned(
            right: -14,
            bottom: -18,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.08,
                child: Icon(
                  Icons.science_rounded,
                  size: 96,
                  color: AppColors.goldAccent,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The offer icon: a tag rather than the flask — this
                    // badge is what says "discount", the flask watermark
                    // behind the card is what says "lab test".
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.goldAccent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.local_offer_rounded,
                        size: 21,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Full body packages from ₹999',
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.25,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Diabetes, Thyroid, Heart, Vitamin & more tests',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textBody,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.goldAccent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'BEST SELLER',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.greenTint,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.brandGreenDeep.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      child: Text(
                        '$_percentOff% OFF',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: AppColors.brandGreenDeep,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      '₹$_price',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '₹$_listPrice',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.groups_2_outlined,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '10,000+ booked',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () =>
                      _toast(context, 'Lab packages open in Lab Tests'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Book Now',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
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
          if (bill.canPayNow) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _PayBillSheet.show(context, order),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandBlue,
                  side: const BorderSide(color: AppColors.brandBlue, width: 1.4),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Pay ₹${formatRupees(order.billAmount ?? 0)} now',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pay now
// ---------------------------------------------------------------------------

/// The bottom sheet a prescription's "Pay now" opens: the priced bill, then
/// Wallet or Cash. Wallet debits the balance instantly and marks the order —
/// and its bill — paid; Cash just tells the member how it is settled instead.
class _PayBillSheet extends StatefulWidget {
  final Purchase order;

  const _PayBillSheet({required this.order});

  static Future<void> show(BuildContext context, Purchase order) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _PayBillSheet(order: order),
    );
  }

  @override
  State<_PayBillSheet> createState() => _PayBillSheetState();
}

class _PayBillSheetState extends State<_PayBillSheet> {
  bool _busy = false;

  int get _amount => widget.order.billAmount ?? 0;

  Future<void> _payWithWallet() async {
    final wallet = WalletService.instance;
    final backendId = widget.order.backendId;
    if (_amount <= 0 || backendId == null) {
      return;
    }
    if (!wallet.isActivated || wallet.balance < _amount) {
      _toast(context, 'Not enough wallet balance to pay this bill.');
      return;
    }

    setState(() => _busy = true);
    final spent = wallet.spendBalance(
      amount: _amount,
      label: 'Order ${widget.order.id}',
    );
    if (!spent) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(context, 'Wallet payment failed. Please try again.');
      }
      return;
    }

    // Best-effort write-through, same contract as every other order write —
    // the local wallet debit above and the optimistic update below are what
    // the member actually sees; this is what keeps the backend in step.
    unawaited(OrderRepository.instance.payBillWithWallet(orderId: backendId));

    PurchaseService.instance.updateOne(
      widget.order.copyWith(
        paymentStatus: OrderPaymentStatus.paid,
        billStatus: OrderPaymentStatus.paid,
      ),
    );

    if (mounted) {
      setState(() => _busy = false);
      _toast(context, 'Paid from your wallet.');
      Navigator.of(context).pop();
    }
  }

  void _payWithCash() {
    _toast(context, 'Pay the delivery person, or at the store, when it arrives.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Pay ₹${formatRupees(_amount)}', style: _titleStyle),
            const SizedBox(height: 2),
            Text('Order ${widget.order.id}', style: _mutedStyle),
            const SizedBox(height: 16),
            _PayOptionTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Wallet balance',
              subtitle: WalletService.instance.isActivated
                  ? '₹${formatRupees(WalletService.instance.balance)} available'
                  : 'Get a Sahakar HealthPass first',
              busy: _busy,
              onTap: _busy ? null : _payWithWallet,
            ),
            const SizedBox(height: 10),
            _PayOptionTile(
              icon: Icons.payments_outlined,
              title: 'Cash',
              subtitle: 'Pay the delivery person, or at the store on pickup',
              busy: false,
              onTap: _busy ? null : _payWithCash,
            ),
          ],
        ),
      ),
    );
  }
}

class _PayOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback? onTap;

  const _PayOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.pageTint,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 19, color: AppColors.brandBlue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(subtitle, style: _mutedStyle),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ),
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
// Sticky pay footer
// ---------------------------------------------------------------------------

/// The pinned "pay for this order" bar, for a prescription order that has not
/// been paid. Payment stays locked until the order is out for dispatch — the
/// same rule the in-card nudge states.
class OrderPayFooter extends StatelessWidget {
  final Purchase order;

  const OrderPayFooter({super.key, required this.order});

  bool get _priced => order.mrpTotal > 0;

  bool get _ready => order.status == OrderStatus.outForDelivery;

  void _pay(BuildContext context) {
    _toast(context, 'Payment opens once the pharmacist confirms the price.');
  }

  @override
  Widget build(BuildContext context) {
    final bill = OrderBill(order);
    final canPay = _priced && _ready;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Color(0x14163055),
              blurRadius: 12,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.pageTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 18,
                      color: AppColors.brandBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pay using',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        SizedBox(height: 1),
                        Text(
                          'UPI',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _toast(context, 'Choose a payment method'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandBlue,
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: AppColors.goldTint,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                canPay
                    ? 'Your order is ready for dispatch — complete payment now'
                    : 'You can pay once order is ready for dispatch',
                style: const TextStyle(fontSize: 12.5, color: AppColors.textDark),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canPay ? () => _pay(context) : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    disabledBackgroundColor: AppColors.searchBorder,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _priced ? 'Pay ${bill.payableLabel}' : 'Awaiting price',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
