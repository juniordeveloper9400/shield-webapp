import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/neon/patient_repository.dart';
import '../../dates.dart';
import '../../theme/app_colors.dart';
import '../../widgets/age_badge.dart';
import '../auth/auth_service.dart';
import '../location/address_book.dart';
import '../location/address_fields.dart';
import '../location/device_location.dart';
import 'patient_book.dart';

/// Add or edit a patient.
///
/// One sheet for both: the only difference is whether the fields open filled
/// in, which keeps the validation rules from being written twice.
class PatientFormSheet extends StatefulWidget {
  /// Null when adding.
  final Patient? existing;

  const PatientFormSheet({super.key, this.existing});

  /// Returns the saved patient, or null when dismissed.
  static Future<Patient?> show(BuildContext context, {Patient? existing}) {
    return showModalBottomSheet<Patient>(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => PatientFormSheet(existing: existing),
    );
  }

  /// Oldest age the form accepts, and so how far back the date picker opens.
  /// Beyond this the entry is almost certainly a typo rather than a person.
  static const int maxAge = 120;

  /// Digits in an ABHA number.
  static const int abhaLength = 14;

  @override
  State<PatientFormSheet> createState() => _PatientFormSheetState();
}

class _PatientFormSheetState extends State<PatientFormSheet> {
  final _formKey = GlobalKey<FormState>();

  /// The address already on file for this patient, when editing one who has
  /// been through this form before — the address section opens filled in
  /// from this rather than from anything on [Patient] itself, which only
  /// ever carries a one-line summary of it.
  late final Address? _existingAddress = widget.existing == null
      ? null
      : AddressBook.instance.forPatient(widget.existing!.id);

  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.existing?.phone ?? '',
  );

  /// Filled by the picker only — see the field below.
  late final TextEditingController _dobText = TextEditingController(
    text: widget.existing == null ? '' : formatDate(widget.existing!.dob),
  );

  late final TextEditingController _abha = TextEditingController(
    text: widget.existing == null ? '' : widget.existing!.abhaLabel,
  );

  // ---- Address details — the section at the foot of the form ----

  late final TextEditingController _pincode = TextEditingController(
    text: _existingAddress?.pincode ?? '',
  );
  late final TextEditingController _house = TextEditingController(
    text: _existingAddress?.house ?? '',
  );
  late final TextEditingController _area = TextEditingController(
    text: _existingAddress?.area ?? '',
  );
  late final TextEditingController _landmark = TextEditingController(
    text: _existingAddress?.landmark ?? '',
  );
  late AddressLabel _addressLabel = _existingAddress?.label ?? AddressLabel.home;

  // ---- Receiver details — who actually takes the delivery, which is not
  // always the patient themselves (a child's parent, say). ----

  late final TextEditingController _receiverFirst = TextEditingController(
    text: _existingAddress?.firstName ?? '',
  );
  late final TextEditingController _receiverLast = TextEditingController(
    text: _existingAddress?.lastName ?? '',
  );
  late final TextEditingController _receiverPhone = TextEditingController(
    text: _existingAddress?.phone ?? '',
  );

  late DateTime? _dob = widget.existing?.dob;
  late PatientGender _gender = widget.existing?.gender ?? PatientGender.male;
  late PatientRelation _relation =
      widget.existing?.relation ?? PatientRelation.self;

  /// Set on the first refused save, so the date — which has no validator of
  /// its own — reports alongside the fields that do.
  bool _submitted = false;
  bool _locating = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _dobText.dispose();
    _abha.dispose();
    _pincode.dispose();
    _house.dispose();
    _area.dispose();
    _landmark.dispose();
    _receiverFirst.dispose();
    _receiverLast.dispose();
    _receiverPhone.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - PatientFormSheet.maxAge),
      lastDate: now,
      helpText: 'Date of birth',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.brandBlue,
            onPrimary: AppColors.white,
            onSurface: AppColors.textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _dob = picked;
        _dobText.text = formatDate(picked);
      });
    }
  }

  /// Fills the pincode (and locality, when it is still blank) from the
  /// device's current position — the same flow as the standalone address form.
  Future<void> _useCurrentLocation() async {
    if (_locating) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _locating = true);
    final result = await DeviceLocation.current();
    if (!mounted) {
      return;
    }
    setState(() => _locating = false);

    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (!result.ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(DeviceLocation.message(result.outcome)),
          action: switch (result.outcome) {
            DeviceLocationOutcome.deniedForever => SnackBarAction(
                label: 'Settings',
                onPressed: Geolocator.openAppSettings,
              ),
            DeviceLocationOutcome.serviceOff => SnackBarAction(
                label: 'Settings',
                onPressed: Geolocator.openLocationSettings,
              ),
            _ => null,
          },
        ),
      );
      return;
    }

    final place = result.place!;
    setState(() {
      if (place.hasPincode) {
        _pincode.text = place.pincode;
      }
      if (_area.text.trim().isEmpty && place.areaLine.isNotEmpty) {
        _area.text = place.areaLine;
      }
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          place.hasPincode
              ? 'Location set${place.city.isNotEmpty ? ' — ${place.city}' : ''} '
                    '(${place.pincode})'
              : 'Got your location — add the pincode to finish',
        ),
      ),
    );
  }

  void _save() {
    setState(() => _submitted = true);
    final dob = _dob;
    if (!_formKey.currentState!.validate() || dob == null) {
      return;
    }

    final book = PatientBook.instance;
    final abha = _abha.text.replaceAll(RegExp(r'\D'), '');
    final existing = widget.existing;

    // Built without a patient id yet — [summary] does not need one, and the
    // id a new patient gets is not known until [book.add] returns below.
    //
    // The receiver is its own set of fields rather than the patient's own
    // name and number — whoever answers the door for a child's delivery is
    // not the patient themselves.
    Address addressFor(String patientId) => Address(
      pincode: _pincode.text.trim(),
      house: _house.text.trim(),
      area: _area.text.trim(),
      landmark: _landmark.text.trim(),
      firstName: _receiverFirst.text.trim(),
      lastName: _receiverLast.text.trim(),
      phone: _receiverPhone.text.trim(),
      label: _addressLabel,
      patientId: patientId,
    );
    final addressSummary = addressFor('').summary;

    final saved = existing == null
        ? book.add(
            name: _name.text,
            phone: _phone.text,
            address: addressSummary,
            dob: dob,
            gender: _gender,
            abhaId: abha,
            relation: _relation,
          )
        : existing.copyWith(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            address: addressSummary,
            dob: dob,
            gender: _gender,
            abhaId: abha,
            relation: _relation,
          );

    if (existing != null) {
      book.update(saved);
    }
    // The address section is the same information under a different id now
    // that [saved] exists — replaces whatever this patient had on file
    // rather than adding a second entry for them.
    AddressBook.instance.upsertForPatient(saved.id, addressFor(saved.id));

    // Write the patient through to `app.patient` on the backend. Fire and
    // forget: [PatientBook] is what the app reads, the call no-ops when the
    // build has no database, and the sheet must close now rather than wait on
    // a round trip. The returned row uuid is pinned back onto the record so a
    // later edit or removal updates the same row.
    _persist(saved);

    Navigator.of(context).pop(saved);
  }

  /// Best-effort durable copy of [saved]. Skipped when signed out — there is no
  /// account to hang the patient off — and silently on any database error.
  void _persist(Patient saved) {
    final account = AuthService.instance.currentUser.value;
    if (account == null) {
      return;
    }
    unawaited(
      PatientRepository.instance
          .upsert(
            uuid: saved.remoteId,
            memberPhone: account.phone,
            memberName: account.name,
            name: saved.name,
            phone: saved.phone,
            address: saved.address,
            dob: saved.dob,
            gender: saved.gender,
            relation: saved.relation,
            abhaId: saved.abhaId,
          )
          .then((uuid) {
            if (uuid != null && uuid != saved.remoteId) {
              PatientBook.instance.attachRemoteId(saved.id, uuid);
            }
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lifts the fields clear of the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.existing == null
                              ? 'Add patient'
                              : 'Edit patient',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.textDark,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: _decoration('Full name'),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: _decoration('Mobile number', prefix: '+91  '),
                    // The same national rule sign-in uses, so a number the app
                    // accepts in one place cannot be refused in another.
                    validator: AuthService.validatePhone,
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextFormField(
                    controller: _dobText,
                    // Read-only and opening the picker: a typed date invites
                    // every format under the sun, and the age is derived from
                    // this rather than asked for, so it has to be exact.
                    readOnly: true,
                    onTap: _pickDob,
                    decoration: _decoration(
                      'Date of birth',
                      hint: 'Select a date',
                      // The age rides in the field itself: it is derived from
                      // the date the moment one is picked, never asked for.
                      suffix: DobFieldSuffix(dob: _dob),
                      error: _submitted && _dob == null
                          ? 'Select a date of birth'
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const _FieldLabel('Gender'),
                _ChipRow<PatientGender>(
                  values: PatientGender.values,
                  selected: _gender,
                  labelOf: (value) => value.label,
                  onSelect: (value) => setState(() => _gender = value),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextFormField(
                    controller: _abha,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [AbhaNumberFormatter()],
                    decoration: _decoration(
                      'ABHA ID',
                      hint: '12-3456-7890-1234',
                      helper:
                          'Optional \u00b7 your Ayushman Bharat health account',
                    ),
                    validator: (value) {
                      final digits = (value ?? '').replaceAll(
                        RegExp(r'\D'),
                        '',
                      );
                      // Blank is a valid answer; a half-typed number is not.
                      if (digits.isEmpty ||
                          digits.length == PatientFormSheet.abhaLength) {
                        return null;
                      }
                      return 'Enter all ${PatientFormSheet.abhaLength} digits, '
                          'or leave it blank';
                    },
                  ),
                ),
                const SizedBox(height: 18),
                const _FieldLabel('Relation'),
                _ChipRow<PatientRelation>(
                  values: PatientRelation.values,
                  selected: _relation,
                  labelOf: (value) => value.label,
                  onSelect: (value) => setState(() => _relation = value),
                ),
                const SizedBox(height: 22),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Divider(height: 1, color: AppColors.border),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Text(
                    'Address details',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  // Pincode and "Current Location" side by side, the same row
                  // the standalone address form opens with.
                  child: Row(
                    children: [
                      Expanded(
                        child: AddressLineField(
                          hint: 'Pincode',
                          controller: _pincode,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.length != 6) {
                              return 'Enter a 6-digit pincode';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CurrentLocationButton(
                          onTap: _useCurrentLocation,
                          loading: _locating,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AddressLineField(
                    hint: 'House no / Floor / Building',
                    controller: _house,
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AddressLineField(
                    hint: 'Area / Locality',
                    controller: _area,
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AddressLineField(
                    hint: 'Landmark (Optional)',
                    controller: _landmark,
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AddressLabelChips(
                    selected: _addressLabel,
                    onSelect: (value) => setState(() => _addressLabel = value),
                  ),
                ),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Divider(height: 1, color: AppColors.border),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Text(
                    'Receiver details',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _receiverFirst,
                          textCapitalization: TextCapitalization.words,
                          decoration: _decoration('First name'),
                          validator: (value) =>
                              (value ?? '').trim().isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _receiverLast,
                          textCapitalization: TextCapitalization.words,
                          decoration: _decoration('Last name'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextFormField(
                    controller: _receiverPhone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: _decoration('Mobile Number'),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      return text.length == 10
                          ? null
                          : 'Enter a valid 10-digit number';
                    },
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    "We'll share delivery related updates on this number",
                    style: TextStyle(fontSize: 13.5, color: AppColors.textBody),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Save patient',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(
    String label, {
    String? hint,
    String? helper,
    String? prefix,
    Widget? suffix,
    String? error,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      prefixText: prefix,
      suffixIcon: suffix,
      errorText: error,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.searchBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.6),
      ),
    );
  }
}

/// Groups an ABHA number as it is typed: 12-3456-7890-1234.
///
/// The caret is parked at the end after every edit. Preserving its position
/// through a reflow means mapping it across inserted dashes, which for a
/// 14-digit identifier that is almost always typed straight through is more
/// machinery than the case is worth.
class AbhaNumberFormatter extends TextInputFormatter {
  const AbhaNumberFormatter();

  static const List<int> _groups = [2, 4, 4, 4];

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > PatientFormSheet.abhaLength
        ? digits.substring(0, PatientFormSheet.abhaLength)
        : digits;

    final parts = <String>[];
    var index = 0;
    for (final size in _groups) {
      if (index >= capped.length) {
        break;
      }
      final end = index + size > capped.length ? capped.length : index + size;
      parts.add(capped.substring(index, end));
      index = end;
    }

    final text = parts.join('-');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _ChipRow<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelect;

  const _ChipRow({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      // Wrap rather than Row: five relations do not fit one line at 320px.
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final value in values)
            _Chip(
              label: labelOf(value),
              isSelected: value == selected,
              onTap: () => onSelect(value),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.brandBlue : AppColors.textBody,
          ),
        ),
      ),
    );
  }
}
