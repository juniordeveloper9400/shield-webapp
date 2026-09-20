import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// One way of paying, and whether it actually works yet.
///
/// The UPI apps are listed before they are wired up on purpose. A member
/// deciding whether to buy a ₹40,000 plan wants to know that GPay is coming;
/// a checkout that offered bank transfer alone would read as the only way it
/// will ever be done. They are listed, they are legible, and they say so when
/// tapped — which is honest in a way that hiding them is not.
@immutable
class PaymentMethod {
  /// Stable across renames — what a stored receipt records.
  final String id;

  final String name;

  /// The line under the name: what choosing this actually involves.
  final String blurb;

  final IconData icon;

  /// The method's own colour, and the wash its glyph sits on.
  final Color accent;
  final Color tint;

  /// False while the method is listed but cannot be used.
  final bool isLive;

  const PaymentMethod({
    required this.id,
    required this.name,
    required this.blurb,
    required this.icon,
    required this.accent,
    required this.tint,
    required this.isLive,
  });

  /// What a member is told when they reach for one that is not wired up yet.
  String get comingSoonNote =>
      '$name is coming soon. Pay by bank transfer for now.';
}

/// Every way of paying the app offers, in the order they are offered.
///
/// Bank transfer leads because it is the one that works. The rest follow in
/// no particular order beyond being the three apps a member in Kerala is
/// most likely to already have on their phone.
abstract final class PaymentMethods {
  static const PaymentMethod bankTransfer = PaymentMethod(
    id: 'bank-transfer',
    name: 'Bank account',
    blurb: 'Transfer to Sahakar 360 and upload the receipt',
    icon: Icons.account_balance_rounded,
    accent: AppColors.brandBlue,
    tint: AppColors.chipBlueTint,
    isLive: true,
  );

  static const PaymentMethod googlePay = PaymentMethod(
    id: 'gpay',
    name: 'Google Pay',
    blurb: 'Pay by UPI',
    icon: Icons.account_balance_wallet_rounded,
    accent: Color(0xFF2E7D32),
    tint: Color(0xFFE9F3EA),
    isLive: false,
  );

  static const PaymentMethod phonePe = PaymentMethod(
    id: 'phonepe',
    name: 'PhonePe',
    blurb: 'Pay by UPI',
    icon: Icons.smartphone_rounded,
    accent: Color(0xFF5F259F),
    tint: Color(0xFFEFE8F6),
    isLive: false,
  );

  static const PaymentMethod paytm = PaymentMethod(
    id: 'paytm',
    name: 'Paytm',
    blurb: 'Pay by UPI',
    icon: Icons.qr_code_2_rounded,
    accent: Color(0xFF00699C),
    tint: Color(0xFFE3F1F8),
    isLive: false,
  );

  static const List<PaymentMethod> all = [
    bankTransfer,
    googlePay,
    phonePe,
    paytm,
  ];

  /// The ones that can actually be used today. One, for now.
  static List<PaymentMethod> get live =>
      all.where((method) => method.isLive).toList();

  /// Pay from the Sahakar 360 wallet balance — instant, and never "coming soon".
  /// Capped at what this month's wallet allowance has left
  /// ([WalletService.walletShareOf]), not the account's full balance; any
  /// remainder on the order is paid in cash alongside it.
  static const PaymentMethod wallet = PaymentMethod(
    id: 'wallet',
    name: 'Wallet balance',
    blurb: 'Pay from your Sahakar 360 wallet',
    icon: Icons.account_balance_wallet_rounded,
    accent: AppColors.brandGreenDark,
    tint: AppColors.greenTint,
    isLive: true,
  );

  /// Pay the person who hands the order over — the delivery rider, or the
  /// counter on a store pickup.
  static const PaymentMethod cash = PaymentMethod(
    id: 'cash',
    name: 'Cash',
    blurb: 'Pay the delivery person, or at the store on pickup',
    icon: Icons.payments_outlined,
    accent: AppColors.goldAccent,
    tint: AppColors.goldTint,
    isLive: true,
  );

  /// The payment choices for a delivering (product/prescription) checkout.
  /// Manual bank transfer settles a privilege-plan purchase, not a parcel —
  /// an order that ships is paid for at the point it changes hands instead.
  static const List<PaymentMethod> forOrder = [wallet, cash];
}
