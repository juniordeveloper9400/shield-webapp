import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend/address_repository.dart';
import '../../data/backend/prescription_repository.dart';
import '../../dates.dart';
import '../../money.dart';
import '../../theme/app_colors.dart';
import '../auth/auth_flow.dart';
import '../auth/auth_service.dart';
import '../checkout/checkout_chrome.dart';
import '../checkout/fulfillment_type.dart';
import '../checkout/payment_method.dart';
import '../location/address_book.dart';
import '../location/address_selection_screen.dart';
import '../orders/purchase_service.dart';
import '../registration/registration_service.dart';
import '../registration/shield_store.dart';
import '../wallet/wallet_service.dart';
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
  // Cash is the safe default — always selectable, unlike wallet, which may
  // not even be open yet. Bank transfer is no longer offered here.
  PaymentMethod _method = PaymentMethods.cash;
  FulfillmentType _fulfillment = FulfillmentType.homeDelivery;
  bool _placing = false;

  void _chooseFulfillment(FulfillmentType fulfillment) {
    if (fulfillment == _fulfillment) {
      return;
    }
    setState(() => _fulfillment = fulfillment);
  }

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

  /// Every record resolves to a real address — its own, or the shared
  /// default — so nothing in this checkout is left with nowhere to ship.
  bool get _everyRecordHasAddress => widget.records.every(
    (record) => (record.address ?? AddressBook.instance.deliverTo) != null,
  );

  Future<void> _placeOrder() async {
    if (_placing) {
      return;
    }
    // A delivery address is only needed when the order actually ships — a
    // pickup order has nowhere to deliver to.
    final needsAddress = _fulfillment == FulfillmentType.homeDelivery;
    if (needsAddress && !_everyRecordHasAddress) {
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
      // Submit the fulfilment order through the backend — an unpriced
      // shell, pharmacist-priced at the counter. Best-effort: an
      // unconfigured or unreachable backend must not stop the order.
      final user = AuthService.instance.currentUser.value;
      if (user != null) {
        // Make sure each prescription's own upload write has actually
        // landed on the backend (so `record.remoteId` is set) before
        // `_submitToBackend` reads it — otherwise a slow connection (web's
        // per-call overhead especially) can lose the race: `remoteId` is
        // still null, `_submitToBackend` silently drops that record
        // (`prescriptionId == null` → `continue`), and the member's script
        // never reaches the backend as an order at all. A no-op once the
        // write has already finished, which is the common case.
        await Future.wait([
          for (final record in widget.records)
            PrescriptionBook.instance.awaitPendingUpload(record.id),
        ]);
        unawaited(_submitToBackend());
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

  /// Resolves each record's backend prescription id (pinned at upload time
  /// — see `PrescriptionFormController._persist`), groups the records by
  /// delivery address, and submits one fulfilment order per distinct
  /// address. A record with its own [PrescriptionRecord.address] (chosen at
  /// upload, for a member sending several prescriptions to different family
  /// members) ships separately from the rest; every record left unset falls
  /// back to the shared [AddressBook.deliverTo] and travels together in one
  /// order, exactly as before this could ever differ. A record never synced
  /// to the backend (a network blip at upload time) is left out rather than
  /// failing the whole submission — same best-effort contract as every
  /// write here.
  ///
  /// Grouped by object identity, not by matching field values: two records
  /// that happen to have separately-created but identical-looking addresses
  /// place two orders instead of one combined order — a minor inefficiency
  /// (an extra `AddressRepository.create` call), not a correctness issue,
  /// and the same class of thing `AddressRepository`'s own doc already notes
  /// about `create` having no dedup.
  ///
  /// The real backend order id(s) `submitForOrder` returns are not written
  /// onto the local [Purchase] directly — [PurchaseService.refresh] re-lists
  /// from `GET /v1/member/orders` instead, which is where [Purchase.backendId]
  /// actually comes from ([Purchase.fromRow]). Without this, a just-placed
  /// order stays `backendId: null` until some other refresh happens to run,
  /// and `PrescriptionUploadedCard` — which needs [Purchase.backendId] to
  /// fetch the uploaded script — silently shows its placeholder icon instead.
  Future<void> _submitToBackend() async {
    final groups = <Address?, List<int>>{};
    for (final record in widget.records) {
      final prescriptionId = int.tryParse(record.remoteId ?? '');
      if (prescriptionId == null) {
        continue;
      }
      final resolved = record.address ?? AddressBook.instance.deliverTo;
      (groups[resolved] ??= []).add(prescriptionId);
    }
    if (groups.isEmpty) {
      return;
    }

    var anySubmitted = false;
    for (final entry in groups.entries) {
      final address = entry.key;
      final addressId =
          address == null ? null : await AddressRepository.instance.create(address);
      final orderId = await PrescriptionRepository.instance.submitForOrder(
        prescriptionIds: entry.value,
        addressId: addressId,
        fulfillmentType: _fulfillment,
        paymentMethodCode: _method.id,
      );
      if (orderId != null) {
        anySubmitted = true;
      }
    }
    if (anySubmitted) {
      await PurchaseService.instance.refresh();
    }
  }

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
          _FulfillmentCard(
            selected: _fulfillment,
            store: _store,
            onSelect: _chooseFulfillment,
          ),
          const SizedBox(height: 14),
          if (_fulfillment == FulfillmentType.homeDelivery)
            const _DeliveryCard()
          else
            _PickupCard(store: _store),
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
          hasAddress: _fulfillment == FulfillmentType.storePickup ||
              _everyRecordHasAddress,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                  // Only shown when this record ships to its own address —
                  // otherwise it silently rides along with whichever address
                  // the "Delivery address" card below settles on, same as
                  // before a record could carry one of its own.
                  if (record.address != null) ...[
                    const SizedBox(height: 3),
                    Padding(
                      padding: const EdgeInsets.only(left: 44),
                      child: Text(
                        '→ ${record.address!.receiver}, ${record.address!.summary}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
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

/// The home-delivery / store-pickup chooser — the same choice a standard
/// cart checkout offers, so a prescription order is never limited to
/// delivery only.
class _FulfillmentCard extends StatelessWidget {
  final FulfillmentType selected;
  final ShieldStore store;
  final ValueChanged<FulfillmentType> onSelect;

  const _FulfillmentCard({
    required this.selected,
    required this.store,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CheckoutHeading('How should this reach you?'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _FulfillmentChip(
                  icon: Icons.local_shipping_outlined,
                  label: FulfillmentType.homeDelivery.label,
                  selected: selected == FulfillmentType.homeDelivery,
                  onTap: () => onSelect(FulfillmentType.homeDelivery),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FulfillmentChip(
                  icon: Icons.storefront_outlined,
                  label: FulfillmentType.storePickup.label,
                  selected: selected == FulfillmentType.storePickup,
                  onTap: () => onSelect(FulfillmentType.storePickup),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FulfillmentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FulfillmentChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.chipBlueTint : AppColors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.brandBlue : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.brandBlue : AppColors.textMuted,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.brandBlue : AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What "Deliver to" becomes once store pickup is chosen — nothing to add,
/// just where to go.
class _PickupCard extends StatelessWidget {
  final ShieldStore store;

  const _PickupCard({required this.store});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          const Icon(
            Icons.storefront_outlined,
            size: 20,
            color: AppColors.brandBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pick up in store',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${store.name}, ${store.addressLine}',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textBody,
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

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard();

  void _edit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddressSelectionScreen()),
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
          // The wallet tile listens to WalletService directly so its balance
          // stays live without this screen tracking it itself — same pattern
          // as the standard cart checkout's own wallet tile, just without a
          // known order total yet to split against (a prescription is priced
          // later, at the counter).
          ListenableBuilder(
            listenable: WalletService.instance,
            builder: (context, _) {
              final wallet = WalletService.instance;
              return Column(
                children: [
                  for (final method in PaymentMethods.forOrder) ...[
                    _MethodTile(
                      method: method,
                      selected: method.id == selected.id,
                      onTap: () => onSelect(method),
                      subtitle: method.id == PaymentMethods.wallet.id
                          ? (wallet.isActivated
                              ? 'Balance: ₹${formatRupees(wallet.balance)} — any shortfall '
                                    'once priced is collected in cash'
                              : 'Get a Sahakar HealthPass first')
                          : null,
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  /// Overrides [PaymentMethod.blurb] — the wallet tile's live balance line.
  final String? subtitle;

  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
    this.subtitle,
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
                      subtitle ?? method.blurb,
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
