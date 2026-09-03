import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../dates.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';
import '../../widgets/upload_picker.dart';
import '../cart/cart_control.dart';
import '../home/product_showcase.dart';
import '../location/address_book.dart';
import '../patients/patient_book.dart';
import '../prescription/upload_prescription_screen.dart';
import '../registration/registration_service.dart';
import '../registration/shield_store.dart';
import '../registration/store_map_picker.dart';
import '../wallet/wallet_service.dart';
import 'checkout_chrome.dart';
import 'checkout_order.dart';
import 'patient_address_details_screen.dart';
import 'payment_method.dart';
import 'payment_receipt.dart';
import 'receipt_form.dart';
import 'shield_payee.dart';

typedef CheckoutComplete = Future<void> Function(PaymentReceipt receipt);

/// Where the checkout's pre-filled store came from — drives the note under the
/// picker.
enum _StoreSource {
  registration,
  deliveryAddress,
  directoryDefault,
  planSelection,
}

/// Manual payment checkout shared by product orders and privilege plans.
class CheckoutScreen extends StatefulWidget {
  final CheckoutOrder order;
  final CheckoutComplete onComplete;

  /// Where to go once the receipt is in. When set, the checkout is replaced by
  /// this screen — the order-placed confirmation for a cart. When null it just
  /// pops with `true`, which is what the privilege flow expects.
  final WidgetBuilder? successScreen;

  /// Notifies this screen that [order] may be stale and [refreshOrder] should
  /// be called again — the cart's own listenable, passed through rather than
  /// read directly, so this screen still knows nothing about carts as such.
  /// "Last minute buys" adds straight into the caller's cart, behind this
  /// screen's back, and this is how the total it shows — and the one it
  /// eventually submits — catches up.
  final Listenable? liveTotals;

  /// Builds a fresh [CheckoutOrder] off whatever [liveTotals] just changed.
  /// Required whenever [liveTotals] is given.
  final CheckoutOrder Function()? refreshOrder;

  /// Whether the store is a picker on this checkout. A privilege-plan
  /// activation lets the member choose the branch to pin to their account;
  /// every product and pharmacy checkout after that shows it locked. Defaults
  /// to locked.
  final bool storeSelectable;

  const CheckoutScreen({
    super.key,
    required this.order,
    required this.onComplete,
    this.successScreen,
    this.liveTotals,
    this.refreshOrder,
    this.storeSelectable = false,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final ReceiptFormController _receipt = ReceiptFormController();
  final TextEditingController _agent = TextEditingController();
  final TextEditingController _bankReference = TextEditingController();
  final ReceiptPicker _picker = const ReceiptPicker();

  int _step = 1;
  PaymentMethod _method = PaymentMethods.bankTransfer;
  late ShieldStore _store;
  late StoreBankAccount _account;

  /// The order actually shown and, eventually, submitted — starts as
  /// [CheckoutScreen.order] and is replaced whenever [CheckoutScreen.liveTotals]
  /// fires, so a "Last minute buys" add on this very screen is reflected in
  /// the total before the member ever leaves it.
  late CheckoutOrder _order = widget.order;

  /// Who a delivery order is for. Nothing else in the app tracks "the current
  /// patient" the way [AddressBook] tracks "the current address", so this is
  /// carried locally and only ever set from what
  /// [PatientAddressDetailsScreen] hands back.
  Patient? _patient;

  /// Where the fixed store came from, which decides the note under it.
  _StoreSource _storeSource = _StoreSource.directoryDefault;

  /// Set once the member picks a branch on a selectable checkout, so the
  /// registration/address listeners stop pulling the store back to its
  /// default underneath them.
  bool _storePickedByHand = false;

  /// The activated plan this order is billed against, when the member holds
  /// more than one. The serving branch follows it. Null on a selectable
  /// checkout, or when the member holds fewer than two plans with a branch.
  WalletCard? _selectedPlan;

  /// Set once the member picks a plan by hand, so the registration/address
  /// listeners stop pulling the branch off that plan underneath them.
  bool _planPickedByHand = false;

  @override
  void initState() {
    super.initState();
    _syncDefaultStore();
    if (widget.order.requiresDelivery && PatientBook.instance.patients.isNotEmpty) {
      _patient = PatientBook.instance.patients.first;
    }
    _bankReference.addListener(() {
      _receipt.setBankReference(_bankReference.text);
    });
    _receipt.addListener(_refresh);
    // The store follows the member's registration, so keep watching it —
    // completing or editing registration while this screen is open still moves
    // it to the branch they signed up against.
    RegistrationService.instance.addListener(_onSourcesChanged);
    if (widget.order.requiresDelivery) {
      // So step one unlocks the moment an address is saved on the form pushed
      // over this screen — and the fallback store tracks that address.
      AddressBook.instance.addListener(_onSourcesChanged);
    }
    widget.liveTotals?.addListener(_onOrderChanged);
  }

  /// Pulls a fresh [CheckoutOrder] off [CheckoutScreen.refreshOrder] — what
  /// [CheckoutScreen.liveTotals] firing means.
  void _onOrderChanged() {
    final refresh = widget.refreshOrder;
    if (refresh == null || !mounted) {
      return;
    }
    setState(() => _order = refresh());
  }

  /// Re-resolves the store from the member's sources, then repaints.
  void _onSourcesChanged() {
    _syncDefaultStore();
    _refresh();
  }

  /// The activated plans this order could be billed against — the ones that
  /// recorded the branch they were activated at. Empty (so the chooser is
  /// hidden) on a selectable checkout, or unless the member holds at least two:
  /// with one there is nothing to choose between.
  List<WalletCard> get _billablePlans {
    if (widget.storeSelectable) {
      return const [];
    }
    final withStore = [
      for (final card in WalletService.instance.cards)
        if (card.store != null) card,
    ];
    return withStore.length >= 2 ? withStore : const [];
  }

  /// Resolves the fixed store and the bank account that goes with it.
  ///
  /// The branch from the member's registration comes first — that is the one
  /// they signed up (or activated a plan) against. Only when there is no
  /// registration does it fall back to the branch nearest the delivery address,
  /// then to the top of the directory. A member holding more than one plan then
  /// bills the order against one of them, and the branch follows that plan.
  void _syncDefaultStore() {
    // On a selectable checkout, a branch the member picked stays picked — the
    // point of the field there is the choice, not tracking the account.
    if (widget.storeSelectable && _storePickedByHand) {
      return;
    }

    // A plan the member chose to bill against fixes the branch to that plan's,
    // and the registration/address listeners stop pulling it back.
    if (_planPickedByHand && _selectedPlan != null) {
      _store = _selectedPlan!.store!;
      _storeSource = _StoreSource.planSelection;
      _account = ShieldPayees.forStore(_store).first;
      return;
    }

    final registered = RegistrationService.instance.profile?.store;
    if (registered != null) {
      _storeSource = _StoreSource.registration;
      _store = registered;
    } else {
      final pincode = AddressBook.instance.deliverTo?.pincode;
      final nearby = pincode != null
          ? StoreDirectory.suggestFor(pincode)
          : null;
      if (nearby != null) {
        _storeSource = _StoreSource.deliveryAddress;
        _store = nearby;
      } else {
        _storeSource = _StoreSource.directoryDefault;
        _store = StoreDirectory.all.first;
      }
    }

    // With more than one activated plan, default the chooser to the plan
    // already on the resolved branch, else the newest, and move the branch
    // onto it. The member can switch plans to bill a different branch.
    final plans = _billablePlans;
    if (plans.isNotEmpty) {
      _selectedPlan = plans.firstWhere(
        (card) => card.store!.id == _store.id,
        orElse: () => plans.last,
      );
      _store = _selectedPlan!.store!;
      _storeSource = _StoreSource.planSelection;
    } else {
      _selectedPlan = null;
    }

    _account = ShieldPayees.forStore(_store).first;
  }

  /// The line under the store field explaining where the fixed value came from,
  /// or null when there is nothing to explain.
  String? get _storeNote {
    switch (_storeSource) {
      case _StoreSource.registration:
        return 'The store you chose during registration. Every order on your '
            'account is served by this branch.';
      case _StoreSource.deliveryAddress:
        return 'Nearest branch to your delivery address. Complete registration '
            'to pin your own store here.';
      case _StoreSource.directoryDefault:
        return null;
      case _StoreSource.planSelection:
        final plan = _selectedPlan;
        return plan == null
            ? null
            : 'Serving branch for your ${plan.name}. Pick another plan above '
                  'to bill this order against a different branch.';
    }
  }

  @override
  void dispose() {
    _receipt.removeListener(_refresh);
    _receipt.dispose();
    _agent.dispose();
    _bankReference.dispose();
    RegistrationService.instance.removeListener(_onSourcesChanged);
    if (widget.order.requiresDelivery) {
      AddressBook.instance.removeListener(_onSourcesChanged);
    }
    widget.liveTotals?.removeListener(_onOrderChanged);
    super.dispose();
  }

  bool get _hasDeliveryAddress =>
      !widget.order.requiresDelivery ||
      AddressBook.instance.deliverTo != null;

  bool get _hasPatient => !widget.order.requiresDelivery || _patient != null;

  // The agent code is optional — an order placed without one is still valid —
  // so it does not gate the step. Only a live method and (where the order
  // ships) a delivery address and a patient do.
  /// The privilege-activation branch map needs a location fix before the
  /// member can move on. Ignored on the product / pharmacy checkout.
  bool _storeLocationReady = false;

  bool get _canContinue =>
      _method.isLive &&
      _hasDeliveryAddress &&
      _hasPatient &&
      (!widget.storeSelectable || _storeLocationReady);

  bool get _canSubmit => _canContinue && _receipt.isComplete && !_receipt.busy;

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Opens "Patient & address details", pre-selecting whoever is chosen
  /// already. Carries a new choice back; a bare back-press (no Save) returns
  /// null, which leaves both the address ([AddressBook] notifies on its own)
  /// and the patient exactly as they were.
  Future<void> _openPatientAddressDetails() async {
    final chosen = await Navigator.of(context).push<Patient>(
      MaterialPageRoute(
        builder: (_) => PatientAddressDetailsScreen(initialPatient: _patient),
      ),
    );
    if (chosen != null && mounted) {
      setState(() => _patient = chosen);
    }
  }

  void _applyCoupon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('No coupons are available for this order right now.'),
        ),
      );
  }

  void _openUploadPrescription() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UploadPrescriptionScreen()),
    );
  }

  void _chooseAccount(StoreBankAccount? account) {
    if (account != null) {
      setState(() => _account = account);
    }
  }

  /// Picks the branch this order — a privilege-plan activation — is served by,
  /// and moves the payee to that branch's account. Only reachable when
  /// [CheckoutScreen.storeSelectable] is set.
  void _chooseStore(ShieldStore store) {
    if (store.id == _store.id) {
      return;
    }
    setState(() {
      _store = store;
      _storePickedByHand = true;
      _account = ShieldPayees.forStore(store).first;
    });
  }

  /// Bills this order against [plan] and moves the serving branch — and the
  /// payee — onto the branch that plan was activated at. Only reachable when
  /// the member holds more than one plan with a branch.
  void _choosePlan(WalletCard plan) {
    if (plan.store == null || plan.load == _selectedPlan?.load) {
      return;
    }
    setState(() {
      _selectedPlan = plan;
      _planPickedByHand = true;
      _store = plan.store!;
      _storeSource = _StoreSource.planSelection;
      _account = ShieldPayees.forStore(_store).first;
    });
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

  Future<void> _pick(ImageSource source) async {
    final file = await _picker.pick(source);
    if (file != null) {
      _receipt.setFile(file);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      return;
    }
    _receipt.setBusy(true);
    try {
      final file = _receipt.file!;
      await widget.onComplete(
        PaymentReceipt(
          method: _method,
          fileName: file.name,
          bytes: file.bytes,
          imageDataUrl: file.dataUrl,
          orderReference: _order.reference,
          storeId: _store.id,
          bankAccount: _account,
          agentCode: _agent.text.trim(),
          bankReference: _receipt.bankReference,
          submittedAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      final success = widget.successScreen;
      if (success != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: success),
        );
      } else {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        _receipt.setBusy(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final delivering = widget.order.requiresDelivery;

    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: Text(
          delivering ? 'Order Summary' : 'Payment checkout',
          style: const TextStyle(
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
          CheckoutSteps(active: _step),
          const SizedBox(height: 14),
          if (delivering && _step == 1) ...[
            _DeliveryEstimateStrip(itemCount: _order.itemCount),
            const SizedBox(height: 14),
          ],
          _OrderSummary(order: _order),
          const SizedBox(height: 14),
          if (_step == 1) ...[
            if (delivering) ...[
              _QuickActionCard(
                iconBg: AppColors.goldTint,
                iconColor: AppColors.goldAccent,
                icon: Icons.assignment_outlined,
                title: 'Upload a Prescription',
                subtitle:
                    'Please upload a valid prescription given by your '
                    'doctor. This is optional',
                onTap: _openUploadPrescription,
              ),
              const SizedBox(height: 14),
              _QuickActionCard(
                iconBg: AppColors.panelBlue,
                iconColor: AppColors.brandBlue,
                icon: Icons.local_offer_outlined,
                title: 'Apply coupon',
                titleColor: AppColors.brandBlue,
                onTap: _applyCoupon,
              ),
              const SizedBox(height: 14),
              const _LastMinuteBuysPanel(),
              const SizedBox(height: 14),
            ],
            _StorePanel(
              store: _store,
              onLocationReady: (ready) {
                if (ready != _storeLocationReady) {
                  setState(() => _storeLocationReady = ready);
                }
              },
              account: _account,
              agent: _agent,
              storeNote: _storeNote,
              selectable: widget.storeSelectable,
              plans: _billablePlans,
              selectedPlan: _selectedPlan,
              onPlanChanged: _choosePlan,
              onStoreChanged: _chooseStore,
              onAccountChanged: _chooseAccount,
            ),
            const SizedBox(height: 14),
            _MethodPanel(selected: _method, onSelect: _chooseMethod),
          ] else ...[
            _BankTransferPanel(order: _order, account: _account),
            const SizedBox(height: 14),
            _ReceiptPanel(
              controller: _receipt,
              bankReference: _bankReference,
              onCamera: () => _pick(ImageSource.camera),
              onGallery: () => _pick(ImageSource.gallery),
            ),
          ],
        ],
      ),
      // Deliver-to and patient sit pinned above the action bar, never part of
      // the scroll — the one thing on this screen that stays in view and in
      // reach the whole time, since the whole page exists to get both right
      // before paying.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (delivering && _step == 1)
            Container(
              decoration: const BoxDecoration(
                color: AppColors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: _DeliverToAndPatientSection(
                address: AddressBook.instance.deliverTo,
                patient: _patient,
                onChange: _openPatientAddressDetails,
              ),
            ),
          CheckoutActionBar(
            amountLabel: _order.amountLabel,
            label: _step == 1
                ? (delivering ? 'Select payment mode' : 'Next')
                : _order.submitLabel,
            busy: _receipt.busy,
            onPressed: _step == 1
                ? (_canContinue ? () => setState(() => _step = 2) : null)
                : (_canSubmit ? _submit : null),
          ),
        ],
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  final CheckoutOrder order;

  const _OrderSummary({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            order.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            order.subtitle,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.textMuted,
            ),
          ),
          if (order.lines.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final line in order.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.label,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.textBody,
                        ),
                      ),
                    ),
                    Text(
                      line.amountLabel,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: line.isCredit
                            ? AppColors.brandGreenDark
                            : AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const Divider(height: 18, color: AppColors.border),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Transfer amount',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              Text(
                order.amountLabel,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Delivery by …" and the item count, right under the step tracker — the
/// same read a member gets from an order once it's placed, offered here
/// before they have committed to anything.
class _DeliveryEstimateStrip extends StatelessWidget {
  final int? itemCount;

  const _DeliveryEstimateStrip({required this.itemCount});

  /// `01 Sep – 03 Sep` — a promise counted from today, the same three-to-five
  /// day window an order is given once it is actually placed.
  String get _window {
    final now = DateTime.now();
    final from = now.add(const Duration(days: 3));
    final to = now.add(const Duration(days: 5));
    return '${formatDayMonth(from)} – ${formatDayMonth(to)}';
  }

  @override
  Widget build(BuildContext context) {
    final count = itemCount;

    return Row(
      children: [
        const Icon(
          Icons.local_shipping_outlined,
          size: 17,
          color: AppColors.brandGreenDark,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
              children: [
                const TextSpan(text: 'Delivery by '),
                TextSpan(
                  text: _window,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandGreenDark,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (count != null)
          Text(
            '$count item${count == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
      ],
    );
  }
}

/// A tinted icon tile, a title, and a chevron — "Upload a Prescription" and
/// "Apply coupon" on the order summary.
class _QuickActionCard extends StatelessWidget {
  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String title;
  final Color titleColor;
  final String? subtitle;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.onTap,
    this.titleColor = AppColors.textDark,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 21, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
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

/// A last-chance impulse-buy strip, the same [CartControl] every product tile
/// in the app uses — adding one here goes straight into the same cart that
/// is about to be checked out.
class _LastMinuteBuysPanel extends StatelessWidget {
  const _LastMinuteBuysPanel();

  @override
  Widget build(BuildContext context) {
    final products = ProductCatalogue.popularItems.take(8).toList();
    if (products.isEmpty) {
      return const SizedBox.shrink();
    }

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CheckoutHeading('Last minute buys'),
          const SizedBox(height: 10),
          SizedBox(
            height: 208,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) =>
                  _LastMinuteTile(product: products[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _LastMinuteTile extends StatelessWidget {
  final Product product;

  const _LastMinuteTile({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 128,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.35,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: AppImage(
                image: product.image,
                fallbackIcon: product.icon,
                iconSize: 30,
                iconColor: AppColors.brandBlue,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${product.price}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                CartControl(
                  name: product.name,
                  pack: product.pack,
                  price: product.price,
                  mrp: product.mrp,
                  image: product.image,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The deliver-to and patient rows, together at the foot of the order
/// summary — the last thing to confirm before choosing how to pay. Both
/// "Change" links, and either row itself, open the same combined screen:
/// picking who an order is for and where it goes is one decision, not two.
class _DeliverToAndPatientSection extends StatelessWidget {
  final Address? address;
  final Patient? patient;
  final VoidCallback onChange;

  const _DeliverToAndPatientSection({
    required this.address,
    required this.patient,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final address = this.address;
    final patient = this.patient;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(
            label: 'DELIVER TO',
            title: address == null
                ? 'Add a delivery address'
                : '${address.label.label} (${address.pincode})',
            subtitle: address?.summary,
            onChange: onChange,
          ),
          const Divider(height: 22, color: AppColors.border),
          _DetailRow(
            label: 'PATIENT',
            title: patient?.name ?? 'Add a patient',
            subtitle: patient?.summary,
            onChange: onChange,
          ),
          if (address == null || patient == null) ...[
            const SizedBox(height: 10),
            Text(
              address == null && patient == null
                  ? 'A delivery address and a patient are required to '
                        'continue.'
                  : address == null
                  ? 'A delivery address is required to continue.'
                  : 'A patient is required to continue.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String title;
  final String? subtitle;
  final VoidCallback onChange;

  const _DetailRow({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;

    return InkWell(
      onTap: onChange,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
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
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.brandBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StorePanel extends StatelessWidget {
  final ShieldStore store;
  final StoreBankAccount account;
  final TextEditingController agent;

  /// A line under the store field saying where the fixed value came from, or
  /// null when there is nothing to explain. Only shown when the store is
  /// locked.
  final String? storeNote;

  /// Whether the branch is a picker here (a privilege-plan activation) rather
  /// than the locked value every product and pharmacy checkout shows.
  final bool selectable;

  /// The member's activated plans, shown as a chooser above the locked branch
  /// when there is more than one. Picking one bills the order against it and
  /// moves the branch onto that plan's. Empty on a selectable checkout or when
  /// the member holds fewer than two plans with a branch.
  final List<WalletCard> plans;
  final WalletCard? selectedPlan;
  final ValueChanged<WalletCard> onPlanChanged;

  final ValueChanged<ShieldStore> onStoreChanged;
  final ValueChanged<StoreBankAccount?> onAccountChanged;

  /// Fires as the branch map's location gate opens / closes. Only meaningful
  /// when [selectable].
  final ValueChanged<bool>? onLocationReady;

  const _StorePanel({
    required this.store,
    required this.account,
    required this.agent,
    required this.storeNote,
    required this.selectable,
    required this.plans,
    required this.selectedPlan,
    required this.onPlanChanged,
    required this.onStoreChanged,
    required this.onAccountChanged,
    this.onLocationReady,
  });

  @override
  Widget build(BuildContext context) {
    final accounts = ShieldPayees.forStore(store);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CheckoutHeading('Your store & agent'),
          const SizedBox(height: 10),
          if (selectable) ...[
            const Text(
              'Choose the SHIELD branch to activate your plan against. Every '
              'product and pharmacy order on your account is served by this '
              'branch afterwards.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            StoreMapPicker(
              selectedId: store.id,
              onSelected: onStoreChanged,
              onLocationReady: onLocationReady,
            ),
          ] else ...[
            if (plans.isNotEmpty) ...[
              const Text(
                'Bill this order against one of your active plans. The serving '
                'branch follows the plan you pick.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.3,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 10),
              for (final plan in plans)
                _PickablePlanTile(
                  plan: plan,
                  selected: plan.load == selectedPlan?.load,
                  onTap: () => onPlanChanged(plan),
                ),
              const SizedBox(height: 10),
            ],
            // Locked: the branch pinned to the member's account at registration
            // or plan activation, and every order is served by it.
            LockedStoreCard(store: store, note: storeNote),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: agent,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Agent code (optional)',
              hintText: 'Enter it only if an agent is helping you',
              helperText: 'Leave blank if you do not have one',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          const CheckoutHeading('Choose bank account'),
          const SizedBox(height: 9),
          for (final option in accounts)
            _AccountTile(
              account: option,
              selected: option.id == account.id,
              onTap: () => onAccountChanged(option),
            ),
        ],
      ),
    );
  }
}


/// One activated plan on the product/pharmacy checkout, offered when the member
/// holds more than one. Picking it bills the order against that plan and moves
/// the serving branch onto the one it was activated at.
class _PickablePlanTile extends StatelessWidget {
  final WalletCard plan;
  final bool selected;
  final VoidCallback onTap;

  const _PickablePlanTile({
    required this.plan,
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
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.brandBlue : AppColors.border,
            ),
          ),
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? AppColors.brandBlue : AppColors.textMuted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      'Served by ${plan.store!.name}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodPanel extends StatelessWidget {
  final PaymentMethod selected;
  final ValueChanged<PaymentMethod> onSelect;

  const _MethodPanel({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CheckoutHeading('Payment option'),
          const SizedBox(height: 10),
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

class _BankTransferPanel extends StatelessWidget {
  final CheckoutOrder order;
  final StoreBankAccount account;

  const _BankTransferPanel({required this.order, required this.account});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CheckoutHeading('Transfer to this account'),
          const SizedBox(height: 10),
          _BankRow('Account name', account.accountName),
          _BankRow('Account number', account.accountNumber),
          _BankRow('IFSC', account.ifsc),
          _BankRow('Bank', account.bank),
          _BankRow('Branch', account.branch),
          _BankRow('Amount', order.amountLabel),
          _BankRow('Reference', order.reference),
        ],
      ),
    );
  }
}

class _ReceiptPanel extends StatelessWidget {
  final ReceiptFormController controller;
  final TextEditingController bankReference;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  const _ReceiptPanel({
    required this.controller,
    required this.bankReference,
    required this.onCamera,
    required this.onGallery,
  });

  @override
  Widget build(BuildContext context) {
    final file = controller.file;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CheckoutHeading('Upload payment receipt'),
          const SizedBox(height: 8),
          const Text(
            'After transfer, upload the bank or UPI receipt screenshot.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              UploadSourceTile(
                icon: Icons.photo_camera_outlined,
                label: 'Camera',
                enabled: !controller.busy,
                onTap: onCamera,
              ),
              const SizedBox(width: 10),
              UploadSourceTile(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                enabled: !controller.busy,
                onTap: onGallery,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (file != null)
            UploadedFileCard(
              name: file.name,
              bytes: file.bytes,
              tooLarge: controller.tooLarge,
              limitLabel: kReceiptLimitLabel,
              readyLabel: 'ready to submit',
              removeLabel: 'Remove receipt',
              onRemove: controller.clearFile,
            ),
          const SizedBox(height: 12),
          TextField(
            controller: bankReference,
            decoration: InputDecoration(
              labelText: 'UTR / transaction ID',
              hintText: 'From your bank or UPI app',
              helperText: 'Required — it matches your transfer to this order',
              border: const OutlineInputBorder(),
              errorText: file != null && controller.bankReference.isEmpty
                  ? 'Enter the UTR / transaction ID shown on your receipt'
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final StoreBankAccount account;
  final bool selected;
  final VoidCallback onTap;

  const _AccountTile({
    required this.account,
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
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.brandBlue : AppColors.border,
            ),
          ),
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? AppColors.brandBlue : AppColors.textMuted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.accountName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      account.shortLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BankRow extends StatelessWidget {
  final String label;
  final String value;

  const _BankRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

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
