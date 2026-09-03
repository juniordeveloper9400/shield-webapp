import 'package:flutter/material.dart';

import '../../data/neon/prescription_repository.dart';
import '../../theme/app_colors.dart';
import '../auth/auth_service.dart';
import '../location/address_book.dart';
import '../location/address_form_screen.dart';
import 'prescription_checkout_screen.dart';
import 'prescription_copy.dart';
import 'prescription_detail_card.dart';
import 'prescription_form.dart';
import 'prescription_form_sheet.dart';
import 'prescription_record.dart';

/// Prescription flow, in two halves.
///
/// With nothing uploaded the screen is the upload form: pick from camera or
/// gallery, review the file against the stated rules, say who it is for, how
/// much to dispense, and whether it repeats. Once something has been uploaded
/// the same screen becomes the list of prescriptions, each one showing what
/// the pharmacy read on it — because from that point on the question is no
/// longer "how do I upload this" but "what is on it, and do I want it".
class UploadPrescriptionScreen extends StatefulWidget {
  const UploadPrescriptionScreen({super.key, this.initialForm});

  /// The form the screen opens with.
  ///
  /// Injectable because choosing a file otherwise runs through the platform
  /// image picker, which no widget test can drive — so the half of Proceed
  /// that matters, the half where it becomes enabled, had never once been
  /// exercised. That is how it came to be permanently grey.
  ///
  /// The screen takes ownership and disposes it like one of its own.
  final PrescriptionFormController? initialForm;

  /// Cap from the on-screen guidance.
  static const int maxBytes = kPrescriptionMaxBytes;

  @override
  State<UploadPrescriptionScreen> createState() =>
      _UploadPrescriptionScreenState();
}

class _UploadPrescriptionScreenState extends State<UploadPrescriptionScreen> {
  final PrescriptionBook _book = PrescriptionBook.instance;

  /// The inline form, shown only while the book is empty. Replaced rather than
  /// reused after a submission, so a second prescription never opens with the
  /// first one's file and patient already filled in.
  late PrescriptionFormController _form =
      widget.initialForm ?? PrescriptionFormController();

  /// Screen-local, and deliberately not remembered between visits: a member
  /// who switches once to read the steps should not find the whole flow in a
  /// language they did not choose the next time they upload.
  AppLanguage _language = AppLanguage.english;

  PrescriptionCopy get _copy => PrescriptionCopy.of(_language);

  /// Prescriptions that still need the fulfilment order placed.
  List<PrescriptionRecord> get _unordered =>
      _book.records.where((record) => record.isAwaitingOrder).toList();

  @override
  void initState() {
    super.initState();
    _book.addListener(_onBookChanged);
    _refreshFromBackend();
  }

  @override
  void dispose() {
    _book.removeListener(_onBookChanged);
    _form.dispose();
    super.dispose();
  }

  void _onBookChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Reads the pharmacist-built intake cards from Neon and folds them into the
  /// in-memory records — so a card that was "waiting on the pharmacist" fills
  /// in and expands. Runs on open and on pull-to-refresh. Best-effort.
  Future<void> _refreshFromBackend() async {
    final phone = AuthService.instance.currentUser.value?.phone;
    if (phone == null || _book.isEmpty) {
      return;
    }
    final cards = await PrescriptionRepository.instance.fetchForMember(phone);
    if (cards == null || !mounted) {
      return;
    }
    final byUuid = {for (final card in cards) card.uuid: card};
    for (final record in _book.records) {
      final card = byUuid[record.remoteId];
      if (card == null) {
        continue;
      }
      _book.applyIntakeCard(
        record.id,
        doctor: card.doctor,
        ordered: card.status == 'ORDERED' || card.status == 'READ',
        medicines: [
          for (final m in card.medicines)
            PrescriptionMedicine(
              name: m.name,
              pack: m.pack,
              intake: IntakePattern(
                morning: m.morning,
                afternoon: m.afternoon,
                night: m.night,
              ),
              totalUnits: m.totalUnits > 0 ? m.totalUnits : null,
            ),
        ],
      );
    }
  }

  void _submitInlineForm() {
    final record = _form.addTo(_book);
    setState(() {
      final spent = _form;
      _form = PrescriptionFormController();
      spent.dispose();
    });
    _say('${record.patient.name} · ${record.supplyLabel}');
    // Straight on to delivery — placing the order is what sends the script to
    // the pharmacy in the new flow.
    _proceedToCheckout();
  }

  Future<void> _addAnother() async {
    final record = await PrescriptionFormSheet.show(context, copy: _copy);
    if (record != null && mounted) {
      _say('${record.patient.name} · ${record.supplyLabel}');
    }
  }

  /// Opens delivery + place-order for every prescription that has not been
  /// ordered yet.
  Future<void> _proceedToCheckout() async {
    final pending = _unordered;
    if (pending.isEmpty) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrescriptionCheckoutScreen(records: pending),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _delete(PrescriptionRecord record) {
    final index = _book.indexOf(record.id);
    _book.remove(record.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_copy.prescriptionRemoved),
          action: SnackBarAction(
            label: _copy.undo,
            // Deleting a card takes the pharmacy's whole reading of it with
            // it, so the way back is offered rather than a confirmation
            // asked for.
            onPressed: () => _book.insert(index, record),
          ),
        ),
      );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final empty = _book.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Upload Prescription',
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
      body: empty ? _buildUploadForm() : _buildPrescriptionList(),
      bottomNavigationBar: empty
          ? _BottomBar(
              label: _copy.proceed,
              // Rebuilt as the form fills in, without the screen holding a
              // second copy of its state to know when.
              listenable: _form,
              enabled: () => _form.isComplete,
              onPressed: _submitInlineForm,
            )
          : _unordered.isNotEmpty
          ? _BottomBar(
              label: _copy.proceedToDelivery,
              icon: Icons.local_shipping_outlined,
              enabled: () => true,
              onPressed: _proceedToCheckout,
            )
          : _BottomBar(
              label: _copy.addNewPrescription,
              icon: Icons.add_rounded,
              filled: false,
              enabled: () => true,
              onPressed: _addAnother,
            ),
    );
  }

  Widget _buildUploadForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        _LanguageToggle(
          language: _language,
          onSelect: (language) => setState(() => _language = language),
        ),
        const SizedBox(height: 16),
        PrescriptionFormBody(controller: _form, copy: _copy),
        const SizedBox(height: 20),
        _OrderStepsBox(copy: _copy),
        const SizedBox(height: 22),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 22),
        _PharmacistCallCard(copy: _copy),
      ],
    );
  }

  Widget _buildPrescriptionList() {
    final records = _book.records;

    return RefreshIndicator(
      onRefresh: _refreshFromBackend,
      child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        _LanguageToggle(
          language: _language,
          onSelect: (language) => setState(() => _language = language),
        ),
        const SizedBox(height: 16),
        Text(
          _copy.yourPrescriptions,
          style: const TextStyle(
            fontSize: 18,
            height: 1.3,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _copy.yourPrescriptionsIntro,
          style: const TextStyle(
            fontSize: 14.5,
            height: 1.4,
            color: AppColors.textBody,
          ),
        ),
        const SizedBox(height: 18),
        for (final record in records)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: PrescriptionDetailCard(
              key: ValueKey(record.id),
              record: record,
              copy: _copy,
              onDelete: () => _delete(record),
            ),
          ),
        // Once something is uploaded the next question is where it goes, so
        // the delivery address sits with the prescriptions rather than being
        // asked for only at the very end.
        _DeliveryDetailsCard(copy: _copy),
        const SizedBox(height: 16),
        _PharmacistCallCard(copy: _copy),
      ],
      ),
    );
  }
}

/// Two-option switch between the languages the screen is written in.
///
/// Both options are labelled in their own script, so a reader who cannot read
/// the current one can still find their way out of it — which is the whole
/// point of a language switch and the one thing a flag or a globe icon
/// cannot do.
class _LanguageToggle extends StatelessWidget {
  final AppLanguage language;
  final ValueChanged<AppLanguage> onSelect;

  const _LanguageToggle({required this.language, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.pageTint,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 7),
              child: Icon(
                Icons.translate_rounded,
                size: 17,
                color: AppColors.brandBlue,
              ),
            ),
            for (final option in AppLanguage.values)
              _LanguageOption(
                option: option,
                isSelected: option == language,
                onTap: () => onSelect(option),
              ),
          ],
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final AppLanguage option;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: option.label,
      child: Material(
        color: isSelected ? AppColors.brandBlue : AppColors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            // The code is decoration; the accessible name is the language,
            // set on the Semantics above. Left in, the two merge and a reader
            // hears "English E N G".
            child: ExcludeSemantics(
              child: Text(
                option.code,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                  letterSpacing: 0.4,
                  color: isSelected ? AppColors.white : AppColors.textBody,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The ordering procedure, numbered, with a rule running between the steps.
///
/// It sits below the form rather than above it: someone who already knows the
/// flow should not have to scroll past an explanation to use it, and someone
/// who does not will read down to it.
class _OrderStepsBox extends StatelessWidget {
  final PrescriptionCopy copy;

  const _OrderStepsBox({required this.copy});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.howToOrder,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            copy.howToOrderIntro,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          for (var index = 0; index < copy.steps.length; index++)
            _OrderStepRow(
              number: index + 1,
              step: copy.steps[index],
              isLast: index == copy.steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _OrderStepRow extends StatelessWidget {
  final int number;
  final OrderStep step;
  final bool isLast;

  const _OrderStepRow({
    required this.number,
    required this.step,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.brandBlue,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                  ),
                ),
              ),
              // The thread joining one step to the next, so the column reads
              // as a sequence rather than as five separate notes.
              if (!isLast)
                const Expanded(
                  child: VerticalDivider(
                    width: 26,
                    thickness: 1.5,
                    color: AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 10 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.detail,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textBody,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PharmacistCallCard extends StatelessWidget {
  final PrescriptionCopy copy;

  const _PharmacistCallCard({required this.copy});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Color(0xFFF6D98C),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              size: 30,
              color: Color(0xFF6B4E12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.pharmacistTitle,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  copy.pharmacistDetail,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: AppColors.textBody,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.greenTint,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              copy.free,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.brandGreenDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a confirmed prescription order is sent.
///
/// Shown only once something has been uploaded — before that the screen is
/// still the upload form, and an address asked for there would be a field with
/// no order behind it. It reads the shared [AddressBook], so an address saved
/// here, at checkout, or from the location sheet is the same one everywhere.
class _DeliveryDetailsCard extends StatelessWidget {
  final PrescriptionCopy copy;

  const _DeliveryDetailsCard({required this.copy});

  Future<void> _edit(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddressFormScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AddressBook.instance,
      builder: (context, _) {
        final address = AddressBook.instance.deliverTo;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                  Expanded(
                    child: Text(
                      copy.deliveryDetails,
                      style: const TextStyle(
                        fontSize: 16.5,
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
                      child: Text(
                        copy.changeAddress,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandBlue,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                copy.deliveryDetailsIntro,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              if (address == null)
                OutlinedButton.icon(
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.add_location_alt_outlined, size: 20),
                  label: Text(copy.addDeliveryAddress),
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
                _AddressSummary(address: address),
            ],
          ),
        );
      },
    );
  }
}

class _AddressSummary extends StatelessWidget {
  final Address address;

  const _AddressSummary({required this.address});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pageTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
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
                  color: AppColors.offerTint,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  address.label.label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  address.receiver,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            address.summary,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textBody,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            address.phone,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// The one action bar at the foot of the screen: Proceed while the form is
/// being filled in, "Add new prescription" once the list has taken over.
class _BottomBar extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool filled;

  /// Rebuild trigger; null when the label's enablement cannot change.
  final Listenable? listenable;

  final bool Function() enabled;
  final VoidCallback onPressed;

  const _BottomBar({
    required this.label,
    this.icon,
    this.filled = true,
    this.listenable,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final trigger = listenable;
    if (trigger == null) {
      return _bar();
    }
    // Built inside the builder, not before it.
    //
    // This used to construct the bar once and hand that same widget back from
    // the builder on every notification. [enabled] was therefore read exactly
    // once — as the screen opened, with the form empty — and the disabled
    // button it produced was what every later rebuild returned. Proceed stayed
    // grey however much of the form was filled in, and no amount of notifying
    // from the controller could have changed it.
    return ListenableBuilder(listenable: trigger, builder: (_, _) => _bar());
  }

  Widget _bar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SizedBox(width: double.infinity, child: _button()),
        ),
      ),
    );
  }

  Widget _button() {
    final text = Text(
      label,
      style: TextStyle(
        fontSize: 16.5,
        fontWeight: FontWeight.w700,
        color: filled ? AppColors.white : AppColors.brandBlue,
      ),
    );
    final action = enabled() ? onPressed : null;

    if (!filled) {
      return OutlinedButton.icon(
        onPressed: action,
        icon: icon == null
            ? null
            : Icon(icon, size: 20, color: AppColors.brandBlue),
        label: text,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.brandBlue, width: 1.4),
          backgroundColor: AppColors.offerTint,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    return FilledButton(
      onPressed: action,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brandBlue,
        disabledBackgroundColor: AppColors.searchBorder,
        padding: const EdgeInsets.symmetric(vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: text,
    );
  }
}
