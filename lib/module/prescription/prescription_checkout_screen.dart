import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/neon/order_repository.dart';
import '../../data/neon/prescription_repository.dart';
import '../../dates.dart';
import '../../theme/app_colors.dart';
import '../auth/auth_flow.dart';
import '../auth/auth_service.dart';
import '../checkout/checkout_chrome.dart';
import '../checkout/payment_method.dart';
import '../location/address_book.dart';
import '../location/address_form_screen.dart';
import '../orders/purchase_service.dart';
import '../registration/registration_service.dart';
import '../registration/shield_store.dart';
import 'medicine_duration.dart';
import 'prescription_record.dart';
import 'prescription_order_placed_screen.dart';

/// Checkout for the prescription basket.
///
/// A prescription is priced at the counter, so there is no bill to settle
/// here — what this screen collects is the delivery address and how the member
/// will pay once the pharmacist has confirmed the price. **Place order** files
/// it into My Orders as a processing order and empties the basket.
class PrescriptionCheckoutScreen extends StatefulWidget {
  final List<PrescriptionRecord> records;

  const PrescriptionCheckoutScreen({super.key, required this.records});

  @override
  State<PrescriptionCheckoutScreen> createState() =>
      _PrescriptionCheckoutScreenState();
}

class _PrescriptionCheckoutScreenState
    extends State<PrescriptionCheckoutScreen> {
  PaymentMethod _method = PaymentMethods.bankTransfer;
  bool _placing = false;

  /// The branch this order is served by. The one pinned to the account comes
  /// first — the store chosen at registration or privilege-plan activation —
  /// then the branch nearest the delivery address, then the top of the
  /// directory. Never a choice here: a prescription is packed by the member's
  /// own store like every other order.
  ShieldStore get _store {
    final registered = RegistrationService.instance.profile?.store;
    if (registered != null) {
      return registered;
    }
    final pincode = AddressBook.instance.deliverTo?.pincode;
    final nearby = pincode != null ? StoreDirectory.suggestFor(pincode) : null;
    return nearby ?? StoreDirectory.all.first;
  }

  /// The line under the locked store card, or null when there is nothing to
  /// explain.
  String? get _storeNote {
    if (RegistrationService.instance.profile?.store != null) {
      return 'The store on your account. Every order, including prescriptions, '
          'is served by this branch.';
    }
    final pincode = AddressBook.instance.deliverTo?.pincode;
    if (pincode != null && StoreDirectory.suggestFor(pincode) != null) {
      return 'Nearest branch to your delivery address. Complete registration '
          'to pin your own store here.';
    }
    return null;
  }

  void _chooseMethod(PaymentMethod method) {
    if (!method.isLive) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(method.comingSoonNote)));
      return;
    }
    setState(() => _method = method);
  }

  Future<void> _placeOrder() async {
    if (_placing) {
      return;
    }
    // The delivery address is the one thing this screen exists to collect, so
    // there is no order to place without it.
    if (AddressBook.instance.deliverTo == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Add a delivery address to place the order.'),
          ),
        );
      return;
    }
    setState(() => _placing = true);

    await AuthFlow.guard(context, () async {
      final id = 'SHD-${100500 + PurchaseService.instance.purchases.length}';
      final purchase = PurchaseService.instance.record(
        id: id,
        placedOn: formatDate(DateTime.now()),
        // One line per prescription — the medicines are not known yet, the
        // pharmacist builds that list after the call.
        itemCount: widget.records.length,
        // Priced at the counter — nothing is owed yet, and a made-up figure
        // here would flow straight into the earnings total.
        mrpTotal: 0,
        paidTotal: 0,
        status: OrderStatus.processing,
        kind: OrderKind.prescription,
      );
      // Write the prescription chain — patient, prescription and a
      // kind:PRESCRIPTION order — through to Neon. Best-effort: a missing or
      // unreachable database must not stop the order.
      final user = AuthService.instance.currentUser.value;
      if (user != null) {
        unawaited(
          OrderRepository.instance.savePrescriptionOrder(
            phone: user.phone,
            name: user.name,
            orderCode: id,
            storeCode: _store.id,
            paymentMethodCode: _method.id,
            address: AddressBook.instance.deliverTo?.toDeliveryInput(),
            prescriptions: [
              for (final record in widget.records) _prescriptionInput(record),
            ],
          ),
        );
        for (final record in widget.records) {
          unawaited(
            PrescriptionRepository.instance.markOrdered(
              memberPhone: user.phone,
              prescriptionUuid: record.remoteId,
            ),
          );
        }
      }
      // The records stay in the book; they just move to the "ordered, waiting
      // on the pharmacist" state the upload screen shows.
      for (final record in widget.records) {
        PrescriptionBook.instance.markOrdered(record.id);
      }

      if (!mounted) {
        return;
      }
      // Replaces the checkout: it is done, and the confirmation is where the
      // member decides whether to track the order or head back to the shop.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PrescriptionOrderPlacedScreen(order: purchase),
        ),
      );
    });

    if (mounted) {
      setState(() => _placing = false);
    }
  }

  /// One [PrescriptionRecord] as the plain-values shape [OrderRepository]
  /// persists. Only complete medicine lines are sent — a half-keyed row is not
  /// something to file.
  static PrescriptionInput _prescriptionInput(PrescriptionRecord record) {
    final patient = record.patient;
    return PrescriptionInput(
      remoteUuid: record.remoteId,
      code: record.number,
      fileName: record.fileName,
      doctor: record.doctor,
      duration: _durationToken(record.duration),
      customDays: record.customDays,
      recurringFrom: record.recurring?.from,
      recurringUntil: record.recurring?.until,
      patient: PrescriptionPatientInput(
        remoteUuid: patient.remoteId,
        name: patient.name,
        phone: patient.phone,
        address: patient.address,
        dob: patient.dob,
        gender: patient.gender.name.toUpperCase(),
        relation: patient.relation.name.toUpperCase(),
        abhaId: patient.abhaId,
      ),
      medicines: [
        for (final medicine in record.dispensable)
          PrescriptionMedicineInput(
            name: medicine.name,
            pack: medicine.pack,
            doseMorning: medicine.intake.morning,
            doseAfternoon: medicine.intake.afternoon,
            doseNight: medicine.intake.night,
          ),
      ],
    );
  }

  /// [MedicineDuration] as its `app.medicine_duration` token, or null.
  static String? _durationToken(MedicineDuration? duration) => switch (duration) {
        MedicineDuration.oneWeek => 'ONE_WEEK',
        MedicineDuration.fifteenDays => 'FIFTEEN_DAYS',
        MedicineDuration.oneMonth => 'ONE_MONTH',
        MedicineDuration.twoMonths => 'TWO_MONTHS',
        MedicineDuration.threeMonths => 'THREE_MONTHS',
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Checkout',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _SummaryCard(records: widget.records),
          const SizedBox(height: 14),
          // The store follows the account, so keep it in step with a
          // registration completed or an address saved over this screen.
          ListenableBuilder(
            listenable: Listenable.merge([
              RegistrationService.instance,
              AddressBook.instance,
            ]),
            builder: (context, _) => _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CheckoutHeading('Your store'),
                  const SizedBox(height: 10),
                  LockedStoreCard(store: _store, note: _storeNote),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _DeliveryCard(),
          const SizedBox(height: 14),
          _PaymentCard(selected: _method, onSelect: _chooseMethod),
        ],
      ),
      // Rebuilds with the address book so the bar unlocks the moment a
      // delivery address is saved on the form above.
      bottomNavigationBar: ListenableBuilder(
        listenable: AddressBook.instance,
        builder: (context, _) => _PlaceOrderBar(
          busy: _placing,
          hasAddress: AddressBook.instance.deliverTo != null,
          onPressed: _placeOrder,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<PrescriptionRecord> records;

  const _SummaryCard({required this.records});

  @override
  Widget build(BuildContext context) {
    final n = records.length;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$n prescription${n == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          for (final record in records)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      record.number,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      record.patient.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 14, color: AppColors.border),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: AppColors.brandGreenDeep,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The pharmacist reads each script, calls you to confirm the '
                  'medicines, and prices it at the counter. You see the bill '
                  'before paying.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textBody,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard();

  void _edit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddressFormScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AddressBook.instance,
      builder: (context, _) {
        final address = AddressBook.instance.deliverTo;

        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    size: 20,
                    color: AppColors.brandBlue,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Delivery address',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  if (address != null)
                    TextButton(
                      onPressed: () => _edit(context),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandBlue,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (address == null)
                OutlinedButton.icon(
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.add_location_alt_outlined, size: 20),
                  label: const Text('Add delivery address'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandBlue,
                    side: const BorderSide(
                      color: AppColors.brandBlue,
                      width: 1.4,
                    ),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                )
              else
                Text(
                  '${address.receiver}\n${address.summary}\n${address.phone}',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textBody,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onSelect;

  const _PaymentCard({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment method',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Charged only after the pharmacy confirms the price.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          for (final method in PaymentMethods.all) ...[
            _MethodTile(
              method: method,
              selected: method.id == selected.id,
              onTap: () => onSelect(method),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? method.tint : AppColors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? method.accent : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: method.tint,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(method.icon, size: 20, color: method.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      method.blurb,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!method.isLive) const ComingSoonPill(),
              if (method.isLive)
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? method.accent : AppColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The foot of the checkout: no amount, because nothing is owed until the
/// counter has priced it — just the one way forward.
class _PlaceOrderBar extends StatelessWidget {
  final bool busy;
  final bool hasAddress;
  final VoidCallback onPressed;

  const _PlaceOrderBar({
    required this.busy,
    required this.hasAddress,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  hasAddress
                      ? 'Priced at the counter'
                      : 'Add a delivery address first',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: hasAddress
                        ? FontWeight.w400
                        : FontWeight.w600,
                    color: hasAddress
                        ? AppColors.textMuted
                        : AppColors.danger,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: (busy || !hasAddress) ? null : onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text(
                          'Place order',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
