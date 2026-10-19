import 'package:flutter/material.dart';

import '../../dates.dart';
import '../../theme/app_colors.dart';
import '../auth/auth_flow.dart';
import '../wallet/wallet_service.dart';
import 'lab_cart_service.dart';
import 'lab_checkout_panels.dart';
import 'lab_checkout_screen.dart';
import 'lab_package.dart';
import 'lab_patient_picker_sheet.dart';

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
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: LabCartService.instance,
              builder: (context, _) {
                final cart = LabCartService.instance;
                if (cart.isEmpty) {
                  return const _EmptyState();
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    for (
                      var index = 0;
                      index < cart.bookings.length;
                      index++
                    ) ...[
                      _BookingCard(index: index, booking: cart.bookings[index]),
                      const SizedBox(height: 12),
                    ],
                    LabBranchRow(),
                    const SizedBox(height: 12),
                    // Hidden unless the member holds a live Health Pass.
                    const _HealthPassCouponCard(),
                    const SizedBox(height: 12),
                    // The lab quotes the final bill itself, so the cart shows
                    // a note here instead of a bill summary.
                    const _LabBillNote(),
                  ],
                );
              },
            ),
          ),
        ],
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

/// Stands in for a bill summary on the lab cart: the lab, not the app, tells
/// the member the final total.
class _LabBillNote extends StatelessWidget {
  const _LabBillNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: AppColors.brandBlue),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'The total bill for your lab tests will be shown by the lab.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.textBody,
              ),
            ),
          ),
        ],
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
    final chosen = await LabPatientPickerSheet.show(
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
                    booking.patients.length == 1
                        ? booking.patients.first.name
                        : '${booking.patients.length} patients',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                    '₹${package.price} × ${booking.patients.length}',
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

/// The total and the one button that leaves this screen — "Proceed to
/// checkout", the same wording and weight the medicine cart's own bar uses,
/// opening [LabCheckoutScreen] to review and actually place the booking
/// rather than filing it straight off this tap.
class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar();

  void _proceed(BuildContext context) {
    // Same rule as the medicine cart: browsing and building the basket stay
    // open, moving on to checkout needs an account (and, here, a completed
    // registration — booking a visit needs somewhere real to send the lab).
    AuthFlow.guardRegistered(context, 'book lab tests', () {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LabCheckoutScreen()));
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
                  onPressed: () => _proceed(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Proceed to checkout',
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

/// The member's activated Health Pass, shown as a coupon with an "Apply"
/// button: which plan, when it was activated, and the home-care charge it
/// gives them — the line a lab home-collection booking draws on. Nothing
/// here is hardcoded: the home-care line is picked out of [PrivilegeLoad.
/// benefits], the same list the Health Pass purchase screen reads, so
/// Silver/Gold/Platinum's different charge can only ever match what that
/// plan was sold on. The rest of the plan's benefits sit behind "View all
/// benefits". Shown nothing when the account holds no plan that is drawable
/// today.
class _HealthPassCouponCard extends StatefulWidget {
  const _HealthPassCouponCard();

  @override
  State<_HealthPassCouponCard> createState() => _HealthPassCouponCardState();
}

class _HealthPassCouponCardState extends State<_HealthPassCouponCard> {
  bool _showAll = false;
  // A visual confirmation only — the lab quotes the final bill itself (see
  // _LabBillNote), so there is no price on this screen for "Apply" to
  // change. Tapping it just tells the member their Health Pass is in effect
  // for this booking's home collection, the same way a coupon chip flips to
  // "Applied" without the cart screen doing its own maths.
  bool _applied = false;

  /// `16 Aug 2026, 05:24 PM`, or just the date when the activation carries no
  /// time of day (a plain date reads as midnight).
  static String _activatedLabel(DateTime at) {
    final local = at.toLocal();
    final hasTime = local.hour != 0 || local.minute != 0;
    return hasTime ? formatDateTime12h(local) : formatDate(local);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WalletService.instance,
      builder: (context, _) {
        final active = WalletService.instance.activeCardsOn(DateTime.now());
        if (active.isEmpty) {
          return const SizedBox.shrink();
        }
        // The most recently issued plan that is drawable today — the same
        // "last" rule WalletService's own [card] getter uses.
        final card = active.last;
        final load = card.load;
        final tier = load.tier;
        final homeCare = load.benefits.firstWhere((line) {
          final lower = line.toLowerCase();
          return lower.contains('home') && lower.contains('care');
        }, orElse: () => '');

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tier.accent.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tier.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.local_offer_rounded,
                        size: 18,
                        color: tier.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _applied
                                ? 'Health Pass applied · ${tier.name}'
                                : 'Health Pass available · ${tier.name}',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${load.amountLabel} plan · activated '
                            '${_activatedLabel(card.issuedOn)}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_applied)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.greenTint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: AppColors.brandGreenDark,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'Applied',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandGreenDark,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      OutlinedButton(
                        onPressed: () => setState(() => _applied = true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tier.accent,
                          side: BorderSide(color: tier.accent),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Apply',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (homeCare.isNotEmpty) ...[
                Divider(height: 1, color: tier.accent.withValues(alpha: 0.25)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: AppColors.brandGreenDark,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          homeCare,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandGreenDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Divider(height: 1, color: tier.accent.withValues(alpha: 0.25)),
              InkWell(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
                onTap: () => setState(() => _showAll = !_showAll),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _showAll ? 'Hide benefits' : 'View all benefits',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: tier.accent,
                          ),
                        ),
                      ),
                      Icon(
                        _showAll
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: tier.accent,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showAll)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Column(
                    children: [
                      for (final line in load.benefits)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1, right: 8),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  size: 15,
                                  color: tier.accent,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  line,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: AppColors.textBody,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
