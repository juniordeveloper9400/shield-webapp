import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend/order_repository.dart';
import '../../theme/app_colors.dart';
import '../auth/auth_service.dart';
import '../location/address_book.dart';
import 'lab_booking_placed_screen.dart';
import 'lab_cart_service.dart';
import 'lab_checkout_panels.dart';
import 'lab_package.dart';

/// The lab basket's checkout: a read-only review of what's booked, the
/// branch and the bill (see [LabBranchRow] / [LabBillCard], shared with the
/// cart itself), and the one button that actually places it — "Place lab
/// test", the same weight "Place order" carries on the medicine checkout.
///
/// Deliberately not the full commerce checkout screen: a lab booking is
/// never paid up front here — [OrderRepository.saveLabBookings] files it
/// against `POST /v1/member/lab-bookings` as `REQUESTED` and the lab settles
/// the bill with the member when the sample is actually collected — so there
/// is no payment method, receipt or delivery step to walk through, only a
/// last look before it's sent.
class LabCheckoutScreen extends StatefulWidget {
  const LabCheckoutScreen({super.key});

  @override
  State<LabCheckoutScreen> createState() => _LabCheckoutScreenState();
}

class _LabCheckoutScreenState extends State<LabCheckoutScreen> {
  bool _placing = false;
  String? _error;

  bool get _canPlace =>
      !_placing &&
      !LabCartService.instance.isEmpty &&
      LabCartService.instance.store != null;

  Future<void> _placeLabTest() async {
    final cart = LabCartService.instance;
    final user = AuthService.instance.currentUser.value;
    if (!_canPlace || user == null) {
      setState(() {
        _error = cart.store == null
            ? 'Choose a branch above before placing this booking.'
            : null;
      });
      return;
    }

    setState(() {
      _placing = true;
      _error = null;
    });

    final bookings = [
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
    ];
    final bookingCount = cart.bookings.length;
    final patientCount = cart.patientCount;
    final payable = cart.payable;

    // Same pattern the medicine checkout submits an order with: the write to
    // the backend is best-effort (saveLabBookings logs and moves on per
    // booking rather than throwing), so it is fired without blocking the
    // member on it — the basket is cleared and the confirmation shown the
    // moment the tap is handled, not once a network round trip happens to
    // finish.
    unawaited(
      OrderRepository.instance.saveLabBookings(
        phone: user.phone,
        name: user.name,
        address: AddressBook.instance.deliverTo,
        storeId: cart.store?.id,
        bookings: bookings,
      ),
    );

    cart.clear();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LabBookingPlacedScreen(
          bookingCount: bookingCount,
          patientCount: patientCount,
          payable: payable,
        ),
      ),
    );
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
      body: ListenableBuilder(
        listenable: LabCartService.instance,
        builder: (context, _) {
          final cart = LabCartService.instance;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _ReviewCard(bookings: cart.bookings),
              const SizedBox(height: 12),
              const LabBranchRow(),
              const SizedBox(height: 12),
              const LabBillCard(),
              const SizedBox(height: 12),
              const _NoPaymentNote(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: Material(
        color: AppColors.white,
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: ListenableBuilder(
              listenable: LabCartService.instance,
              builder: (context, _) {
                final cart = LabCartService.instance;
                return Row(
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
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: _canPlace ? _placeLabTest : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _placing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Place lab test',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A read-only recap of what's in the basket — editing a test or its patient
/// count happens back on the cart, not here.
class _ReviewCard extends StatelessWidget {
  final List<LabBooking> bookings;

  const _ReviewCard({required this.bookings});

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
          const Text(
            'Booking summary',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          for (final booking in bookings) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.package.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        booking.patients == 1
                            ? '1 patient'
                            : '${booking.patients} patients',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${formatRupees(booking.amount)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
            if (booking != bookings.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _NoPaymentNote extends StatelessWidget {
  const _NoPaymentNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: AppColors.textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'No payment now — settle the bill with the lab when your sample '
            'is collected.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
