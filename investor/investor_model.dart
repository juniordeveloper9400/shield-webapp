import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../registration/shield_store.dart';

/// Which way an investor's return plan reads — set once, when the stake was
/// opened, and from then on changed only through [InvestorPlanType.other],
/// which is a request to admin rather than something the investor can flip
/// for themselves.
enum InvestorPlanType {
  yearly('Yearly'),
  monthly('Monthly');

  const InvestorPlanType(this.label);

  final String label;

  /// The one other option — what a conversion request asks to switch to.
  InvestorPlanType get other =>
      this == InvestorPlanType.yearly
          ? InvestorPlanType.monthly
          : InvestorPlanType.yearly;
}

/// A stakeholder in SHIELD itself, rather than a member buying a plan or an
/// agent recruiting a team — holds units, not a privilege card, and reads
/// the business back as a store and a return, not a wallet.
@immutable
class Investor {
  final String id;
  final String name;
  final String phone;

  /// The printed reference, e.g. `SHD-INV-001`.
  final String investorCode;

  /// The one outlet this stake is actually in — an investor backs a
  /// specific store, not the whole directory of them.
  final ShieldStore investedStore;

  /// How many units this investor holds.
  final int totalUnits;

  /// What one unit costs, in whole rupees — [totalInvested] is derived from
  /// this rather than stored on its own, so the two can never drift apart.
  /// A unit is priced at ₹1,50,000.
  final int unitPrice;

  final DateTime investedSince;

  /// Return on investment to date, as a percentage — e.g. `18.5` for 18.5%.
  final double roiPercent;

  /// Whether the return plan reads yearly or monthly — fixed to whichever it
  /// was set to the first time the stake was opened.
  final InvestorPlanType planType;

  const Investor({
    required this.id,
    required this.name,
    required this.phone,
    required this.investorCode,
    required this.investedStore,
    required this.totalUnits,
    required this.unitPrice,
    required this.investedSince,
    required this.roiPercent,
    required this.planType,
  });

  /// The principal: units held times what each one cost.
  int get totalInvested => totalUnits * unitPrice;

  /// What the stake is worth today, principal plus the return it has earned.
  int get currentValue =>
      (totalInvested * (1 + roiPercent / 100)).round();

  /// The gain alone — [currentValue] less what was put in.
  int get totalReturns => currentValue - totalInvested;

  /// Whole months since [investedSince], never less than one — the divisor
  /// behind the return plan's monthly figure, and floored at one so a stake
  /// opened this month still has a pace to show rather than a division by
  /// zero.
  int get monthsInvested {
    final now = DateTime.now();
    final months =
        (now.year - investedSince.year) * 12 +
        (now.month - investedSince.month);
    return months < 1 ? 1 : months;
  }

  /// The average monthly pace [totalReturns] has been earned at, so far —
  /// what the "Monthly" side of the return plan shows.
  int get monthlyReturnPace => (totalReturns / monthsInvested).round();

  /// The monthly pace annualised — what the "Yearly" side shows. Derived
  /// from the same monthly figure rather than [totalReturns] divided by
  /// years directly, so the two views of the return plan always agree with
  /// each other down to the twelfth.
  int get yearlyReturnPace => monthlyReturnPace * 12;

  /// The purchase credit SHIELD offers against this stake — 10% of what was
  /// invested, plus a flat ₹250 — spendable on products and pharmacy
  /// purchases through the wallet.
  int get purchaseCredit => (totalInvested * 0.10).round() + 250;

  /// A plausible history of [count] periods — years when [yearly], months
  /// otherwise — leading up to and including the one this stake is in right
  /// now. Built as a gentle upward climb to the current pace
  /// ([yearlyReturnPace] or [monthlyReturnPace]) with a small wave through
  /// it, deterministically, so the line reads as a real trend rather than a
  /// straight ramp and the same stake always tells the same story twice.
  ///
  /// Oldest first, matching [returnHistoryLabels] point for point.
  List<int> returnHistory({required bool yearly, int count = 6}) {
    final pace = yearly ? yearlyReturnPace : monthlyReturnPace;
    return [
      for (var i = 0; i < count; i++) _historyPoint(pace, i, count),
    ];
  }

  static int _historyPoint(int pace, int index, int count) {
    final progress = (index + 1) / count;
    final wave = 0.06 * math.sin(index * 1.3);
    final factor = (0.55 + 0.45 * progress + wave).clamp(0.3, 1.15);
    return (pace * factor).round();
  }

  /// The calendar label for each entry [returnHistory] returns — the last
  /// [count] years, or the last [count] months, oldest first, ending on the
  /// current one.
  List<String> returnHistoryLabels({required bool yearly, int count = 6}) {
    final now = DateTime.now();
    return [
      for (var i = count - 1; i >= 0; i--)
        yearly ? '${now.year - i}' : _monthLabel(DateTime(now.year, now.month - i)),
    ];
  }

  static const List<String> _monthAbbrev = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _monthLabel(DateTime date) =>
      '${_monthAbbrev[date.month - 1]} '
      "'${(date.year % 100).toString().padLeft(2, '0')}";

  /// One or two letters for the avatar circle.
  String get initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return '?';
    }
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }

  /// `+91 98765 •••••` — the full number is never shown back, same as an
  /// agent's or a customer's.
  String get maskedPhone {
    if (phone.length < 5) {
      return '+91 $phone';
    }
    return '+91 ${phone.substring(0, 5)} •••••';
  }
}
