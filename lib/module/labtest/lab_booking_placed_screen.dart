import 'package:flutter/material.dart';

import '../../money.dart';
import '../../theme/app_colors.dart';
import '../../widgets/success_tick.dart';
import 'my_lab_bookings_screen.dart';

/// The "your lab test is booked" screen, shown once [LabCheckoutScreen] has
/// filed the basket — the same role [OrderPlacedScreen] plays for a medicine
/// order, with the same [SuccessTick] confirmation, but pointed at My Lab
/// Bookings instead of order tracking since that is where a placed booking
/// actually lives.
///
/// Replaces the checkout in the stack rather than sitting on top of it — a
/// back gesture from here should land on the (now empty) cart, not on a
/// checkout for a booking already placed.
class LabBookingPlacedScreen extends StatelessWidget {
  final int bookingCount;
  final int patientCount;
  final int payable;

  const LabBookingPlacedScreen({
    super.key,
    required this.bookingCount,
    required this.patientCount,
    required this.payable,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            children: [
              const Spacer(),
              const SuccessTick(),
              const SizedBox(height: 24),
              const Text(
                'Lab test booked',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$bookingCount ${bookingCount == 1 ? 'test' : 'tests'} · '
                '$patientCount ${patientCount == 1 ? 'patient' : 'patients'} '
                '· ₹${formatRupees(payable)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandBlue,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'The lab will contact you to confirm your sample collection. '
                'Track it any time from My Lab Bookings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const MyLabBookingsScreen(),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.science_outlined, size: 20),
                  label: const Text(
                    'View my bookings',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text(
                  'Back to home',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textBody,
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
