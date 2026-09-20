import 'package:flutter/material.dart';

import '../../money.dart';
import '../../theme/app_colors.dart';

/// Which of the three cards a tier is.
///
/// Every card works its benefits out from the amount loaded, and each works
/// them out differently — silver counts one free consultation per ₹10,000,
/// gold charges a flat reduced rate however much is on it, platinum counts
/// like silver but from a much higher floor. The rule that picks between them
/// has to be able to name the card it is looking at.
///
/// An enum rather than the tier's name, so the switch that picks the rule is
/// exhaustive: a fourth card will not compile until its benefits are written.
enum PrivilegeCardKind { silver, gold, platinum }

/// A named privilege card.
///
/// Three cards, each issued for a band of loads rather than for one figure:
/// silver covers ₹10,000 to ₹30,000, gold ₹40,000 to ₹50,000, platinum
/// ₹60,000 to ₹1,00,000. Every card carries the same 10% bonus — the tiers
/// differ in how much is loaded and in the benefits that come with the card,
/// not in the rate.
@immutable
class PrivilegeTier {
  final String name;

  /// Which card this is, and so which rule works out what a load on it
  /// carries. See [PrivilegeLoad.benefits].
  final PrivilegeCardKind kind;

  /// The first four digits of every card number issued on this tier.
  final String bin;

  /// The loads this card is issued for, smallest first. Whole multiples of
  /// [PrivilegeProgramme.step], and between them the three cards cover every
  /// amount the programme offers — which is why there is no "other amount"
  /// box to fall back on.
  final List<int> amounts;

  /// One line on the card explaining who the tier suits.
  final String blurb;

  /// The card's own colour. Each tier owns a hue so the three are told apart
  /// at a glance rather than by reading the amounts.
  final Color accent;

  /// The pale wash of [accent] its amounts sit on.
  final Color tint;

  const PrivilegeTier({
    required this.name,
    required this.kind,
    required this.bin,
    required this.amounts,
    required this.blurb,
    required this.accent,
    required this.tint,
  });

  /// Every load this card can be issued for.
  List<PrivilegeLoad> get loads => [
    for (final amount in amounts) PrivilegeLoad(tier: this, amount: amount),
  ];

  /// The smallest load on the card — what its face shows before one is picked.
  PrivilegeLoad get entry => PrivilegeLoad(tier: this, amount: amounts.first);

  int get lowest => amounts.first;

  int get highest => amounts.last;

  /// The most this card can put in a wallet: its largest load plus the bonus
  /// on it.
  ///
  /// The headline figure the card is sold on — "benefits up to ₹33,000" — and
  /// worked out rather than written down, so it cannot drift from the amounts
  /// underneath it.
  int get benefitsUpTo => highest + PrivilegeProgramme.bonusOn(highest);

  String get benefitsUpToLabel => '₹${formatRupees(benefitsUpTo)}';

  /// "₹10,000 – ₹30,000", the span the card covers.
  String get rangeLabel =>
      '₹${formatRupees(lowest)} – ₹${formatRupees(highest)}';

  bool covers(int amount) => amounts.contains(amount);
}

/// One card issued for one amount: what is actually activated.
///
/// A tier on its own cannot be loaded — ₹10,000 and ₹30,000 are both silver,
/// and the wallet needs to know which. Pairing the two here means the card
/// face, the amount list and the activate bar are all reading one value.
@immutable
class PrivilegeLoad {
  final PrivilegeTier tier;
  final int amount;

  const PrivilegeLoad({required this.tier, required this.amount});

  String get name => tier.name;

  Color get accent => tier.accent;

  Color get tint => tier.tint;

  /// What Sahakar 360 adds on top.
  int get bonus => PrivilegeProgramme.bonusOn(amount);

  /// What lands in the wallet in total.
  int get credited => amount + bonus;

  /// Sixteen digits in four groups: the card, the programme, the load, and
  /// the account it is issued to.
  ///
  /// A 9 prefix rather than the 3-6 a payment network issues on, so a number
  /// of this length still cannot be read as a debit or credit card.
  String get cardNumber =>
      '${tier.bin} ${PrivilegeProgramme.programmeBlock} '
      '${(amount ~/ 1000).toString().padLeft(4, '0')} '
      '${PrivilegeProgramme.accountBlock}';

  /// How many of the countable benefits this load carries: one per ₹10,000.
  ///
  /// ₹10,000 buys one free dental consultation and ₹30,000 buys three, so the
  /// count is read off the amount rather than written under it. Gold is the
  /// exception and does not use this — it charges a flat reduced rate however
  /// much is on the card.
  int get benefitUnits => amount ~/ PrivilegeProgramme.step;

  /// What this particular load carries.
  ///
  /// Per amount, not per card. The three silver loads do not carry the same
  /// thing — ₹10,000 is one free dental consultation and ₹30,000 is three —
  /// so the list is worked out from the amount instead of being stated once
  /// on the tier and reprinted under every row.
  ///
  /// The first two lines are arithmetic off the load itself: what the card
  /// can be spent on in total, and what that comes to a month. Neither is
  /// written down anywhere, so neither can drift from the amount above it.
  List<String> get benefits => [
    'Eligible healthcare purchases up to $creditedLabel',
    'Complimentary home delivery on eligible orders',
    ...switch (tier.kind) {
      PrivilegeCardKind.silver => [
        'Eligible home-care visit: ₹50 per visit',
        '$benefitUnits complimentary dental consultation${benefitUnits == 1 ? '' : 's'}',
        '$benefitUnits complimentary teleconsultation${benefitUnits == 1 ? '' : 's'}',
        PrivilegeProgramme.dietitianBase,
      ],
      PrivilegeCardKind.gold => [
        // The call-out charge is what separates the two gold loads: ₹40,000
        // pays a reduced one, ₹50,000 stops paying it for the first two
        // visits. Read off the card rather than against the figure, so a
        // third gold load would fall on the better side of it.
        if (amount > tier.lowest)
          '2 complimentary home-care visits'
        else
          'Eligible home-care visit: ₹20 per visit',
        // Flat rates, not counts. Gold buys the consultation cheaply however
        // often it is used, where silver and platinum buy a fixed number of
        // them outright.
        'Eligible dental consultation: ₹15',
        'Eligible teleconsultation: ₹15',
        PrivilegeProgramme.dietitianBase,
      ],
      PrivilegeCardKind.platinum => [
        '$benefitUnits complimentary home-care visit${benefitUnits == 1 ? '' : 's'}',
        '$benefitUnits complimentary dental consultation${benefitUnits == 1 ? '' : 's'}',
        '$benefitUnits complimentary teleconsultation${benefitUnits == 1 ? '' : 's'}',
        PrivilegeProgramme.dietitianPlatinum,
      ],
    },
  ];

  /// What this card carries, with the bonus leading.
  ///
  /// The bonus is split out rather than folded into [benefits] because it is
  /// the one line that is a credit rather than a service — it lands in the
  /// wallet, where the rest are things to spend it on.
  List<String> get inclusions => [
    '$bonusLabel promotional purchase benefit added to your wallet at once',
    ...benefits,
  ];

  String get amountLabel => '₹${formatRupees(amount)}';

  String get bonusLabel => '₹${formatRupees(bonus)}';

  String get creditedLabel => '₹${formatRupees(credited)}';

  @override
  bool operator ==(Object other) =>
      other is PrivilegeLoad &&
      other.amount == amount &&
      other.tier.name == tier.name;

  @override
  int get hashCode => Object.hash(tier.name, amount);
}

/// The privilege programme's rules and its published cards.
class PrivilegeProgramme {
  const PrivilegeProgramme._();

  /// Sahakar 360 adds this share of whatever is loaded.
  static const double bonusRate = 0.10;

  /// Loads are in whole multiples of this, starting at one of them.
  static const int step = 10000;

  /// How long a card stays live once it is issued, and the number of
  /// instalments its credit is redeemed in.
  ///
  /// One figure for both, because they are the same rule read two ways: a
  /// card is a year of medicine bought up front, so a twelfth of what it
  /// carries comes due each month and the last twelfth falls on the month it
  /// expires.
  static const int validityMonths = 12;

  /// The second group of every card number — the programme, not the card.
  static const String programmeBlock = '8801';

  /// The last group: the account the card is issued to.
  ///
  /// One figure for now, matching the four digits the member's referral code
  /// already ends in. A real issuer assigns this per member, and that is the
  /// one part of the number a backend would fill in.
  static const String accountBlock = '4821';

  /// The dietitian consultation carried by silver and gold.
  ///
  /// Stated once here rather than repeated on both, so a change to the
  /// programme is a change in one place.
  static const String dietitianBase = '1 complimentary dietitian consultation';

  /// Platinum's version of the same consultation: valid across two months
  /// rather than one. Fixed across all five platinum loads — it is the one
  /// benefit on that card which does not climb with the amount.
  static const String dietitianPlatinum =
      '1 complimentary dietitian consultation, valid for 2 months';

  /// The three cards, named so anything built on top of a particular one —
  /// the referral ladder, say — can name it rather than index into the
  /// list and hope the order never changes.
  static const PrivilegeTier silver = PrivilegeTier(
    name: 'HealthPass – Silver',
    kind: PrivilegeCardKind.silver,
    bin: '9010',
    amounts: [10000, 20000, 30000],
    blurb: '12-month healthcare purchase benefit for one registered member.',
    accent: AppColors.silverAccent,
    tint: AppColors.silverTint,
  );

  static const PrivilegeTier gold = PrivilegeTier(
    name: 'HealthPass – Gold',
    kind: PrivilegeCardKind.gold,
    bin: '9020',
    amounts: [40000, 50000],
    blurb: 'A family on long-term medication, with room for lab tests.',
    accent: AppColors.goldAccent,
    tint: AppColors.goldTint,
  );

  static const PrivilegeTier platinum = PrivilegeTier(
    name: 'HealthPass – Platinum',
    kind: PrivilegeCardKind.platinum,
    bin: '9030',
    amounts: [60000, 70000, 80000, 90000, 100000],
    blurb: 'Chronic care across several patients, up to a lakh.',
    accent: AppColors.platinumAccent,
    tint: AppColors.platinumTint,
  );

  static const List<PrivilegeTier> tiers = [silver, gold, platinum];

  /// The smallest published load, and the largest.
  static int get minAmount => tiers.first.lowest;

  static int get maxAmount => tiers.last.highest;

  /// 10% of [amount], rounded down to the rupee.
  ///
  /// Down rather than to nearest: a bonus is a promise, and the safe direction
  /// to round a promise is the one that cannot overstate it.
  static int bonusOn(int amount) =>
      amount <= 0 ? 0 : (amount * bonusRate).floor();

  /// What comes due each month out of [total], over the year a card is live.
  ///
  /// The one place the twelfth is worked out. Both the screen a card is bought
  /// on and the wallet it is spent from read this, because a card that offers
  /// "about ₹916 a month" and a wallet that then releases ₹917 — or the other
  /// way about — is the app disagreeing with itself over money.
  ///
  /// Down, like [bonusOn] and for the same reason: twelve of these must never
  /// add up to more than the card carries.
  static int monthlyShareOf(int total) =>
      total <= 0 ? 0 : total ~/ validityMonths;

  /// Whether [amount] is one of the published loads.
  static bool isValidAmount(int amount) => tierFor(amount) != null;

  /// The card [amount] is issued as, or null when no card carries it.
  static PrivilegeTier? tierFor(int amount) {
    for (final tier in tiers) {
      if (tier.covers(amount)) {
        return tier;
      }
    }
    return null;
  }

  /// The card and the amount together, or null when no card carries it.
  static PrivilegeLoad? loadFor(int amount) {
    final tier = tierFor(amount);
    return tier == null ? null : PrivilegeLoad(tier: tier, amount: amount);
  }
}
