import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../registration/shield_store.dart';

// The furniture both checkout steps share.
//
// Kept apart from either screen so neither has to import the other to end on
// the same bar — and so the two steps cannot drift into looking like two
// different flows, which is the failure this whole module exists to avoid.

/// Which of the two steps the member is on.
///
/// Two steps is few enough that a member would manage without a rail. But the
/// second one asks them to leave the app, move money in their banking app and
/// come back, and knowing there is exactly one step left is what makes that a
/// reasonable thing to ask.
class CheckoutSteps extends StatelessWidget {
  /// 1 or 2.
  final int active;

  const CheckoutSteps({super.key, required this.active});

  static const List<String> labels = ['Payment method', 'Pay & confirm'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Container(
              width: 16,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: AppColors.border,
            ),
          _Step(
            index: i + 1,
            label: labels[i],
            done: i + 1 < active,
            active: i + 1 == active,
          ),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int index;
  final String label;
  final bool done;
  final bool active;

  const _Step({
    required this.index,
    required this.label,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final lit = done || active;

    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lit ? AppColors.brandBlue : AppColors.white,
              border: Border.all(
                color: lit ? AppColors.brandBlue : AppColors.border,
              ),
            ),
            child: done
                ? const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: AppColors.white,
                  )
                : Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: lit ? AppColors.white : AppColors.textMuted,
                    ),
                  ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: lit ? AppColors.brandBlue : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bar both steps end on: what is owed on the left, the one way forward
/// on the right.
///
/// Deliberately the same shape as the cart's own checkout bar, because it is
/// the bar the member has just come from — the total stays where it was and
/// only the word on the button changes.
class CheckoutActionBar extends StatelessWidget {
  final String amountLabel;
  final String label;

  /// Null disables the button. The transfer step leaves it null until a
  /// receipt is attached.
  final VoidCallback? onPressed;

  final bool busy;

  const CheckoutActionBar({
    super.key,
    required this.amountLabel,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

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
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Total payable',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Text(
                    amountLabel,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: busy
                      // The submit sends a file, so the button has to say it
                      // is working — pressing it twice would file the same
                      // receipt twice.
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppColors.white,
                          ),
                        )
                      : Text(
                          label,
                          maxLines: 1,
                          style: const TextStyle(
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

/// Says a payment method is listed but not wired up yet.
class ComingSoonPill extends StatelessWidget {
  const ComingSoonPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.chipCreamTint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.goldAccent.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'Coming soon',
        maxLines: 1,
        style: TextStyle(
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w800,
          color: AppColors.goldAccent,
        ),
      ),
    );
  }
}

/// The member's fixed branch, shown read-only.
///
/// Registration and privilege-plan activation are the two places a member
/// chooses their Sahakar 360 store. Every product and pharmacy order after that is
/// served by it, so those checkouts show it here locked rather than as a
/// picker — only the privilege activation offers the choice.
class LockedStoreCard extends StatelessWidget {
  final ShieldStore store;

  /// A line under the card saying where the fixed value came from, or null
  /// when there is nothing to explain.
  final String? note;

  const LockedStoreCard({super.key, required this.store, this.note});

  @override
  Widget build(BuildContext context) {
    final note = this.note;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.pageTint,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              const Icon(
                Icons.storefront_rounded,
                size: 20,
                color: AppColors.brandBlue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your store',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      store.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      store.addressLine,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 14,
                color: AppColors.brandGreenDark,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  note,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The line that names a block on either checkout step.
class CheckoutHeading extends StatelessWidget {
  final String text;

  const CheckoutHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w800,
        color: AppColors.textDark,
      ),
    );
  }
}
