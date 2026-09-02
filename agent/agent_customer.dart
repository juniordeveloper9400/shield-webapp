import 'package:flutter/foundation.dart';

import '../privilege/privilege_tier.dart';

/// One privilege card a customer holds. A customer can hold more than one.
@immutable
class CustomerPlan {
  final String id;
  final PrivilegeTier tier;

  /// The load the card was activated with — one of [tier]'s published amounts.
  final int amount;

  final DateTime activatedOn;

  const CustomerPlan({
    required this.id,
    required this.tier,
    required this.amount,
    required this.activatedOn,
  });

  /// The tier and the amount together, so every figure the privilege
  /// programme already works out — the bonus, what lands in the wallet, the
  /// monthly coverage — reads off this rather than being recomputed here.
  PrivilegeLoad get load => PrivilegeLoad(tier: tier, amount: amount);

  /// A year on from activation — every privilege card runs on the same
  /// validity.
  DateTime get expiresOn => DateTime(
    activatedOn.year,
    activatedOn.month + PrivilegeProgramme.validityMonths,
    activatedOn.day,
  );

  bool isActiveOn(DateTime asOf) => !asOf.isAfter(expiresOn);

  bool get isActive => isActiveOn(DateTime.now());
}

/// A member one agent personally sold one or more privilege cards to.
///
/// This is what "Direct sale" on the agent portal actually means: not the
/// agents recruited under someone (that is the team tree), but the customers
/// their own selling turned into activated plans — the figure an agent is
/// paid commission on in the first place.
@immutable
class AgentCustomer {
  final String id;
  final String name;
  final String phone;

  /// The agent who sold to this customer — [Agent.id] on the roster.
  final String agentId;

  /// Every card this customer holds, in the order they were sold.
  final List<CustomerPlan> plans;

  const AgentCustomer({
    required this.id,
    required this.name,
    required this.phone,
    required this.agentId,
    required this.plans,
  });

  /// The customer's cards, most recently activated first.
  List<CustomerPlan> get plansByNewest =>
      [...plans]..sort((a, b) => b.activatedOn.compareTo(a.activatedOn));

  List<CustomerPlan> get activePlans =>
      plans.where((plan) => plan.isActive).toList();

  int get planCount => plans.length;

  bool get hasMultiplePlans => plans.length > 1;

  /// When the customer's most recent card was activated — used to order the
  /// direct-sale list newest first.
  DateTime get lastActivatedOn =>
      plans.isEmpty ? DateTime(0) : plansByNewest.first.activatedOn;

  /// The combined load of every card the customer holds.
  int get totalAmount => plans.fold(0, (sum, plan) => sum + plan.amount);

  /// Active while any one card still is.
  bool get isActive => plans.any((plan) => plan.isActive);

  bool isActiveOn(DateTime asOf) =>
      plans.any((plan) => plan.isActiveOn(asOf));

  /// The card the customer row and detail header take their colour from — the
  /// highest-value one still running, or the newest if none are.
  PrivilegeTier get tier {
    final pick = activePlans.isEmpty ? plansByNewest : activePlans;
    return ([...pick]..sort((a, b) => b.amount.compareTo(a.amount))).first.tier;
  }

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

  /// `+91 98470 •••••` — a customer's full number is never shown, same as a
  /// downline agent's.
  String get maskedPhone {
    if (phone.length < 5) {
      return '+91 $phone';
    }
    return '+91 ${phone.substring(0, 5)} •••••';
  }
}
