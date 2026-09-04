import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../theme/app_colors.dart';
import 'address_book.dart';
import 'address_fields.dart';
import 'device_location.dart';

/// "Add address details" — search or pincode, the address lines, a label, and
/// receiver details, saved from a pinned bottom action.
class AddressFormScreen extends StatefulWidget {
  const AddressFormScreen({super.key});

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _search = TextEditingController();
  final _pincode = TextEditingController();
  final _house = TextEditingController();
  final _area = TextEditingController();
  final _landmark = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();

  AddressLabel _label = AddressLabel.home;
  bool _locating = false;

  @override
  void dispose() {
    _search.dispose();
    _pincode.dispose();
    _house.dispose();
    _area.dispose();
    _landmark.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final address = Address(
      pincode: _pincode.text.trim(),
      house: _house.text.trim(),
      area: _area.text.trim(),
      landmark: _landmark.text.trim(),
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      phone: _phone.text.trim(),
      label: _label,
    );
    AddressBook.instance.add(address);

    Navigator.of(context).pop(address);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${_label.label} address saved')));
  }

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

    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Add address details',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            _SearchBox(controller: _search),
            const SizedBox(height: 16),
            const _OrDivider(),
            const SizedBox(height: 16),
            Row(
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
            const SizedBox(height: 14),
            AddressLineField(
              hint: 'House no / Floor / Building',
              controller: _house,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            AddressLineField(
              hint: 'Area / Locality',
              controller: _area,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            AddressLineField(
              hint: 'Landmark (Optional)',
              controller: _landmark,
            ),
            const SizedBox(height: 18),
            AddressLabelChips(
              selected: _label,
              onSelect: (label) => setState(() => _label = label),
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 16),
            const Text(
              'Receiver details',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _LabelledField(
                    label: 'First name',
                    controller: _firstName,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LabelledField(
                    label: 'Last name',
                    controller: _lastName,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _LabelledField(
              label: 'Mobile Number',
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.length != 10) {
                  return 'Enter a valid 10-digit number';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            const Text(
              "We'll share delivery related updates on this number",
              style: TextStyle(fontSize: 13.5, color: AppColors.textBody),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _SaveBar(onSave: _save),
    );
  }
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;

  const _SearchBox({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Search by building, area or pincode',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 15.5),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 22,
          color: AppColors.brandBlue,
        ),
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.brandBlue.withValues(alpha: 0.45),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.border)),
      ],
    );
  }
}

/// Floating-label field used for the receiver block.
class _LabelledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _LabelledField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      ),
      decoration: InputDecoration(
        labelText: label,
        // Always floated, so the label reads as a caption above the value.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFB4322F)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFB4322F), width: 1.4),
        ),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  final VoidCallback onSave;

  const _SaveBar({required this.onSave});

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
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Save',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
