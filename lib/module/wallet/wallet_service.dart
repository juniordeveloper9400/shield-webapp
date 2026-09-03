import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/neon/wallet_repository.dart';
import '../../dates.dart';
import '../../money.dart';
import '../privilege/privilege_tier.dart';
import '../registration/shield_store.dart';
import '../rewards/rewards_service.dart';

/// One line in the wallet ledger.
@immutable
class WalletEntry {
  final String label;
  final String date;

  /// Positive credits, negative debits, in whole rupees.
  final int amount;

  const WalletEntry({
    required this.label,
    required this.date,
    required this.amount,
  });

  bool get isCredit => amount >= 0;
}

/// A privilege plan the account holds: what was loaded onto it, when, and
/// until when it is good for.
///
/// A plan rather than a bare [PrivilegeLoad] because the wallet has to answer
/// two questions the load cannot: when money last went on, and when it stops
/// working. Both are dates, and both are per plan — an account holding a
/// silver plan from March and a gold one from August expires them on
/// different days.
@immutable
class WalletCard {
  final PrivilegeLoad load;

  /// The day the card was issued. Validity runs from here.
  final DateTime issuedOn;

  /// The day money last went onto it — the issue date until it is topped up.
  final DateTime rechargedOn;

  /// Topped up onto the card since it was issued, over and above the load it
  /// was issued for.
  final int recharged;

  /// The SHIELD branch this plan was activated against — the one a member with
  /// more than one plan can bill a later order to by picking this plan at
  /// checkout. Null on plans activated before the branch was recorded.
  final ShieldStore? store;

  /// The `app.wallet_card.uuid` this card was approved from, when it came back
  /// from the console rather than being activated straight away in a test.
  final String? remoteId;

  const WalletCard({
    required this.load,
    required this.issuedOn,
    required this.rechargedOn,
    this.recharged = 0,
    this.store,
    this.remoteId,
  });

  String get name => load.name;

  /// Everything the card carries: what it was issued with, bonus included,
  /// plus every recharge since.
  int get loaded => load.credited + recharged;

  /// A twelfth of what is on the card, which is what comes due each month.
  ///
  /// Off the programme's own rule, the same one the card was sold on, so what
  /// the wallet releases matches what the privilege screen offered.
  int get monthlyRedeemable => PrivilegeProgramme.monthlyShareOf(loaded);

  /// The day of the month this card's instalment falls due.
  ///
  /// Its issue day, and the reason two cards on one account do not come due
  /// together: a card taken on the 10th releases a twelfth on the 10th of
  /// every month, and one taken on the 25th waits until the 25th.
  int get cycleDay => issuedOn.day;

  /// The day this card comes due in the month [asOf] falls in.
  ///
  /// Clamped to the length of that month, so a card issued on the 31st comes
  /// due on the 28th in February rather than slipping into March.
  DateTime dueDayIn(DateTime asOf) {
    final lastOfMonth = DateTime(asOf.year, asOf.month + 1, 0).day;
    return DateTime(asOf.year, asOf.month, math.min(cycleDay, lastOfMonth));
  }

  /// Whether this card's instalment for the month [asOf] falls in has been
  /// released.
  ///
  /// A card issued on the 25th is not drawable on the 24th of a later month:
  /// its month has not come round yet. An expired card never is.
  bool isActiveOn(DateTime asOf) {
    if (asOf.isAfter(expiresOn) || asOf.isBefore(issuedOn)) {
      return false;
    }
    return !asOf.isBefore(dueDayIn(asOf));
  }

  /// The next day this card comes due: this month's if it has not passed,
  /// otherwise next month's.
  DateTime nextDueOn(DateTime asOf) {
    final thisMonth = dueDayIn(asOf);
    if (!asOf.isBefore(thisMonth)) {
      return dueDayIn(DateTime(asOf.year, asOf.month + 1, 1));
    }
    return thisMonth;
  }

  /// Which instalment of [PrivilegeProgramme.validityMonths] the card is on,
  /// counting from one on the day it was issued.
  int instalmentOn(DateTime asOf) {
    var months =
        (asOf.year - issuedOn.year) * 12 + (asOf.month - issuedOn.month);
    if (asOf.day < dueDayIn(asOf).day) {
      // This month's has not been released yet, so the card is still on the
      // one before it.
      months -= 1;
    }
    return (months + 1).clamp(1, PrivilegeProgramme.validityMonths);
  }

  /// What has been released off this card so far: one instalment for every
  /// month that has come due.
  int releasedBy(DateTime asOf) => monthlyRedeemable * instalmentOn(asOf);

  /// What is still locked up in the card, waiting on later months.
  int remainingAfter(DateTime asOf) {
    final left = loaded - releasedBy(asOf);
    return left < 0 ? 0 : left;
  }

  /// A year on from issue, to the day.
  DateTime get expiresOn {
    final months = issuedOn.month - 1 + PrivilegeProgramme.validityMonths;
    return DateTime(
      issuedOn.year + months ~/ 12,
      months % 12 + 1,
      issuedOn.day,
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresOn);

  /// This plan's status as the member reads it: [PlanStatus.active] until
  /// the year runs out, then [PlanStatus.expired].
  PlanStatus get planStatus =>
      isExpired ? PlanStatus.expired : PlanStatus.active;

  String get loadedLabel => '₹${formatRupees(loaded)}';

  String get rechargedOnLabel => formatDate(rechargedOn);

  String get expiresOnLabel => formatDate(expiresOn);

  /// A recharge of [amount] on [date]: the same card, carrying more. The
  /// activation branch is fixed on the first issue and rides through recharges.
  WalletCard rechargedWith(int amount, DateTime date) => WalletCard(
    load: load,
    issuedOn: issuedOn,
    rechargedOn: date,
    recharged: recharged + amount,
    store: store,
    remoteId: remoteId,
  );
}

/// The one status a member ever reads off a privilege plan, whatever
/// class is backing it: a submission ([PendingWalletCard]) is `pending` or
/// `rejected`; a card on the wallet ([WalletCard]) is `active` until its
/// year is up, then `expired`.
enum PlanStatus {
  pending('Pending'),
  rejected('Rejected'),
  active('Active'),
  expired('Expired');

  final String label;
  const PlanStatus(this.label);
}

/// Where a submitted privilege card sits before it is on the wallet.
enum PendingCardStatus {
  /// Waiting for a Super Admin to check the receipt in the console.
  awaitingApproval,

  /// Turned down. [PendingWalletCard.note] carries the reason.
  rejected,
}

/// A privilege card the member submitted that is not (yet) crediting the
/// wallet: either waiting on the console, or rejected with a reason. An
/// approved card stops being one of these and becomes a real [WalletCard].
@immutable
class PendingWalletCard {
  final PrivilegeLoad load;
  final ShieldStore? store;

  /// The `app.wallet_card.uuid`, once the submit write has returned. Null while
  /// the row is still being written, or in a build with no database.
  final String? remoteId;

  final DateTime submittedAt;
  final PendingCardStatus status;

  /// The Super Admin's reason — set only when [status] is [PendingCardStatus.rejected].
  final String note;

  const PendingWalletCard({
    required this.load,
    this.store,
    this.remoteId,
    required this.submittedAt,
    this.status = PendingCardStatus.awaitingApproval,
    this.note = '',
  });

  String get name => load.name;

  bool get isRejected => status == PendingCardStatus.rejected;

  /// This submission's status as the member reads it: [PlanStatus.rejected]
  /// when the counter turned it down, otherwise [PlanStatus.pending].
  PlanStatus get planStatus =>
      isRejected ? PlanStatus.rejected : PlanStatus.pending;

  PendingWalletCard copyWith({
    String? remoteId,
    PendingCardStatus? status,
    String? note,
  }) => PendingWalletCard(
    load: load,
    store: store,
    remoteId: remoteId ?? this.remoteId,
    submittedAt: submittedAt,
    status: status ?? this.status,
    note: note ?? this.note,
  );
}

/// The SHIELD wallet: a balance and the ledger behind it.
///
/// Real state rather than a hardcoded figure, because the privilege programme
/// credits a bonus into it — a number that is never shown anywhere would not
/// be a programme at all.
///
/// In memory only; a backend would replace this class wholesale.
class WalletService extends ChangeNotifier {
  WalletService._();

  static final WalletService instance = WalletService._();

  /// What is in the wallet before a plan opens it: nothing.
  ///
  /// It used to open at ₹3,472 against a ledger of five made-up transactions —
  /// an order, a top-up, a referral reward, a cashback. That money came from
  /// nowhere. A wallet is opened by activating a privilege plan and is filled
  /// by that plan, so the only figure it can honestly show before one is
  /// activated is zero, and the only lines in it afterwards are the ones the
  /// plan actually put there.
  ///
  /// It stays a named constant because a backend would fill it from the
  /// account rather than from here.
  static const int openingBalance = 0;

  /// The ledger a wallet opens with. Empty: every line in the wallet is put
  /// there by something the member did.
  static const List<WalletEntry> _seed = [];

  int _balance = openingBalance;
  int _redeemed = 0;
  final List<WalletEntry> _entries = List.of(_seed);

  /// The cards on the account, oldest first, or empty while the wallet is
  /// still closed.
  final List<WalletCard> _cards = [];

  /// Cards the member has submitted that a Super Admin has not approved yet
  /// (or has rejected). They credit nothing — the wallet stays closed on a
  /// pending-only account — and are shown on the wallet screen so the member
  /// knows the plan is with the counter.
  final List<PendingWalletCard> _pending = [];

  int get balance => _balance;

  /// The reward-points balance — read straight from the ledger-backed
  /// [RewardsService], so the wallet and the header coin can never disagree.
  int get rewardPoints => RewardsService.instance.balance;

  /// Every card on the account, oldest first. What the back of the wallet
  /// card lists: an account may hold more than one, and each carries its own
  /// recharge and expiry dates.
  List<WalletCard> get cards => List.unmodifiable(_cards);

  /// The card in hand — the most recently issued one.
  ///
  /// The wallet is drawn against the whole set, but the screens that name one
  /// card mean this one.
  PrivilegeLoad? get card => _cards.isEmpty ? null : _cards.last.load;

  /// A wallet is opened by activating a privilege card and not otherwise.
  ///
  /// The programme is the way in: money is loaded onto a card, the card opens
  /// the wallet, and the wallet spends it. Nothing moves before that, so the
  /// flag is checked here as well as being drawn in the UI — a locked wallet
  /// that could still be topped up through some other path would not be
  /// locked at all. A card that is only submitted, not approved, does not
  /// count: it has credited nothing.
  bool get isActivated => _cards.isNotEmpty;

  /// Cards submitted and not yet on the wallet — awaiting approval or rejected.
  /// Newest first, the order the wallet screen lists them.
  List<PendingWalletCard> get pendingCards =>
      List.unmodifiable(_pending.reversed);

  /// Whether a submission is with the counter, so the "activate" call to action
  /// can stand down rather than invite a second one.
  bool get hasPendingSubmission =>
      _pending.any((card) => card.status == PendingCardStatus.awaitingApproval);

  /// Records a privilege card the member just submitted. It credits nothing —
  /// a Super Admin approves it in the console, and [applyRemoteCards] turns it
  /// into a real [WalletCard] then.
  void submitPending(
    PrivilegeLoad load, {
    ShieldStore? store,
    String? remoteId,
    DateTime? on,
  }) {
    _pending.add(
      PendingWalletCard(
        load: load,
        store: store,
        remoteId: remoteId,
        submittedAt: on ?? DateTime.now(),
      ),
    );
    notifyListeners();
  }

  /// Pins the `app.wallet_card.uuid` onto the pending card once the submit
  /// write returns, so a later refresh matches this exact submission.
  void attachPendingRemoteId(DateTime submittedAt, String remoteId) {
    final index = _pending.indexWhere(
      (card) => card.remoteId == null && card.submittedAt == submittedAt,
    );
    if (index == -1) {
      return;
    }
    _pending[index] = _pending[index].copyWith(remoteId: remoteId);
    notifyListeners();
  }

  /// Merges what the console has decided into the wallet: approves credit the
  /// balance and become real cards, rejections carry their reason, and a
  /// pending row the app had lost (a restart before approval) is re-created.
  ///
  /// Called when the wallet screen opens and when the app returns to the
  /// foreground — the app has no push channel, so this is how an approval made
  /// at the counter reaches the member.
  void applyRemoteCards(List<RemoteWalletCard> remote) {
    var changed = false;

    for (final row in remote) {
      final known = _cards.any((card) => card.remoteId == row.uuid);

      if (row.isApproved) {
        if (known) {
          continue;
        }
        final load = PrivilegeProgramme.loadFor(row.amount);
        if (load == null) {
          continue;
        }
        _cards.add(
          WalletCard(
            load: load,
            issuedOn: row.issuedOn,
            rechargedOn: row.issuedOn,
            recharged: row.rechargedExtra,
            store: StoreDirectory.byId(row.storeCode),
            remoteId: row.uuid,
          ),
        );
        _credit(
          amount: row.amount,
          bonus: row.bonus,
          label: '${load.name} activation',
          bonusLabel: '${load.name} bonus · 10%',
          date: formatDate(row.issuedOn),
        );
        _pending.removeWhere(
          (card) => card.remoteId == row.uuid || _sameLoad(card, row),
        );
        changed = true;
        continue;
      }

      // PENDING or REJECTED — keep it visible, matched by uuid or, for a row
      // the app has not seen an id for yet, by its load and tier.
      final status = row.isRejected
          ? PendingCardStatus.rejected
          : PendingCardStatus.awaitingApproval;
      final index = _pending.indexWhere(
        (card) => card.remoteId == row.uuid || _sameLoad(card, row),
      );
      if (index == -1) {
        final load = PrivilegeProgramme.loadFor(row.amount);
        if (load == null) {
          continue;
        }
        _pending.add(
          PendingWalletCard(
            load: load,
            store: StoreDirectory.byId(row.storeCode),
            remoteId: row.uuid,
            submittedAt: row.submittedAt,
            status: status,
            note: row.reviewerNote,
          ),
        );
        changed = true;
      } else {
        final current = _pending[index];
        if (current.status != status ||
            current.note != row.reviewerNote ||
            current.remoteId != row.uuid) {
          _pending[index] = current.copyWith(
            remoteId: row.uuid,
            status: status,
            note: row.reviewerNote,
          );
          changed = true;
        }
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// Pulls the member's privilege cards from Neon and applies any approvals or
  /// rejections. Best-effort: a no-op without a database or on a failed read.
  Future<void> refreshFromDatabase(String memberPhone) async {
    final remote = await WalletRepository.instance.fetchCards(
      memberPhone: memberPhone,
    );
    if (remote != null) {
      applyRemoteCards(remote);
    }
  }

  /// Drops a rejected card once the member has read the reason.
  void dismissRejected(String remoteId) {
    final before = _pending.length;
    _pending.removeWhere(
      (card) => card.remoteId == remoteId && card.isRejected,
    );
    if (_pending.length != before) {
      notifyListeners();
    }
  }

  static bool _sameLoad(PendingWalletCard card, RemoteWalletCard row) =>
      card.load.tier.kind == row.tierKind && card.load.amount == row.amount;

  /// What comes due this month across every card that has come round.
  ///
  /// The cards pool once they are due — two cards are two twelfths, drawn from
  /// one balance — but they do not come due together. Each releases its
  /// twelfth on its own issue day, so an account holding a card from the 10th
  /// and one from the 25th can draw on the first from the 10th of a month and
  /// on the second only from the 25th. A card whose day has not come round,
  /// or one that has expired, adds nothing.
  int monthlyRedeemableOn(DateTime asOf) {
    var total = 0;
    for (final card in _cards) {
      if (card.isActiveOn(asOf)) {
        total += card.monthlyRedeemable;
      }
    }
    return total;
  }

  int get monthlyRedeemable => monthlyRedeemableOn(DateTime.now());

  /// The cards drawable right now, and the ones still waiting on their day.
  List<WalletCard> activeCardsOn(DateTime asOf) => [
    for (final card in _cards)
      if (card.isActiveOn(asOf)) card,
  ];

  List<WalletCard> waitingCardsOn(DateTime asOf) => [
    for (final card in _cards)
      if (!card.isActiveOn(asOf)) card,
  ];

  /// What the programme has added on top of what was paid in: the 10% bonus
  /// on every plan the account holds.
  ///
  /// Worked out from the plans rather than tallied off the ledger, so it
  /// cannot drift from the cards it is a bonus on — and so a wallet reset or
  /// a reordered ledger cannot change it.
  int get bonusEarned {
    var total = 0;
    for (final card in _cards) {
      total += card.load.bonus;
    }
    return total;
  }

  /// Drawn against this month's allowance so far.
  ///
  /// Only what has been spent since a card opened the wallet counts: the
  /// seeded ledger predates the card, and was paid out of the wallet's own
  /// balance rather than against an allowance that did not exist yet.
  int get redeemedThisMonth => _redeemed;

  /// What is left of this month's allowance.
  ///
  /// Floored at zero rather than allowed to go negative: an allowance that
  /// has been used up is used up, and a negative one would read as a debt the
  /// member does not owe.
  int get monthlyBalance {
    final left = monthlyRedeemable - _redeemed;
    return left < 0 ? 0 : left;
  }

  /// Newest first, which is the order the screen reads them in.
  List<WalletEntry> get entries => List.unmodifiable(_entries);

  /// Opens the wallet on [load], crediting what was paid and the bonus.
  ///
  /// The one way a wallet comes to be open. Activating a card the account
  /// already holds recharges that card; activating a different one issues a
  /// second card alongside it, which is why the wallet holds a list.
  void activate(
    PrivilegeLoad load, {
    String date = 'Today',
    DateTime? on,
    ShieldStore? store,
  }) {
    final day = on ?? DateTime.now();
    final existing = _cards.indexWhere((card) => card.load == load);
    if (existing >= 0) {
      _cards[existing] = _cards[existing].rechargedWith(load.credited, day);
    } else {
      _cards.add(
        WalletCard(load: load, issuedOn: day, rechargedOn: day, store: store),
      );
    }

    _credit(
      amount: load.amount,
      bonus: load.bonus,
      label: '${load.name} activation',
      bonusLabel: '${load.name} bonus · 10%',
      date: date,
    );
  }

  /// Credits [amount], and [bonus] as its own line.
  ///
  /// Returns false, changing nothing, while the wallet is still closed. The
  /// money goes onto the card in hand, so the back of the wallet card can say
  /// when that card was last recharged.
  bool topUp({
    required int amount,
    int bonus = 0,
    String label = 'Wallet top-up',
    String bonusLabel = 'Bonus credit',
    String date = 'Today',
    DateTime? on,
  }) {
    if (!isActivated || amount <= 0) {
      return false;
    }
    _cards[_cards.length - 1] = _cards.last.rechargedWith(
      amount + bonus,
      on ?? DateTime.now(),
    );
    _credit(
      amount: amount,
      bonus: bonus,
      label: label,
      bonusLabel: bonusLabel,
      date: date,
    );
    return true;
  }

  /// Credits [amount] moved across from the agent portal — commission the
  /// agent has earned and chosen to keep in the app rather than withdraw.
  ///
  /// Unlike [topUp] this does not need a privilege plan: the money is the
  /// agent's own commission, not a programme load, so it lands as a plain
  /// balance line and opens nothing.
  bool creditEarnings({
    required int amount,
    String label = 'Agent earnings added',
    String date = 'Today',
  }) {
    if (amount <= 0) {
      return false;
    }
    _balance += amount;
    _entries.insert(0, WalletEntry(label: label, date: date, amount: amount));
    notifyListeners();
    return true;
  }

  /// Spends [amount] against the wallet, drawing on this month's allowance.
  ///
  /// The one debit path, so [redeemedThisMonth] cannot drift from the ledger.
  /// Refused when the wallet is closed or the balance would go negative — the
  /// wallet holds real money and cannot be overdrawn.
  bool spend({
    required int amount,
    required String label,
    String date = 'Today',
  }) {
    if (!isActivated || amount <= 0 || amount > _balance) {
      return false;
    }

    _balance -= amount;
    _redeemed += amount;
    _entries.insert(0, WalletEntry(label: label, date: date, amount: -amount));
    notifyListeners();
    return true;
  }

  /// Two entries rather than one combined credit: the bonus is the whole point
  /// of the privilege programme, and rolling it into the top-up would hide the
  /// thing the member signed up for.
  void _credit({
    required int amount,
    required int bonus,
    required String label,
    required String bonusLabel,
    required String date,
  }) {
    if (amount <= 0) {
      return;
    }

    _entries.insert(0, WalletEntry(label: label, date: date, amount: amount));
    _balance += amount;

    if (bonus > 0) {
      _entries.insert(
        0,
        WalletEntry(label: bonusLabel, date: date, amount: bonus),
      );
      _balance += bonus;
    }
    notifyListeners();
  }

  /// Spends reward points and moves their value into the wallet balance.
  ///
  /// The points side is a negative `REDEMPTION` row on the reward-points
  /// ledger ([RewardsService.redeem]); the wallet side is a credit line here.
  /// Points become wallet balance, so they cannot be redeemed into a wallet
  /// that is not open yet.
  Future<bool> redeemPoints({int? points, String date = 'Today'}) async {
    final toRedeem = points ?? RewardsService.instance.balance;
    if (!isActivated ||
        toRedeem <= 0 ||
        toRedeem > RewardsService.instance.balance) {
      return false;
    }

    final spent = await RewardsService.instance.redeem(toRedeem);
    if (!spent) {
      return false;
    }

    _entries.insert(
      0,
      WalletEntry(
        label: 'Shield points redeemed · $toRedeem pts',
        date: date,
        amount: toRedeem,
      ),
    );
    _balance += toRedeem;
    notifyListeners();
    return true;
  }

  @visibleForTesting
  void reset() {
    _cards.clear();
    _pending.clear();
    _balance = openingBalance;
    _redeemed = 0;
    _entries
      ..clear()
      ..addAll(_seed);
    notifyListeners();
  }
}
