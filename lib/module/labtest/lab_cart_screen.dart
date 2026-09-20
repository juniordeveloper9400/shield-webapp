import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend/order_repository.dart';
import '../../theme/app_colors.dart';
import '../auth/auth_flow.dart';
import '../auth/auth_service.dart';
import '../location/address_book.dart';
import 'lab_cart_service.dart';
import 'lab_package.dart';
import 'patient_count_sheet.dart';

/// The lab basket: booked packages, how many patients each covers, and the
/// bill.
///
/// Separate from the medicine cart on purpose — see [LabCartService].
class LabCartScreen extends StatelessWidget {
  const LabCartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Lab bookings',
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
      body: ListenableBuilder(
        listenable: LabCartService.instance,
        builder: (context, _) {
          final cart = LabCartService.instance;
          if (cart.isEmpty) {
            return const _EmptyState();
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              for (var index = 0; index < cart.bookings.length; index++) ...[
                _BookingCard(index: index, booking: cart.bookings[index]),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              const _BillCard(),
            ],
          );
        },
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: LabCartService.instance,
        builder: (context, _) {
          if (LabCartService.instance.isEmpty) {
            return const SizedBox.shrink();
          }
          return const _CheckoutBar();
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined, size: 54, color: AppColors.textMuted),
            SizedBox(height: 14),
            Text(
              'No tests booked yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Pick a package and choose how many patients it is for.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textBody),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final int index;
  final LabBooking booking;

  const _BookingCard({required this.index, required this.booking});

  Future<void> _changePatients(BuildContext context) async {
    final chosen = await PatientCountSheet.show(
      context,
      booking.package,
      initial: booking.patients,
    );
    if (chosen != null) {
      LabCartService.instance.book(booking.package, patients: chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final package = booking.package;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  package.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => LabCartService.instance.removeAt(index),
                icon: const Icon(Icons.delete_outline_rounded),
                color: AppColors.textMuted,
                iconSize: 21,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Remove booking',
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${package.testCount} tests · report in ${package.reportIn}',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _changePatients(context),
                  icon: const Icon(Icons.person_outline_rounded, size: 18),
                  label: Text(
                    booking.patients == 1
                        ? '1 patient'
                        : '${booking.patients} patients',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandBlue,
                    side: const BorderSide(color: AppColors.searchBorder),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${formatRupees(booking.amount)}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(
                    '₹${package.price} × ${booking.patients}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard();

  @override
  Widget build(BuildContext context) {
    final cart = LabCartService.instance;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Bill summary',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _BillRow(
            label: 'Tests total',
            value: '₹${formatRupees(cart.mrpTotal)}',
          ),
          _BillRow(
            label: 'Package discount',
            value: '- ₹${formatRupees(cart.savings)}',
            accent: AppColors.brandGreenDark,
          ),
          _BillRow(
            label: 'Home collection',
            value: cart.collectionFee == 0
                ? 'FREE'
                : '₹${formatRupees(cart.collectionFee)}',
            accent: cart.collectionFee == 0 ? AppColors.brandGreenDark : null,
          ),
          const Divider(height: 22, color: AppColors.border),
          _BillRow(
            label: 'Payable',
            value: '₹${formatRupees(cart.payable)}',
            bold: true,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              cart.patientCount == 1
                  ? 'For 1 patient'
                  : 'For ${cart.patientCount} patients',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;
  final bool bold;

  const _BillRow({
    required this.label,
    required this.value,
    this.accent,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: bold ? 16 : 14,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: accent ?? (bold ? AppColors.textDark : AppColors.textBody),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar();

  /// Files the basket as `app.lab_booking` rows (status `REQUESTED`) on the
  /// same guarded tap that moves on to slot selection. Best-effort: a missing
  /// or unreachable database leaves the flow exactly as it was.
  void _selectSlot(BuildContext context) {
    AuthFlow.guardRegistered(context, 'book lab tests', () {
      final cart = LabCartService.instance;
      final user = AuthService.instance.currentUser.value;
      if (user != null && !cart.isEmpty) {
        unawaited(
          OrderRepository.instance.saveLabBookings(
            phone: user.phone,
            name: user.name,
            address: AddressBook.instance.deliverTo,
            bookings: [
              for (final booking in cart.bookings)
                LabBookingInput(
                  name: booking.package.name,
                  testCount: booking.package.testCount,
                  profileCount: booking.package.profileCount,
                  rating: booking.package.rating,
                  booked: booking.package.booked,
                  reportIn: booking.package.reportIn,
                  unitPrice: booking.package.priceValue,
                  mrp: booking.package.mrpValue,
                  patients: booking.patients,
                  forWhom: booking.package.forWhom,
                  ageRange: booking.package.ageRange,
                  preparation: booking.package.preparation,
                  sample: booking.package.sample,
                  about: booking.package.about,
                ),
            ],
          ),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choosing a slot')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = LabCartService.instance;

    return Material(
      color: AppColors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₹${formatRupees(cart.payable)}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  const Text(
                    'Total',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  // Same rule as the medicine cart: browsing and building the
                  // basket stay open, booking a visit needs an account.
                  onPressed: () => _selectSlot(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Select slot',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
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
