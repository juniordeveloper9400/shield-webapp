import 'package:flutter/foundation.dart';

import '../../money.dart';
import '../auth/auth_service.dart';
import '../wallet/wallet_service.dart';
import 'agent_customer.dart';
import 'agent_customer_directory.dart';
import 'agent_directory.dart';
import 'agent_model.dart';

/// The live, in-memory agent roster plus the withdrawal ledger.
///
/// Modelled on [ChangeNotifier] the same way `RegistrationService` is — a
/// single instance, getters for the derived figures, mutators that call
/// `notifyListeners()`, and a `@visibleForTesting` [reset]. The roster starts
/// as a copy of [AgentDirectory.seed]; agents added from the portal
/// ([addAgent]) live here until the app restarts. A backend would replace this
/// wholesale: [addAgent] becomes the create call, [requestWithdrawal] the
/// payout call, and the tree getters become downline queries.
class AgentService extends ChangeNotifier {
  AgentService._();

  static final AgentService instance = AgentService._();

  /// The smallest amount a withdrawal request may ask for.
  static const int minWithdrawal = 500;

  /// The share of downline sales an agent earns as override commission.
  static const int commissionPercent = 2;

  /// The whole roster, seed agents and added ones alike.
  final List<Agent> _agents = [...AgentDirectory.seed];

  /// Bumped for every added agent so ids and placeholder numbers stay unique.
  int _added = 0;

  /// Requests raised in this session, keyed by agent id, oldest first.
  final Map<String, List<WithdrawalRequest>> _requests = {};

  /// Earnings each agent has moved into their SHIELD wallet, keyed by agent
  /// id. Counts against [withdrawableFor] the same way a paid-out request
  /// would — the money has left the commission pot either way.
  final Map<String, int> _movedToWallet = {};

  /// Every customer any agent has sold a plan to.
  final List<AgentCustomer> _customers = [...AgentCustomerDirectory.seed];

  // ---- Roster ----

  /// Every agent, seed and added, in insertion order.
  List<Agent> get roster => List.unmodifiable(_agents);

  Agent? byId(String id) {
    for (final agent in _agents) {
      if (agent.id == id) {
        return agent;
      }
    }
    return null;
  }

  /// Sets [agent]'s profile photo, replacing their roster entry with a copy
  /// carrying it. A no-op if the agent is no longer on the roster.
  void setPhoto(Agent agent, Uint8List bytes) {
    final index = _agents.indexWhere((a) => a.id == agent.id);
    if (index < 0) {
      return;
    }
    _agents[index] = _agents[index].withPhoto(bytes);
    notifyListeners();
  }

  /// The agent for [phone], or null when the number is not an agent's. Only
  /// the seed national agent carries a real number.
  Agent? agentForPhone(String? phone) {
    if (phone == null) {
      return null;
    }
    final clean = phone.trim();
    for (final agent in _agents) {
      if (agent.phone == clean) {
        return agent;
      }
    }
    return null;
  }

  /// The agents reporting directly to [id], in insertion order.
  List<Agent> childrenOf(String id) =>
      _agents.where((agent) => agent.parentId == id).toList(growable: false);

  /// Every agent anywhere below [id] in the tree. [id] itself is not included.
  List<Agent> descendantsOf(String id) {
    final out = <Agent>[];
    final queue = <String>[id];
    while (queue.isNotEmpty) {
      final next = queue.removeLast();
      for (final child in childrenOf(next)) {
        out.add(child);
        queue.add(child.id);
      }
    }
    return out;
  }

  /// The chain of parents above [id], nearest first.
  List<Agent> ancestorsOf(String id) {
    final out = <Agent>[];
    var current = byId(id);
    while (current?.parentId != null) {
      final parent = byId(current!.parentId!);
      if (parent == null) {
        break;
      }
      out.add(parent);
      current = parent;
    }
    return out;
  }

  /// Every tier a new agent under [parent] may be registered at — anything
  /// strictly below parent's own level, not just the one tier immediately
  /// under them. A national agent can recruit a district agent straight
  /// away without first having to seed a region and a state to sit them
  /// under — the tiers in between are filled in later, or never, as real
  /// people are found for them. Empty at a ward, which heads nobody.
  List<AgentLevel> allowedChildLevels(Agent parent) =>
      AgentLevel.values.sublist(parent.level.index + 1);

  /// How many more agents [parent] can take on directly, before every
  /// position [AgentLevel.childCapacity] opens up under them is filled — the
  /// same budget of direct reports whatever tier each one actually ends up
  /// registered at.
  int openPositionsUnder(Agent parent) =>
      (parent.level.childCapacity - childrenOf(parent.id).length).clamp(
        0,
        parent.level.childCapacity,
      );

  // ---- Customers ----
  // What "Direct sale" actually shows: not the agents someone recruited, but
  // the customers their own selling turned into activated plans.

  /// Every customer [agent] personally sold a plan to, newest activation
  /// first.
  List<AgentCustomer> customersOf(Agent agent) {
    final mine = _customers.where((c) => c.agentId == agent.id).toList();
    mine.sort((a, b) => b.lastActivatedOn.compareTo(a.lastActivatedOn));
    return mine;
  }

  int activeCustomerCount(Agent agent) =>
      customersOf(agent).where((c) => c.isActive).length;

  /// The share of a plan's load the selling agent keeps as their direct
  /// commission — richer than the [commissionPercent] override on downline
  /// volume, because a direct sale is the agent's own work.
  static const int directCommissionPercent = 5;

  /// What [agent] earned on one card.
  int commissionOnPlan(CustomerPlan plan) =>
      plan.amount * directCommissionPercent ~/ 100;

  /// What [agent] earned across every card one customer holds.
  int commissionOnSale(AgentCustomer customer) =>
      customer.plans.fold(0, (sum, p) => sum + commissionOnPlan(p));

  /// What [agent]'s own direct sales have earned them in total.
  int directSaleEarnings(Agent agent) => customersOf(
    agent,
  ).fold(0, (sum, c) => sum + commissionOnSale(c));

  /// The combined card value of every direct sale [agent] has made.
  int directSaleVolume(Agent agent) =>
      customersOf(agent).fold(0, (sum, c) => sum + c.totalAmount);

  @visibleForTesting
  void addCustomer(AgentCustomer customer) {
    _customers.add(customer);
    notifyListeners();
  }

  // ---- Registration field checks ----
  // Static so the registration screen can hang them straight off its fields,
  // and [registerAgent] re-runs the lot as the backstop.

  static String? validateName(String? value, {String field = 'name'}) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'Enter the $field';
    }
    if (text.length < 2) {
      return 'Enter at least 2 characters';
    }
    if (!RegExp(r"^[A-Za-z][A-Za-z .'-]*$").hasMatch(text)) {
      return 'Use letters only';
    }
    return null;
  }

  /// Middle name is optional, but if given it has to look like a name.
  static String? validateMiddleName(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    return validateName(text, field: 'middle name');
  }

  static String? validatePhone(String? value) => AuthService.validatePhone(value);

  static String? validateAadhaar(String? value) {
    final text = (value ?? '').replaceAll(' ', '');
    if (text.isEmpty) {
      return 'Aadhaar number is required';
    }
    if (!RegExp(r'^\d{12}$').hasMatch(text)) {
      return 'Aadhaar is 12 digits';
    }
    return null;
  }

  static String? validatePan(String? value) {
    final text = (value ?? '').trim().toUpperCase();
    if (text.isEmpty) {
      return 'PAN is required';
    }
    if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(text)) {
      return 'PAN looks like ABCDE1234F';
    }
    return null;
  }

  static String? validatePincode(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'PIN code is required';
    }
    if (!RegExp(r'^\d{6}$').hasMatch(text)) {
      return 'PIN code is 6 digits';
    }
    return null;
  }

  static String? validateAccountNumber(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'Account number is required';
    }
    if (!RegExp(r'^\d{9,18}$').hasMatch(text)) {
      return 'Enter a 9–18 digit account number';
    }
    return null;
  }

  static String? validateRequired(String? value, String field) =>
      (value ?? '').trim().isEmpty ? 'Enter the $field' : null;

  /// Registers a new agent under [parent] once their phone has been verified.
  /// Returns null on success, or the first thing wrong with the submission.
  String? registerAgent({
    required Agent parent,
    required AgentLevel level,
    required String firstName,
    String middleName = '',
    required String lastName,
    required String phone,
    required DateTime dob,
    required String aadhaar,
    required String pan,
    required String address,
    required String pincode,
    required String place,
    required String accountNumber,
    Uint8List? photoBytes,
    bool active = true,
  }) {
    if (byId(parent.id) == null) {
      return 'That parent agent no longer exists';
    }
    if (level.index <= parent.level.index) {
      return '${level.label} is not below ${parent.level.label}';
    }
    if (openPositionsUnder(parent) <= 0) {
      return 'Every position under ${parent.name} is already filled';
    }

    final checks = <String?>[
      validateName(firstName, field: 'first name'),
      validateMiddleName(middleName),
      validateName(lastName, field: 'last name'),
      validatePhone(phone),
      validateAadhaar(aadhaar),
      validatePan(pan),
      validateRequired(address, 'address'),
      validatePincode(pincode),
      validateRequired(place, 'place'),
      validateAccountNumber(accountNumber),
    ];
    for (final failure in checks) {
      if (failure != null) {
        return failure;
      }
    }

    final first = firstName.trim();
    final middle = middleName.trim();
    final last = lastName.trim();
    final cleanPlace = place.trim();

    _added++;
    _agents.add(
      Agent(
        id: 'add-$_added',
        name: [first, middle, last].where((p) => p.isNotEmpty).join(' '),
        phone: phone.trim(),
        agentCode: _mintCode(level),
        level: level,
        active: active,
        parentId: parent.id,
        area: cleanPlace,
        firstName: first,
        middleName: middle,
        lastName: last,
        dob: dob,
        aadhaar: aadhaar.replaceAll(' ', ''),
        pan: pan.trim().toUpperCase(),
        address: address.trim(),
        pincode: pincode.trim(),
        place: cleanPlace,
        accountNumber: accountNumber.trim(),
        // The profile photo is captured here at registration and nowhere
        // else — the agent's own detail screen only ever shows it.
        photoBytes: photoBytes,
        // Approved on the spot — registering someone is the recruiter's own
        // decision, made with a live OTP check already behind it, so there
        // is nothing further to gate them on. [Agent]'s own default already
        // reads this way; spelled out here so it stays true on purpose.
        approvalStatus: AgentApprovalStatus.approved,
      ),
    );
    notifyListeners();
    return null;
  }

  // ---- Approval ----

  /// [parent] signs off on [agent], or turns them away. Either way this is
  /// the one thing a pending recruit is waiting on — approving unlocks their
  /// real figures ([Agent.displayEarned] and the rest) and the ability to
  /// recruit under themselves; rejecting leaves them on the roster, visibly
  /// refused, rather than silently deleting a submission that was made in
  /// good faith.
  void setApproval(Agent agent, AgentApprovalStatus status) {
    final index = _agents.indexWhere((a) => a.id == agent.id);
    if (index < 0) {
      return;
    }
    _agents[index] = _agents[index].withApprovalStatus(status);
    notifyListeners();
  }

  /// `SHD-WRD-004` — the next free code for [level].
  String _mintCode(AgentLevel level) {
    final prefix = 'SHD-${level.code}-';
    var highest = 0;
    for (final agent in _agents) {
      if (agent.agentCode.startsWith(prefix)) {
        final n = int.tryParse(agent.agentCode.substring(prefix.length));
        if (n != null && n > highest) {
          highest = n;
        }
      }
    }
    return '$prefix${(highest + 1).toString().padLeft(3, '0')}';
  }

  // ---- Withdrawals ----

  /// Every request [agent] has raised, newest first.
  List<WithdrawalRequest> requestsFor(Agent agent) => List.unmodifiable(
    (_requests[agent.id] ?? const <WithdrawalRequest>[]).reversed,
  );

  /// The total of [agent]'s requests still awaiting payout — held back from
  /// [withdrawableFor] so an amount cannot be asked for twice.
  int pendingFor(Agent agent) => (_requests[agent.id] ?? const [])
      .where((request) => request.status == WithdrawalStatus.pending)
      .fold(0, (sum, request) => sum + request.amount);

  int earnedFor(Agent agent) => agent.displayEarned;

  /// What [agent] has taken out of the commission pot: paid out on the seed
  /// data, plus anything moved into the wallet from the portal this session.
  /// Zero while the agent is still awaiting approval, same as [earnedFor] —
  /// there is nothing to have taken out of a pot that reads zero.
  int redeemedFor(Agent agent) =>
      agent.isApproved ? agent.redeemed + movedToWalletFor(agent) : 0;

  /// Commission [agent] has moved into their SHIELD wallet this session.
  int movedToWalletFor(Agent agent) => _movedToWallet[agent.id] ?? 0;

  /// What [agent] could ask to withdraw right now: earned, less what has been
  /// taken out ([redeemedFor]), less what is already in flight. Never negative.
  int withdrawableFor(Agent agent) =>
      (agent.displayEarned - redeemedFor(agent) - pendingFor(agent))
          .clamp(0, agent.displayEarned)
          .toInt();

  /// Raises a withdrawal request for [amount]. Returns null on success, or the
  /// reason it was refused.
  String? requestWithdrawal(Agent agent, int amount) {
    if (amount < minWithdrawal) {
      return 'Minimum withdrawal is ₹${formatRupees(minWithdrawal)}';
    }
    if (amount > withdrawableFor(agent)) {
      return 'Amount exceeds your withdrawable balance';
    }

    (_requests[agent.id] ??= <WithdrawalRequest>[]).add(
      WithdrawalRequest(amount: amount, requestedOn: DateTime.now()),
    );
    notifyListeners();
    return null;
  }

  /// Moves [amount] of [agent]'s withdrawable commission into the SHIELD
  /// wallet, where it can be spent in the app straight away. Returns null on
  /// success, or the reason it was refused.
  String? moveEarningsToWallet(Agent agent, int amount) {
    if (amount <= 0) {
      return 'Enter an amount to add';
    }
    if (amount > withdrawableFor(agent)) {
      return 'Amount exceeds your withdrawable balance';
    }

    _movedToWallet[agent.id] = movedToWalletFor(agent) + amount;
    WalletService.instance.creditEarnings(
      amount: amount,
      label: 'Agent commission · ${agent.agentCode}',
    );
    notifyListeners();
    return null;
  }

  // ---- Team roll-ups ----

  /// The sub-agents [agent] recruited — the "Direct sale" list.
  List<Agent> directSubAgentsOf(Agent agent) => childrenOf(agent.id);

  /// Everyone anywhere below [agent] in the tree.
  List<Agent> teamOf(Agent agent) => descendantsOf(agent.id);

  int teamMemberCount(Agent agent) => teamOf(agent).length;

  int activeMemberCount(Agent agent) =>
      teamOf(agent).where((member) => member.active).length;

  /// Total sales closed anywhere in [agent]'s downline. A member still
  /// awaiting approval contributes nothing — see [Agent.displayPersonalSales].
  int teamSalesTotal(Agent agent) => teamOf(
    agent,
  ).fold(0, (sum, member) => sum + member.displayPersonalSales);

  /// Override commission [agent] earns on that downline volume.
  int teamCommission(Agent agent) =>
      teamSalesTotal(agent) * commissionPercent ~/ 100;

  /// What the viewing agent earns as override commission from one team
  /// member's own sales — [commissionPercent]% of [Agent.personalSales]. The
  /// per-row figure the team roster shows against each name; [teamCommission]
  /// is the same rate taken over the whole downline at once rather than
  /// member by member.
  int commissionFrom(Agent member) =>
      member.displayPersonalSales * commissionPercent ~/ 100;

  /// The members of [agent]'s downline that sit at [level], for the per-tier
  /// breakdown on the Team Sales card.
  List<Agent> teamAtLevel(Agent agent, AgentLevel level) =>
      teamOf(agent).where((member) => member.level == level).toList();

  @visibleForTesting
  void reset() {
    _requests.clear();
    _movedToWallet.clear();
    _agents
      ..clear()
      ..addAll(AgentDirectory.seed);
    _customers
      ..clear()
      ..addAll(AgentCustomerDirectory.seed);
    _added = 0;
    notifyListeners();
  }
}
