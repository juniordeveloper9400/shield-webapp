import 'package:flutter/material.dart';

import '../../money.dart';
import '../../theme/app_colors.dart';

/// One rung of the refer-and-earn ladder.
///
/// A rung is its own thing: a name, a number of people to bring in, and what
/// that pays. It used to be built on a privilege card — clearing a level
/// meant enough of the people you referred were carrying Silver, Gold or
/// Platinum — which tied the ladder to the programme's three cards and capped
/// it at three rungs. Referring people and buying a plan are two different
/// acts, and only one of them is what this screen is asking for.
@immutable
class ReferralLevel {
  final int level;

  /// What the rung is called: Starter, Riser, and so on up.
  final String name;

  /// How many people must be referred to clear it.
  final int referralsRequired;

  /// Points awarded, once, on clearing the rung.
  ///
  /// Points rather than rupees. The ladder pays points and nothing else —
  /// money comes from the other side of the programme, as commission on the
  /// plans an invite activates. See [ReferralLadder.planCommissionOn].
  final int points;

  /// The rung's own colour, running cool to warm up the ladder so a glance
  /// says how far along it a level sits.
  final Color accent;

  /// The pale wash of [accent] the rung is drawn on.
  final Color tint;

  const ReferralLevel({
    required this.level,
    required this.name,
    required this.referralsRequired,
    required this.points,
    required this.accent,
    required this.tint,
  });

  /// "500 points", for prose and for the rung's own badge.
  String get pointsLabel =>
      '${formatRupees(points)} point${points == 1 ? '' : 's'}';

  /// "500 pts" — the same figure where a graph label has to stay short.
  String get pointsShort => '${formatRupees(points)} pts';

  /// "Refer 5 members" — the whole of what the rung asks for.
  String get requirement =>
      'Refer $referralsRequired member${referralsRequired == 1 ? '' : 's'}';
}

/// How far one person the member referred has got.
///
/// A referral is only worth something to the referrer once the person does
/// something: joining is where it starts, their first paid order is what
/// counts towards a level, and a plan is what earns commission. The referrer's
/// screen shows each person at whichever of these they have reached.
enum ReferredStage {
  /// Registered with the member's code; no paid order yet. Not counted towards
  /// a level — the referrer sees them so a sign-up never looks like nothing
  /// happened.
  joined('Joined'),

  /// Completed a paid order. This is what counts towards a level.
  transacted('Made a transaction'),

  /// Activated a privilege plan — the commission stage.
  planActivated('Plan activated');

  final String label;

  const ReferredStage(this.label);

  /// Reads an `app.referral_status` token; null for one that is not a person
  /// who has joined (`SHARED` is an invite that was only sent).
  static ReferredStage? fromStatus(String? status) =>
      switch ((status ?? '').toUpperCase()) {
        'REGISTERED' => ReferredStage.joined,
        'TRANSACTED' => ReferredStage.transacted,
        'PLAN_ACTIVATED' => ReferredStage.planActivated,
        _ => null,
      };
}

/// One person who joined on the member's invite code, for the "People you
/// referred" list.
@immutable
class ReferredMember {
  /// First name and last initial ("Althaf M."), enough to recognise them.
  final String name;
  final ReferredStage stage;
  final DateTime? joinedAt;
  final DateTime? transactedAt;
  final DateTime? planActivatedAt;

  const ReferredMember({
    required this.name,
    required this.stage,
    this.joinedAt,
    this.transactedAt,
    this.planActivatedAt,
  });

  /// When they last moved forward — the date the list shows beside them.
  DateTime? get lastActivityAt => switch (stage) {
    ReferredStage.planActivated => planActivatedAt ?? transactedAt ?? joinedAt,
    ReferredStage.transacted => transactedAt ?? joinedAt,
    ReferredStage.joined => joinedAt,
  };

  /// "Nihal", "Althaf M." from a full name, so another member's whole name is
  /// never carried to the referrer's phone.
  static String shortName(String? fullName) {
    final parts = (fullName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'A friend';
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts.last[0].toUpperCase()}.';
  }
}

/// How far a member has progressed.
@immutable
class ReferralProgress {
  /// People brought in on this member's invite link who have gone on to make a
  /// transaction. The one number the ladder is climbed on: rungs clear on
  /// these and nothing else.
  final int directReferrals;

  /// People who joined on this member's code but have not yet made a paid
  /// order. They do not count towards a level until they do; they are reported
  /// so the referrer sees a sign-up the moment it happens instead of nothing.
  final int pendingReferrals;

  /// Everyone who has joined, newest first — each at the stage they have
  /// reached. Empty until somebody signs up with the member's code.
  final List<ReferredMember> invitees;

  /// How many of those referred members went on to activate a privilege plan.
  ///
  /// Reported alongside [directReferrals] rather than folded into it. It is a
  /// measure of how well the invites landed — a referral who buys a card is
  /// worth more to the programme than one who installs and stops — but it
  /// does not clear rungs, so it never changes which level a member is on.
  ///
  /// Always at most [directReferrals]: a plan can only be activated by
  /// somebody who was referred first.
  final int plansActivated;

  /// Sahakar money earned, in rupees: the commission those activations paid.
  ///
  /// Reported rather than worked out. Each activation pays
  /// [ReferralLadder.planCommissionPercent]% of whatever was loaded, and the
  /// loads run from ₹10,000 to ₹1,00,000 — so [plansActivated] alone puts the
  /// total anywhere between ₹200 and ₹2,000 a head. Multiplying a count by a
  /// guessed load would be the app inventing a figure it was never told, so
  /// the sum arrives with the count instead.
  ///
  /// Nought whenever [plansActivated] is nought: there is nothing for a
  /// commission to be a share of.
  final int sahakarMoney;

  const ReferralProgress({
    required this.directReferrals,
    this.pendingReferrals = 0,
    this.invitees = const [],
    this.plansActivated = 0,
    this.sahakarMoney = 0,
  });

  /// Everyone who has signed up with the member's code: those already counted
  /// plus those still waiting on their first paid order.
  int get joinedReferrals => directReferrals + pendingReferrals;

  /// "₹1,000" — what the commission has paid so far.
  String get sahakarMoneyLabel => '₹${formatRupees(sahakarMoney)}';

  bool isLevelCleared(ReferralLevel level) =>
      directReferrals >= level.referralsRequired;

  /// Highest cleared level, or 0 when nothing is cleared yet.
  int currentLevel(List<ReferralLevel> levels) {
    var cleared = 0;
    for (final level in levels) {
      if (isLevelCleared(level)) {
        cleared = level.level;
      } else {
        break;
      }
    }
    return cleared;
  }

  /// The level being worked towards, or null once every level is cleared.
  ReferralLevel? nextLevel(List<ReferralLevel> levels) {
    for (final level in levels) {
      if (!isLevelCleared(level)) {
        return level;
      }
    }
    return null;
  }

  /// Fraction of the way to [level], clamped to 0..1.
  ///
  /// Measured from the rung below rather than from zero, so the bar fills
  /// across the rung being worked on instead of creeping the whole way up the
  /// ladder — at level five, 39 of 40 referrals should not read as almost
  /// nothing done.
  double progressTowards(ReferralLevel level, List<ReferralLevel> levels) {
    final floor = level.level <= 1
        ? 0
        : levels[level.level - 2].referralsRequired;
    final span = level.referralsRequired - floor;
    if (span <= 0) {
      return 1;
    }
    return ((directReferrals - floor) / span).clamp(0.0, 1.0);
  }
}

/// The published ladder: five rungs, Starter to Legend.
class ReferralLadder {
  const ReferralLadder._();

  static const List<ReferralLevel> levels = [
    ReferralLevel(
      level: 1,
      name: 'Starter',
      referralsRequired: 2,
      points: 100,
      accent: AppColors.levelStarter,
      tint: AppColors.levelStarterTint,
    ),
    ReferralLevel(
      level: 2,
      name: 'Riser',
      referralsRequired: 5,
      points: 200,
      accent: AppColors.levelRiser,
      tint: AppColors.levelRiserTint,
    ),
    ReferralLevel(
      level: 3,
      name: 'Achiever',
      referralsRequired: 10,
      points: 500,
      accent: AppColors.levelAchiever,
      tint: AppColors.levelAchieverTint,
    ),
    ReferralLevel(
      level: 4,
      name: 'Champion',
      referralsRequired: 20,
      points: 1500,
      accent: AppColors.levelChampion,
      tint: AppColors.levelChampionTint,
    ),
    ReferralLevel(
      level: 5,
      name: 'Legend',
      referralsRequired: 40,
      points: 3000,
      accent: AppColors.levelLegend,
      tint: AppColors.levelLegendTint,
    ),
  ];

  /// The share of a privilege plan that comes back to whoever invited the
  /// member activating it.
  ///
  /// The second way the programme pays, and the one the ladder does not
  /// cover: rungs clear on referrals alone, so a member who brings in three
  /// people stands on the same rung whether they bought a plan or not. This
  /// is what makes the difference worth something.
  static const int planCommissionPercent = 2;

  /// The commission on a plan of [amount], in Sahakar money.
  ///
  /// Whole-integer arithmetic rather than a multiply by 0.02: two percent of
  /// ₹30,000 is exactly ₹600, and a binary fraction of a percent is not
  /// something a commission figure should inherit. Truncating, on the same
  /// principle the programme rounds its bonus down — a promise is not
  /// overstated by a rounding rule.
  static int planCommissionOn(int amount) =>
      amount <= 0 ? 0 : amount * planCommissionPercent ~/ 100;

  static String planCommissionLabel(int amount) =>
      '₹${formatRupees(planCommissionOn(amount))}';

  /// The points the cleared rungs have paid out.
  ///
  /// Worked out from the ladder rather than stored, so the figure on the
  /// standing card can never disagree with the rungs marked cleared beneath
  /// it.
  static int pointsEarnedBy(ReferralProgress progress) {
    var total = 0;
    for (final level in levels) {
      if (!progress.isLevelCleared(level)) {
        break;
      }
      total += level.points;
    }
    return total;
  }

  static String pointsEarnedLabel(ReferralProgress progress) =>
      formatRupees(pointsEarnedBy(progress));

  /// What clearing the whole ladder pays.
  static int get totalPoints {
    var total = 0;
    for (final level in levels) {
      total += level.points;
    }
    return total;
  }

  static String get totalPointsLabel => '${formatRupees(totalPoints)} points';

  /// Shown on the invite-code card before the member's real code has come
  /// back from Neon (or on a build with no database at all) — a placeholder
  /// so the card is never blank, never the sample fixture below.
  static const String fallbackCode = 'SAHAKAR-RN4821';

  /// The rung a member is standing on: the one they last cleared, or the one
  /// they are working towards before anything is cleared.
  static ReferralLevel standingFor(ReferralProgress progress) {
    final cleared = progress.currentLevel(levels);
    return cleared == 0 ? levels.first : levels[cleared - 1];
  }

  /// How many new members a rung needs beyond the one below it.
  ///
  /// Level 3 asks for ten referrals and level 2 asked for five, so standing on
  /// level 2 the work left is five more — not ten. Read off the neighbours
  /// rather than stored, so it cannot disagree with the rungs.
  static int newMembersFor(ReferralLevel level) {
    final floor = level.level <= 1
        ? 0
        : levels[level.level - 2].referralsRequired;
    return level.referralsRequired - floor;
  }

  /// The one line that says what the rung pays for, in the rung's own numbers.
  static String howItWorks(ReferralLevel level) =>
      'Get ${_people(level.referralsRequired)} to make a transaction on '
      'Sahakar 360 using your invite link, and earn ${level.pointsLabel}.';

  /// The three things that have to happen before a referral counts.
  ///
  /// Every rung qualifies a referral the same way — shared, registered,
  /// transacted — because that is what a referral *is*; what changes rung to
  /// rung is how many people have to do it, so the steps are written from the
  /// rung's own counts rather than kept as one paragraph repeated five times.
  static List<String> stepsFor(ReferralLevel level) {
    final fresh = newMembersFor(level);
    final first = level.level == 1;

    return [
      first
          ? 'Share your invite link with ${_people(fresh)}'
          : 'Share your invite link with ${_people(fresh, more: true)}',
      'They install Sahakar 360 and complete registration with your code',
      first
          ? 'Each one makes their first transaction'
          : 'Each one makes a transaction — ${level.referralsRequired} in all',
    ];
  }

  /// "3 friends", or "3 more friends" partway up the ladder.
  static String _people(int count, {bool more = false}) =>
      '$count ${more ? 'more ' : ''}friend${count == 1 ? '' : 's'}';

  /// Fixture standing in for the signed-in member's real progress.
  static const ReferralProgress sampleProgress = ReferralProgress(
    directReferrals: 3,
    plansActivated: 2,
    // A silver ₹10,000 and a gold ₹40,000 between them: ₹200 and ₹800.
    sahakarMoney: 1000,
  );
}
