import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/backend/patient_repository.dart';
import '../../data/backend/prescription_repository.dart';
import '../../dates.dart';
import '../../theme/app_colors.dart';
import '../../widgets/upload_picker.dart';
import '../auth/auth_service.dart';
import '../location/address_book.dart';
import '../location/address_picker.dart';
import '../patients/patient_book.dart';
import '../patients/patient_picker.dart';
import 'medicine_duration.dart';
import 'prescription_copy.dart';
import 'prescription_image.dart';
import 'prescription_image_view.dart';
import 'prescription_record.dart';

/// Cap from the on-screen guidance.
const int kPrescriptionMaxBytes = 5 * 1024 * 1024;

/// Up to this many photos per prescription — a script is often more than
/// one page (front/back, or several pages of a longer prescription).
const int kPrescriptionMaxImages = 3;

/// One picked photo, before it is submitted: the file itself, its size, and
/// (when readable) the bytes the form shows a thumbnail and full-screen view
/// from.
class PickedPrescriptionImage {
  final XFile file;
  final int bytes;
  final Uint8List? preview;

  const PickedPrescriptionImage({
    required this.file,
    required this.bytes,
    this.preview,
  });

  bool get tooLarge => bytes > kPrescriptionMaxBytes;
}

/// Everything the upload form holds, kept apart from the widgets that draw it.
///
/// The same form is shown twice — inline on an empty screen, and inside the
/// sheet that "Add new prescription" opens — and the button that submits it
/// sits outside the form in both cases. A controller is what lets that button
/// ask whether the form is ready without the two copies drifting apart.
class PrescriptionFormController extends ChangeNotifier {
  /// Up to [kPrescriptionMaxImages] photos, in the order they were added —
  /// a script is often more than one page.
  final List<PickedPrescriptionImage> images = [];

  bool get canAddMoreImages => images.length < kPrescriptionMaxImages;

  bool busy = false;

  Patient? patient;

  /// Where this prescription's own order ships — see
  /// [PrescriptionRecord.address]'s own doc. Null until chosen; the checkout
  /// screen falls back to the shared [AddressBook.deliverTo] for a record
  /// left unset.
  Address? address;

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

  bool get anyTooLarge => images.any((image) => image.tooLarge);

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

  // Only who it is for is actually required — the pharmacist can read the
  // dispense quantity off the script itself, or off a call, so a member with
  // no photo to hand yet and no fixed idea of how much they need can still
  // send the prescription and have both filled in for them. Any file that
  // was picked still has to be under the size cap, and a recurring order
  // still needs a real schedule once switched on.
  bool get isComplete => !anyTooLarge && patient != null && hasSchedule;

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

  /// Appends a newly picked photo — a no-op past [kPrescriptionMaxImages],
  /// since the tiles that call this are hidden once the cap is reached.
  void addImage(XFile picked, int length, {Uint8List? preview}) {
    if (!canAddMoreImages) return;
    images.add(PickedPrescriptionImage(file: picked, bytes: length, preview: preview));
    notifyListeners();
  }

  void removeImageAt(int index) {
    if (index < 0 || index >= images.length) return;
    images.removeAt(index);
    notifyListeners();
  }

  void setPatient(Patient value) {
    patient = value;
    notifyListeners();
  }

  void setAddress(Address value) {
    address = value;
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
      // '' when no photo was attached — the pharmacist fills the script in
      // from the call instead. [PrescriptionDetailCard] shows a placeholder
      // for the empty case rather than a blank title line. Only the first
      // page's name is kept for that display purpose; every page is still
      // sent to the backend below.
      fileName: images.isEmpty ? '' : images.first.file.name,
      duration: isCustomDuration ? null : duration,
      customDays: isCustomDuration ? customDays : null,
      recurring: schedule,
      address: address,
    );
    unawaited(_persist(book, record));
    return record;
  }

  Future<void> _persist(
    PrescriptionBook book,
    PrescriptionRecord record,
  ) async {
    final user = AuthService.instance.currentUser.value;
    if (user == null) {
      return;
    }
    final patient = record.patient;
    // Every picked page, so the pharmacy console can read the whole script
    // and build the intake card from it. Try a small re-encoded JPEG first
    // per image; if the image package cannot decode one (an odd format, a
    // screenshot), fall back to its raw bytes as-is so the counter still
    // gets a picture.
    //
    // The whole per-image block is one try/catch, not just the encode call:
    // a script the pharmacy console never got to see (this exact bug,
    // reported live) traced back to nothing throwing loudly enough to show
    // up anywhere — the encode failed silently, and whatever ran after it
    // for that image never got a chance to fall back. Wrapping the entire
    // block means a failure anywhere in it — encode, mime lookup, the
    // fallback itself — still leaves the raw bytes as the very last resort
    // tried, and the one case that logs instead of quietly moving on is
    // when even *that* didn't produce anything, which is the only
    // genuinely inexplicable outcome left.
    final encodedImages = <String>[];
    final debugSteps = <String>['picked=${images.length}'];
    for (final picked in images) {
      final rawImage = picked.preview;
      if (rawImage == null) {
        debugSteps.add('${picked.file.name}: no preview bytes at all');
        debugPrint(
          'prescription: ${picked.file.name} has no bytes to encode at all '
          '— the picker never delivered a preview for it',
        );
        continue;
      }
      try {
        String? image;
        var how = 'encoded';
        try {
          image = await prescriptionImageDataUrl(rawImage);
        } catch (error) {
          debugPrint(
            'prescription: could not re-encode ${picked.file.name} — $error',
          );
        }
        // Always the fallback once the encode has nothing — kPrescriptionMaxBytes
        // already gated what could be picked in the first place (see
        // UploadPrescriptionScreen.maxBytes), so there is no smaller cap to
        // re-check here; re-checking it a second time with its own copy of
        // the constant is exactly the kind of two-sources-of-truth gap that
        // silently drops a page if they ever come apart.
        if (image == null || image.isEmpty) {
          how = 'fallback';
          image = 'data:${_mimeForName(picked.file.name)};base64,'
              '${base64Encode(rawImage)}';
        }
        if (image.isNotEmpty) {
          encodedImages.add(image);
          debugSteps.add(
            '${picked.file.name}: ${rawImage.length}B raw, $how, '
            '${image.length}B data-uri',
          );
        } else {
          debugSteps.add('${picked.file.name}: $how produced an empty string');
        }
      } catch (error) {
        debugSteps.add('${picked.file.name}: threw — $error');
        debugPrint(
          'prescription: ${picked.file.name} could not be attached by any '
          'means — $error',
        );
      }
    }
    debugSteps.add('sending images=${encodedImages.length}');
    book.setImageDebugNote(record.id, debugSteps.join(' | '));
    try {
      // The backend requires an existing patient id — resolve/create one
      // first (the old direct-Neon upload did this inline as part of the
      // same write; the backend has no equivalent "create the patient as
      // part of this upload" path).
      final patientId = await PatientRepository.instance.upsert(
        id: patient.remoteId,
        memberPhone: user.phone,
        memberName: user.name,
        name: patient.name,
        phone: patient.phone,
        address: patient.address,
        dob: patient.dob,
        gender: patient.gender,
        relation: patient.relation,
        abhaId: patient.abhaId,
      );
      if (patientId == null) {
        book.setImageDebugNote(
          record.id,
          '${debugSteps.join(' | ')} | patient upsert returned null, upload skipped',
        );
        return;
      }
      PatientBook.instance.attachRemoteId(patient.id, patientId);

      final id = await PrescriptionRepository.instance.insertUpload(
        patientId: int.parse(patientId),
        fileName: record.fileName,
        images: encodedImages,
        doctor: record.doctor,
        duration: record.duration,
        customDays: record.customDays,
        recurringFrom: record.recurring?.from,
        recurringUntil: record.recurring?.until,
      );
      if (id != null) {
        book.attachRemoteId(record.id, id);
        book.setImageDebugNote(
          record.id,
          '${debugSteps.join(' | ')} | insertUpload ok, id=$id',
        );
      } else {
        book.setImageDebugNote(
          record.id,
          '${debugSteps.join(' | ')} | insertUpload returned null',
        );
      }
    } catch (error, stack) {
      book.setImageDebugNote(
        record.id,
        '${debugSteps.join(' | ')} | threw before/during upload — $error',
      );
      debugPrint('prescription: could not save upload to database — $error');
      debugPrintStack(stackTrace: stack);
    }
  }
}

/// A best-effort MIME type from a picked file's name, for the raw-bytes
/// fallback data URI. Defaults to JPEG — most script photos are.
String _mimeForName(String name) {
  final ext = name.toLowerCase().split('.').last;
  return switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' || 'heif' => 'image/heic',
    'gif' => 'image/gif',
    _ => 'image/jpeg',
  };
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

  /// Opens one picked image full-screen so the member can check the page is
  /// readable before committing to it. Only offered once its bytes are to hand.
  void _viewImage(BuildContext context, int index) {
    final picked = _form.images[index];
    final data = picked.preview;
    if (data == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrescriptionImageView(bytes: data, name: picked.file.name),
      ),
    );
  }

  Future<void> _pick(ImageSource source) async {
    if (!_form.canAddMoreImages) {
      return;
    }
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
      _form.addImage(picked, data.length, preview: data);
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
            // Hidden once the cap is reached — there is nothing more to add.
            if (_form.canAddMoreImages) ...[
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
              const SizedBox(height: 8),
              Text(
                _form.images.isEmpty
                    ? copy.maxImagesNote(kPrescriptionMaxImages)
                    : copy.addAnotherImageNote(
                        kPrescriptionMaxImages - _form.images.length,
                      ),
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            if (_form.images.isEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OptionalTag(label: copy.optionalTag),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      copy.photoOptionalNote,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            for (var i = 0; i < _form.images.length; i++) ...[
              const SizedBox(height: 18),
              UploadedFileCard(
                name: _form.images[i].file.name,
                bytes: _form.images[i].bytes,
                tooLarge: _form.images[i].tooLarge,
                limitLabel: '5 MB',
                removeLabel: copy.remove,
                onRemove: () => _form.removeImageAt(i),
                previewBytes: _form.images[i].preview,
                viewLabel: copy.viewFile,
                onView: _form.images[i].preview == null
                    ? null
                    : () => _viewImage(context, i),
              ),
            ],
            const SizedBox(height: 18),
            PatientPicker(
              selected: _form.patient,
              label: copy.patientLabel,
              hint: copy.patientHint,
              onSelect: _form.setPatient,
            ),
            const SizedBox(height: 12),
            // Optional here — a record left without one falls back to the
            // shared delivery address at checkout (see
            // PrescriptionRecord.address's own doc). Only worth answering
            // explicitly when this prescription (of possibly several being
            // uploaded together) needs to ship somewhere different.
            AddressPicker(
              selected: _form.address,
              onSelect: _form.setAddress,
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

/// A small neutral pill marking a section of the form as not required —
/// shared by the two sections a member can skip and still send the
/// prescription: the photo and how much to dispense.
class _OptionalTag extends StatelessWidget {
  final String label;

  const _OptionalTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.chipSlateTint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                copy.durationHeading,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _OptionalTag(label: copy.optionalTag),
          ],
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
