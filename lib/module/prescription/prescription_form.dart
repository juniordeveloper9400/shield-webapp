import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/neon/prescription_repository.dart';
import '../../dates.dart';
import '../../theme/app_colors.dart';
import '../../widgets/upload_picker.dart';
import '../auth/auth_service.dart';
import '../location/address_book.dart';
import '../patients/patient_book.dart';
import '../patients/patient_picker.dart';
import '../registration/registration_service.dart';
import '../registration/shield_store.dart';
import 'medicine_duration.dart';
import 'prescription_copy.dart';
import 'prescription_image.dart';
import 'prescription_image_view.dart';
import 'prescription_record.dart';

/// Cap from the on-screen guidance.
const int kPrescriptionMaxBytes = 5 * 1024 * 1024;

/// Everything the upload form holds, kept apart from the widgets that draw it.
///
/// The same form is shown twice — inline on an empty screen, and inside the
/// sheet that "Add new prescription" opens — and the button that submits it
/// sits outside the form in both cases. A controller is what lets that button
/// ask whether the form is ready without the two copies drifting apart.
class PrescriptionFormController extends ChangeNotifier {
  XFile? file;
  int bytes = 0;

  /// The picked image's bytes, held so the form can show a thumbnail and open
  /// a full-screen view before the file is ever submitted. Null when the pick
  /// came from a path the form could not read (a bare test double, say).
  Uint8List? preview;

  bool busy = false;

  Patient? patient;

  MedicineDuration? duration;
  bool isCustomDuration = false;
  int? customDays;

  bool isRecurring = false;
  DateTime from = _today();
  DateTime? until;
  bool neverExpires = false;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get tooLarge => bytes > kPrescriptionMaxBytes;

  bool get hasDuration => isCustomDuration
      ? (customDays != null && customDays! > 0)
      : duration != null;

  /// A repeat with no end and no tick saying so is not a decision yet — it is
  /// a blank field, and it would silently become a one-off order.
  bool get hasSchedule =>
      !isRecurring || neverExpires || (until != null && until!.isAfter(from));

  /// True once the due date has been set to a day that is not after the
  /// start: worth saying out loud, where a merely unset date is not.
  bool get dueDateIsBackwards =>
      isRecurring && !neverExpires && until != null && !until!.isAfter(from);

  // A prescription that does not say who it is for, or how much to dispense,
  // cannot be filled. Both are as required as the file itself.
  bool get isComplete =>
      file != null &&
      !tooLarge &&
      patient != null &&
      hasDuration &&
      hasSchedule;

  String get supplyLabel {
    if (isCustomDuration && customDays != null && customDays! > 0) {
      return "$customDays days · $customDays days' supply";
    }
    return duration?.supplyLabel ?? '';
  }

  RecurringSchedule? get schedule => isRecurring
      ? RecurringSchedule(from: from, until: neverExpires ? null : until)
      : null;

  void setBusy(bool value) {
    busy = value;
    notifyListeners();
  }

  void setFile(XFile picked, int length, {Uint8List? preview}) {
    file = picked;
    bytes = length;
    this.preview = preview;
    notifyListeners();
  }

  void clearFile() {
    file = null;
    bytes = 0;
    preview = null;
    notifyListeners();
  }

  void setPatient(Patient value) {
    patient = value;
    notifyListeners();
  }

  void selectPreset(MedicineDuration value) {
    duration = value;
    isCustomDuration = false;
    notifyListeners();
  }

  void selectCustomDuration() {
    isCustomDuration = true;
    notifyListeners();
  }

  void setCustomDays(int? days) {
    customDays = days;
    notifyListeners();
  }

  void setRecurring(bool value) {
    isRecurring = value;
    notifyListeners();
  }

  void setFrom(DateTime value) {
    from = value;
    notifyListeners();
  }

  void setUntil(DateTime? value) {
    until = value;
    notifyListeners();
  }

  void setNeverExpires(bool value) {
    neverExpires = value;
    notifyListeners();
  }

  /// Files the finished form and returns the stored record.
  ///
  /// [PrescriptionBook] is the in-memory source of truth the screens listen
  /// to; the record is also written through to `app.prescription` on Neon in
  /// the background. A failed or unconfigured database write is logged, never
  /// thrown — an upload is an offer, not a gate.
  PrescriptionRecord addTo(PrescriptionBook book) {
    final record = book.add(
      patient: patient!,
      fileName: file!.name,
      duration: isCustomDuration ? null : duration,
      customDays: isCustomDuration ? customDays : null,
      recurring: schedule,
    );
    unawaited(_persist(book, record));
    return record;
  }

  Future<void> _persist(PrescriptionBook book, PrescriptionRecord record) async {
    final user = AuthService.instance.currentUser.value;
    if (user == null) {
      return;
    }
    final patient = record.patient;
    // A readable, collision-safe code for a row that outlives the session
    // counter behind [PrescriptionRecord.number].
    final code = 'RX-'
        '${DateTime.now().millisecondsSinceEpoch.remainder(100000000).toString().padLeft(8, '0')}';
    // The script itself, resized small, so the pharmacy console can read it
    // and build the intake card from it. Best-effort — a photo that will not
    // decode just leaves the row without an image.
    String? image;
    final rawImage = preview;
    if (rawImage != null) {
      try {
        image = await prescriptionImageDataUrl(rawImage);
      } catch (error) {
        debugPrint('prescription: could not encode the script image — $error');
      }
    }
    try {
      final uuid = await PrescriptionRepository.instance.insertUpload(
        memberPhone: user.phone,
        memberName: user.name,
        patientUuid: patient.remoteId,
        patientName: patient.name,
        patientPhone: patient.phone,
        patientAddress: patient.address,
        patientDob: patient.dob,
        patientGender: patient.gender,
        patientRelation: patient.relation,
        patientAbhaId: patient.abhaId,
        code: code,
        fileName: record.fileName,
        image: image,
        storeCode: _uploadStoreCode(),
        doctor: record.doctor,
        duration: record.duration,
        customDays: record.customDays,
        recurringFrom: record.recurring?.from,
        recurringUntil: record.recurring?.until,
        medicines: record.medicines,
      );
      if (uuid != null) {
        book.attachRemoteId(record.id, uuid);
      }
    } catch (error, stack) {
      debugPrint('prescription: could not save upload to database — $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  /// The branch the script is filled at: the store on the account, else the
  /// branch nearest the delivery address, else the top of the directory — the
  /// same order the prescription checkout resolves its store in, so the
  /// upload and the eventual order name the same branch.
  static String _uploadStoreCode() {
    final registered = RegistrationService.instance.profile?.store;
    if (registered != null) {
      return registered.id;
    }
    final pincode = AddressBook.instance.deliverTo?.pincode;
    final nearby = pincode != null ? StoreDirectory.suggestFor(pincode) : null;
    return (nearby ?? StoreDirectory.all.first).id;
  }
}

/// The upload form itself: where the file comes from, who it is for, how much
/// to dispense, and whether it repeats.
///
/// Draws no submit button of its own — the screen puts one in its bottom bar
/// and the sheet puts one under its own scroll view.
class PrescriptionFormBody extends StatefulWidget {
  final PrescriptionFormController controller;
  final PrescriptionCopy copy;

  /// Off inside the sheet, which titles itself.
  final bool showHeading;

  const PrescriptionFormBody({
    super.key,
    required this.controller,
    required this.copy,
    this.showHeading = true,
  });

  @override
  State<PrescriptionFormBody> createState() => _PrescriptionFormBodyState();
}

class _PrescriptionFormBodyState extends State<PrescriptionFormBody> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _customDaysController = TextEditingController();

  PrescriptionFormController get _form => widget.controller;

  @override
  void initState() {
    super.initState();
    final days = _form.customDays;
    if (days != null) {
      _customDaysController.text = '$days';
    }
  }

  @override
  void dispose() {
    _customDaysController.dispose();
    super.dispose();
  }

  /// Opens the picked image full-screen so the member can check the page is
  /// readable before committing to it. Only offered once its bytes are to hand.
  void _viewFile(BuildContext context) {
    final data = _form.preview;
    final picked = _form.file;
    if (data == null || picked == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrescriptionImageView(bytes: data, name: picked.name),
      ),
    );
  }

  Future<void> _pick(ImageSource source) async {
    _form.setBusy(true);
    try {
      final picked = await _picker.pickImage(source: source);
      if (picked == null) {
        return;
      }
      // Read the bytes once, here: they give both the size the card shows and
      // the thumbnail — and the full-screen view — it now offers.
      final data = await picked.readAsBytes();
      if (!mounted) {
        return;
      }
      _form.setFile(picked, data.length, preview: data);
    } on Exception {
      if (!mounted) {
        return;
      }
      // A browser with no camera, or a denied permission, throws here.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source == ImageSource.camera
                ? 'Camera is not available on this device'
                : 'Could not open the gallery',
          ),
        ),
      );
    } finally {
      if (mounted) {
        _form.setBusy(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.copy;

    return ListenableBuilder(
      listenable: _form,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showHeading) ...[
              Text(
                copy.heading,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                copy.intro,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: AppColors.textBody,
                ),
              ),
              const SizedBox(height: 20),
            ],
            // IntrinsicHeight + stretch keeps both tiles the same height as
            // the taller of the two, without either reserving extra space.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  UploadSourceTile(
                    icon: Icons.add_a_photo_outlined,
                    label: copy.useCamera,
                    enabled: !_form.busy,
                    onTap: () => _pick(ImageSource.camera),
                  ),
                  const SizedBox(width: 14),
                  UploadSourceTile(
                    icon: Icons.add_photo_alternate_outlined,
                    label: copy.useGallery,
                    enabled: !_form.busy,
                    onTap: () => _pick(ImageSource.gallery),
                  ),
                ],
              ),
            ),
            if (_form.file != null) ...[
              const SizedBox(height: 18),
              UploadedFileCard(
                name: _form.file!.name,
                bytes: _form.bytes,
                tooLarge: _form.tooLarge,
                limitLabel: '5 MB',
                removeLabel: copy.remove,
                onRemove: _form.clearFile,
                previewBytes: _form.preview,
                viewLabel: copy.viewFile,
                onView: _form.preview == null ? null : () => _viewFile(context),
              ),
            ],
            const SizedBox(height: 18),
            PatientPicker(
              selected: _form.patient,
              label: copy.patientLabel,
              hint: copy.patientHint,
              onSelect: _form.setPatient,
            ),
            const SizedBox(height: 20),
            _DurationPicker(
              copy: copy,
              selected: _form.duration,
              isCustom: _form.isCustomDuration,
              customController: _customDaysController,
              onSelectPreset: _form.selectPreset,
              onSelectCustom: _form.selectCustomDuration,
              onCustomDaysChanged: (value) =>
                  _form.setCustomDays(int.tryParse(value.trim())),
            ),
            const SizedBox(height: 20),
            RecurringPicker(copy: copy, form: _form),
            const SizedBox(height: 20),
            _GuidanceBox(copy: copy),
          ],
        );
      },
    );
  }
}

/// Whether the prescription repeats, and for how long.
///
/// The two dates only appear once the repeat is switched on: a one-off order
/// has no start and no end, and showing empty date rows next to it would read
/// as two more fields left blank.
class RecurringPicker extends StatelessWidget {
  final PrescriptionCopy copy;
  final PrescriptionFormController form;

  const RecurringPicker({super.key, required this.copy, required this.form});

  Future<void> _pickFrom(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: form.from,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      helpText: copy.fromDate,
    );
    if (picked != null) {
      form.setFrom(picked);
    }
  }

  Future<void> _pickUntil(BuildContext context) async {
    final start = form.from;
    final picked = await showDatePicker(
      context: context,
      initialDate: form.until ?? start.add(const Duration(days: 30)),
      // A repeat cannot end before it starts, so that day is the floor.
      firstDate: start.add(const Duration(days: 1)),
      lastDate: DateTime(start.year + 5, 12, 31),
      helpText: copy.dueDate,
    );
    if (picked != null) {
      form.setUntil(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: form.isRecurring ? AppColors.brandBlue : AppColors.border,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.recurringHeading,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      copy.recurringIntro,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: AppColors.textBody,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: copy.recurringToggle,
                child: Switch(
                  value: form.isRecurring,
                  onChanged: form.setRecurring,
                  activeThumbColor: AppColors.white,
                  activeTrackColor: AppColors.brandBlue,
                ),
              ),
            ],
          ),
          if (form.isRecurring) ...[
            const SizedBox(height: 12),
            _DateRow(
              label: copy.fromDate,
              value: formatDate(form.from),
              onTap: () => _pickFrom(context),
            ),
            const SizedBox(height: 10),
            _DateRow(
              label: copy.dueDate,
              value: form.neverExpires
                  ? copy.neverExpires
                  : (form.until == null ? null : formatDate(form.until!)),
              hint: copy.selectDate,
              // Ticked "never expires", there is no date to change; the row
              // stays on screen so the state it is in is still readable.
              onTap: form.neverExpires ? null : () => _pickUntil(context),
            ),
            if (form.dueDateIsBackwards)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 6),
                child: Text(
                  copy.dueBeforeFrom,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.danger,
                  ),
                ),
              ),
            const SizedBox(height: 2),
            InkWell(
              onTap: () => form.setNeverExpires(!form.neverExpires),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Checkbox(
                      value: form.neverExpires,
                      onChanged: (value) =>
                          form.setNeverExpires(value ?? false),
                      activeColor: AppColors.brandBlue,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      copy.neverExpires,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textBody,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;

  /// Null when nothing has been chosen, which is what draws the placeholder.
  final String? value;
  final String? hint;
  final VoidCallback? onTap;

  const _DateRow({
    required this.label,
    required this.value,
    this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chosen = value != null;
    final disabled = onTap == null;

    return Semantics(
      button: !disabled,
      label: '$label, ${value ?? hint ?? ''}',
      child: Material(
        color: disabled ? AppColors.pageTint : AppColors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: chosen ? AppColors.searchBorder : AppColors.border,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  size: 19,
                  color: disabled ? AppColors.textMuted : AppColors.brandBlue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Text(
                  value ?? hint ?? '',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: chosen ? FontWeight.w700 : FontWeight.w500,
                    color: chosen ? AppColors.textDark : AppColors.textMuted,
                  ),
                ),
                if (!disabled) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuidanceBox extends StatelessWidget {
  final PrescriptionCopy copy;

  const _GuidanceBox({required this.copy});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pageTint,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 19,
                color: AppColors.brandBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  copy.keepInMind,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final point in copy.rules)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: AppColors.textBody,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      point,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.4,
                        color: AppColors.textBody,
                      ),
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

/// How long a supply the prescription should be filled for.
class _DurationPicker extends StatelessWidget {
  final PrescriptionCopy copy;
  final MedicineDuration? selected;
  final bool isCustom;
  final TextEditingController customController;
  final ValueChanged<MedicineDuration> onSelectPreset;
  final VoidCallback onSelectCustom;
  final ValueChanged<String> onCustomDaysChanged;

  const _DurationPicker({
    required this.copy,
    required this.selected,
    required this.isCustom,
    required this.customController,
    required this.onSelectPreset,
    required this.onSelectCustom,
    required this.onCustomDaysChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          copy.durationHeading,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          copy.durationIntro,
          style: const TextStyle(
            fontSize: 13,
            height: 1.35,
            color: AppColors.textBody,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final duration in MedicineDuration.values)
              _DurationChip(
                label: duration.label,
                isSelected: !isCustom && duration == selected,
                onTap: () => onSelectPreset(duration),
              ),
            _DurationChip(
              label: copy.customDays,
              icon: Icons.edit_calendar_outlined,
              isSelected: isCustom,
              onTap: onSelectCustom,
            ),
          ],
        ),
        if (isCustom) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.pageTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.customDaysHint,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: customController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  onChanged: onCustomDaysChanged,
                  decoration: InputDecoration(
                    hintText: 'e.g. 45',
                    filled: true,
                    fillColor: AppColors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    suffixText: 'days',
                    suffixStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppColors.searchBorder,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppColors.brandBlue,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DurationChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _DurationChip({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? AppColors.offerTint : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.brandBlue : AppColors.searchBorder,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppColors.brandBlue : AppColors.textBody,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.brandBlue : AppColors.textBody,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
