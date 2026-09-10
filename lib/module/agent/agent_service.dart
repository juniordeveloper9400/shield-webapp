import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/neon/agent_repository.dart';
import '../../money.dart';
import '../auth/auth_service.dart';
import '../wallet/wallet_service.dart';
import 'agent_customer.dart';
import 'agent_customer_directory.dart';
import 'agent_directory.dart';
import 'agent_model.dart';

/// The live agent roster plus the withdrawal ledger.
///
/// Modelled on [ChangeNotifier] the same way `RegistrationService` is — a
/// single instance, getters for the derived figures, mutators that call
/// `notifyListeners()`, and a `@visibleForTesting` [reset]. The roster starts
/// as a copy of [AgentDirectory.seed] and [ensureLoaded] folds in every real
/// row already in `app.agent` on top of that; [registerAgent] writes new
/// ones there too ([AgentRepository]), best-effort — the in-memory list here
/// is what the UI actually reads, and stays correct even if the database
/// write never lands.
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

  bool _remoteLoaded = false;
  Future<void>? _remoteLoadInFlight;

  /// The database row id behind each agent already known to have one —
  /// [AgentDirectory.national] once the first registration under it has
  /// needed one, and every agent registered this session. A `Future` (not
  /// just the resolved id) so a grandchild registered moments after its
  /// parent — before the parent's own insert has actually landed — awaits
  /// the very same in-flight write rather than racing it: [_dbIdFor]
  /// caches and returns this before the insert it wraps has necessarily
  /// finished.
  final Map<String, Future<int?>> _dbId = {};

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

  /// Loads every agent already in `app.agent`, folding them into the roster
  /// below the seed national persona — best-effort, matching
  /// `AgentGeo.ensureLoaded`'s contract (a missing `DATABASE_URL` or a
  /// network blip just leaves the seed-only roster in place). Safe to call
  /// from every screen's `initState`; only the first call does any work.
  Future<void> ensureLoaded() {
    if (_remoteLoaded) {
      return Future<void>.value();
    }
    return _remoteLoadInFlight ??= _loadFromServer();
  }

  Future<void> _loadFromServer() async {
    try {
      final approved = await AgentRepository.instance.fetchAll();
      final pending = await AgentRepository.instance.fetchPendingRequests();
      final remote = <Agent>[
        if (approved != null) ...approved,
        if (pending != null) ...pending,
      ];
      if (remote.isEmpty) {
        return;
      }
      // Skip any approved row that is the seed root's own database counterpart
      // — written the first time a registration under it needed one to parent
      // under — so the national persona never shows twice. Pending requests
      // keep their `req-` ids and never collide.
      final have = _agents.map((a) => a.phone).toSet();
      final ids = _agents.map((a) => a.id).toSet();
      final fresh = remote
          .where((a) => !ids.contains(a.id) && !have.contains(a.phone))
          .toList();
      if (fresh.isEmpty) {
        return;
      }
      _agents.addAll(fresh);
      // Cache the real database id for every approved fetched row so a
      // registration under one of them resolves its parent id immediately.
      for (final agent in fresh) {
        if (agent.id.startsWith('db-')) {
          final dbId = int.tryParse(agent.id.substring(3));
          if (dbId != null) {
            _dbId[agent.id] = Future.value(dbId);
          }
        }
      }
      notifyListeners();
    } finally {
      _remoteLoaded = true;
      _remoteLoadInFlight = null;
    }
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

  /// The phone of the agent row applied from Neon by `PersonaService` (a member
  /// the Super Admin converted), held so it can be swapped cleanly.
  String? _remoteAgentPhone;

  /// Applies — or, with null, removes — the `app.agent` row the console created
  /// for the signed-in member. Keyed on phone, so [agentForPhone] and every
  /// tree getter pick it up with nothing else to change.
  void applyRemoteAgent(Agent? agent) {
    var changed = false;
    final prev = _remoteAgentPhone;
    if (prev != null && (agent == null || agent.phone != prev)) {
      _agents.removeWhere((a) => a.phone == prev);
      _remoteAgentPhone = null;
      changed = true;
    }
    if (agent != null) {
      final index = _agents.indexWhere((a) => a.phone == agent.phone);
      if (index >= 0) {
        _agents[index] = agent;
      } else {
        _agents.add(agent);
      }
      _remoteAgentPhone = agent.phone;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// The agents reporting directly to [id], in insertion order.
  List<Agent> childrenOf(String id) =>
      _agents.where((agent) => agent.parentId == id).toList(growable: false);

  /// [childrenOf], minus anyone an admin rejected — a rejected registration
  /// gives its slot back, so it must not count against capacity or hold a
  /// named position.
  List<Agent> _slotHoldersUnder(String id) => childrenOf(id)
      .where((a) => a.approvalStatus != AgentApprovalStatus.rejected)
      .toList(growable: false);

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

  /// The fixed named slots directly under [parent] — the six zones under a
  /// national agent, or a zone's states under a region agent — or an empty
  /// list where the tier just uses the plain doubling shape.
  ///
  /// Id-keyed ([GeoSlot], not a bare name) — see the doc on [Agent.areaId]
  /// for why matching on name alone breaks against the real Kerala data.
  List<GeoSlot> slotsUnder(Agent parent) =>
      AgentGeo.current.slotsUnder(parent.level, parent.areaId);

  /// How many more agents [parent] can take on directly, before every
  /// position under them is filled.
  ///
  /// Where the tier below is a fixed set of named slots ([slotsUnder] — the
  /// zones, or a zone's states) the budget is that set's size; otherwise it
  /// is [AgentLevel.childCapacity], the same budget whatever tier each
  /// direct report actually ends up registered at.
  int openPositionsUnder(Agent parent) {
    final slots = slotsUnder(parent);
    final capacity =
        slots.isNotEmpty ? slots.length : parent.level.childCapacity;
    return (capacity - _slotHoldersUnder(parent.id).length).clamp(0, capacity);
  }

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
    /// The named slot this agent fills — a zone for a region agent, a state
    /// for a state agent. Becomes their [Agent.area] / [Agent.areaId]; falls
    /// back to [place] (with no id) when the tier has no named slots.
    GeoSlot? slot,
    Uint8List? photoBytes,
    bool active = true,
  }) {
    final resolvedParent = byId(parent.id);
    if (resolvedParent == null) {
      return 'That parent agent no longer exists';
    }
    if (resolvedParent.isPending) {
      return '${resolvedParent.name} is still awaiting approval and cannot '
          'recruit yet.';
    }
    // The national agent is the single seeded persona at the top of the tree.
    // There is only ever one, and nobody is registered *at* that tier.
    if (level == AgentLevel.national) {
      return 'There is already a national agent — only one is allowed. '
          'Register this person at region level or below.';
    }
    if (level.index <= parent.level.index) {
      return '${level.label} is not below ${parent.level.label}';
    }
    // A region agent heads one of the six fixed zones, picked from a list.
    if (level == AgentLevel.region &&
        !AgentGeo.current.regions.any((r) => r.id == slot?.id)) {
      return 'Choose which region this agent heads';
    }
    // Capacity and one-agent-per-slot are NOT checked here — the recruiter may
    // request any region / any level, and the admin console decides on approval
    // (which caps at one national + six regions and rejects a slot that is
    // already taken). This screen only captures the request.

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

    // What the agent heads: the named slot they filled (a zone / a state),
    // falling back to their home place — with no id, since it names nothing
    // in the hierarchy — where the tier has no named slots.
    final headArea = slot?.name ?? cleanPlace;

    _added++;
    final newAgent = Agent(
      id: 'add-$_added',
      name: [first, middle, last].where((p) => p.isNotEmpty).join(' '),
      phone: phone.trim(),
      agentCode: _mintCode(level),
      level: level,
      // Off and pending until an admin reviews the KYC and sets the position
      // in the console. `active` (the caller's arg) only takes effect once
      // approved.
      active: false,
      parentId: parent.id,
      area: headArea,
      areaId: slot?.id,
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
      // Pending: the recruit has proven their number over a real OTP, but an
      // admin still reviews the KYC and fixes the level/position in the console
      // before they can work. The card shows a "Pending approval" tag and every
      // figure reads zero (see [Agent.displayEarned]) until then.
      approvalStatus: AgentApprovalStatus.pending,
    );
    _agents.add(newAgent);
    // Fire-and-forget the app.agent_request write. Not cached under the new
    // agent's id: a pending recruit cannot be a parent (guarded above), and
    // once the admin approves them they come back from fetchAll() with a real
    // db-<id> anyway.
    unawaited(_persistNew(newAgent, parent));
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

  /// The database row id for [agent] — resolving (and caching, via [_dbId])
  /// it the first time anything needs it. The seed national persona has no
  /// row of its own until the first registration under it asks for one
  /// ([AgentRepository.ensureNationalRow]); every other agent already has
  /// one cached — a fetched row from [_loadFromServer], or its own
  /// [_persistNew] future kicked off at the moment it was registered.
  Future<int?> _dbIdFor(Agent agent) {
    return _dbId[agent.id] ??= agent.id == AgentDirectory.national.id
        ? AgentRepository.instance.ensureNationalRow(
            phone: agent.phone,
            name: agent.name,
            code: agent.agentCode,
          )
        : Future.value(null);
  }

  /// Files [agent] as an `app.agent_request` under [parent] for the admin
  /// console to approve — the app never writes `app.agent` itself. Best-effort:
  /// a missing `DATABASE_URL` or a network blip just leaves the request in this
  /// session's roster (as a pending card) and absent from the database.
  ///
  /// The parent's own database id is passed through when known, but a null one
  /// is fine — the admin confirms the parent on approval anyway.
  Future<int?> _persistNew(Agent agent, Agent parent) async {
    final parentDbId = await _dbIdFor(parent);
    return AgentRepository.instance.insertAgentRequest(
      parentDbId: parentDbId,
      level: agent.level,
      name: agent.name,
      phone: agent.phone,
      area: agent.area,
      areaId: agent.areaId,
      firstName: agent.firstName,
      middleName: agent.middleName,
      lastName: agent.lastName,
      dob: agent.dob!,
      aadhaar: agent.aadhaar,
      pan: agent.pan,
      address: agent.address,
      pincode: agent.pincode,
      place: agent.place,
      accountNumber: agent.accountNumber,
    );
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
    _dbId.clear();
    _remoteLoaded = false;
    _remoteLoadInFlight = null;
    notifyListeners();
  }
}
