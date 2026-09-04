import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../theme/app_colors.dart';
import 'address_book.dart';
import 'address_form_screen.dart';
import 'device_location.dart';

/// Bottom sheet for choosing the delivery location.
///
/// Returns the chosen pincode, or null when dismissed without a change.
class LocationSheet extends StatefulWidget {
  final String currentPincode;

  const LocationSheet({super.key, required this.currentPincode});

  static Future<String?> show(BuildContext context, String currentPincode) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.white,
      // Scroll-controlled so the sheet can lift clear of the keyboard.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => LocationSheet(currentPincode: currentPincode),
    );
  }

  /// Pincodes the app can name a city for. Anything else is shown as-is.
  ///
  /// [AddressBook] holds the data, since it also owns the delivery location
  /// these describe. Kept here because callers reach for it through the sheet.
  static const Map<String, String> knownCities = AddressBook.knownCities;

  /// "400079, Mumbai" when the city is known, otherwise just the pincode.
  static String describe(String pincode) =>
      AddressBook.describePincode(pincode);

  @override
  State<LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<LocationSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentPincode,
  );
  String? _error;
  bool _locating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.length != 6 || int.tryParse(value) == null) {
      setState(() => _error = 'Enter a valid 6-digit pincode');
      return;
    }
    Navigator.of(context).pop(value);
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) {
      return;
    }
    setState(() {
      _locating = true;
      _error = null;
    });
    final result = await DeviceLocation.current();
    if (!mounted) {
      return;
    }

    if (result.ok && result.place!.hasPincode) {
      Navigator.of(context).pop(result.place!.pincode);
      return;
    }

    setState(() => _locating = false);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? 'Found your location but not its pincode — enter it above.'
              : DeviceLocation.message(result.outcome),
        ),
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
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keeps the field visible when the on-screen keyboard opens.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose your location',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  Material(
                    color: AppColors.white,
                    shape: const CircleBorder(
                      side: BorderSide(color: AppColors.searchBorder),
                    ),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      customBorder: const CircleBorder(),
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(
                          Icons.close_rounded,
                          size: 19,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: _PincodeField(
                controller: _controller,
                error: _error,
                onSubmit: _submit,
                onChanged: () {
                  if (_error != null) {
                    setState(() => _error = null);
                  }
                },
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            _ActionRow(
              label: _locating ? 'Getting your location…' : 'Use current location',
              trailing: Icons.my_location_rounded,
              loading: _locating,
              onTap: _useCurrentLocation,
            ),
            const Divider(height: 1, color: AppColors.border),
            _ActionRow(
              label: 'Manage addresses',
              trailing: Icons.chevron_right_rounded,
              onTap: () {
                // Closes the sheet first, so the form is not stacked on it.
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute(builder: (_) => const AddressFormScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PincodeField extends StatelessWidget {
  final TextEditingController controller;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onChanged;

  const _PincodeField({
    required this.controller,
    required this.error,
    required this.onSubmit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: error == null
                  ? AppColors.searchBorder
                  : const Color(0xFFB4322F),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onSubmit(),
                  decoration: const InputDecoration(
                    hintText: 'Enter pincode',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                  style: const TextStyle(
                    fontSize: 17,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: AppColors.brandBlue,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onSubmit,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.location_on_outlined,
                      size: 22,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 6),
            child: Text(
              error!,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB4322F),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String label;
  final IconData trailing;
  final VoidCallback onTap;
  final bool loading;

  const _ActionRow({
    required this.label,
    required this.trailing,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      child: InkWell(
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandBlue,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brandBlue,
                  ),
                )
              else
                Icon(trailing, size: 22, color: AppColors.brandBlue),
            ],
          ),
        ),
      ),
    );
  }
}
