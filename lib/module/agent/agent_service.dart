import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/backend/agent_customer_repository.dart';
import '../../data/backend/agent_repository.dart';
import '../../money.dart';
import '../auth/auth_service.dart';
import '../wallet/wallet_service.dart';
import 'agent_customer.dart';
import 'agent_customer_directory.dart';
import 'agent_directory.dart';
import 'agent_model.dart';
import 'withdrawal_policy.dart';

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
  static const int minWithdrawal = minimumAgentWithdrawal;
  final Set<String> _withdrawalsLoaded = {};

  /// The decaying override an agent earns on a downline member's own
  /// personal sales, indexed by how many real `parentId` hops separate the
  /// two — hop 1 (the member's own immediate manager) down to hop 6 (the
  /// deepest possible, ward up to national). Mirrors the real backend split
  /// exactly (`app.approve_wallet_card_activation`'s `v_hop_rates`,
  /// migrations 0036-0039): each hop's rate here times
  /// [commissionPoolPercent] gives the same percentage of the sale amount
  /// the backend actually credits — e.g. hop 1 is 10% of the 10% pool = 1%
  /// of the sale. There used to be one flat `commissionPercent` (2%) applied
  /// to every downline member regardless of distance; that only happened to
  /// be correct for a member 6 hops away and badly under-counted anyone
  /// closer, so it's gone in favour of walking the real chain below.
  static const List<int> hopOverridePercents = [10, 6, 5, 4, 3, 2];

  /// The whole commission pool set aside from a loaded amount — 10%, same
  /// as [directCommissionPercent]'s own 60%-of-this-pool doc explains.
  static const int commissionPoolPercent = 10;

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

  /// Earnings each agent has moved into their Sahakar 360 wallet, keyed by agent
  /// id. Counts against [withdrawableFor] the same way a paid-out request
  /// would — the money has left the commission pot either way.
  final Map<String, int> _movedToWallet = {};

  /// Every customer any agent has sold a plan to.
  final List<AgentCustomer> _customers = [...AgentCustomerDirectory.seed];

  // ---- Roster ----

  /// Whether [ensureLoaded]'s remote fetch has settled — a screen showing
  /// the roster (the team-sales rollup, the member list) reads this to
  /// decide between its own skeleton and the real thing, so a still-cold
  /// backend reads as "loading" rather than as a team of zero.
  bool get isTeamLoaded => _remoteLoaded;

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

  /// Loads the signed-in agent's own subtree from the backend, folding it
  /// into the roster below the seed national persona — best-effort,
  /// matching `AgentGeo.ensureLoaded`'s contract (an unconfigured backend,
  /// not being signed in to it, or a network blip just leaves the seed-only
  /// roster in place). Safe to call from every screen's `initState`; only
  /// the first call does any work.
  String? loadError;
  int _loadGeneration = 0;
  Future<List<Agent>?> Function()? _teamLoader;
  Future<List<Agent>?> Function()? _pendingLoader;
  Future<List<AgentCustomer>?> Function(String)? _customerLoader;

  @visibleForTesting
  void debugSetLoaders({
    required Future<List<Agent>?> Function() team,
    required Future<List<Agent>?> Function() pending,
    required Future<List<AgentCustomer>?> Function(String) customers,
  }) {
    _teamLoader = team;
    _pendingLoader = pending;
    _customerLoader = customers;
  }

  Future<void> ensureLoaded() {
    if (_remoteLoaded) return Future<void>.value();
    return refresh();
  }

  Future<void> refresh() {
    return _remoteLoadInFlight ??= _loadFromServer();
  }

  Future<void> _loadFromServer() async {
    final generation = _loadGeneration;
    try {
      final approved =
          await (_teamLoader ?? AgentRepository.instance.fetchAll)();
      if (generation != _loadGeneration) return;
      if (approved == null || approved.isEmpty) {
        loadError = 'Could not load agent sales. Please retry.';
        return;
      }
      final pending =
          await (_pendingLoader ??
              AgentRepository.instance.fetchPendingRequests)();
      if (generation != _loadGeneration) return;
      // The authenticated team endpoint returns the caller first. Phone
      // formatting in the admin profile can differ from the login number.
      final self = approved.first;
      final customers =
          await (_customerLoader ?? AgentCustomerRepository.instance.fetchAll)(
            self.id,
          );
      if (generation != _loadGeneration) return;
      final remote = [...approved, if (pending != null) ...pending];
      final ids = remote.map((a) => a.id).toSet();
      _agents.removeWhere((a) => a.id.startsWith('db-') && !ids.contains(a.id));
      if (pending != null) _agents.removeWhere((a) => a.id.startsWith('req-'));
      for (final row in remote) {
        final index = _agents.indexWhere((a) => a.id == row.id);
        if (index < 0) {
          _agents.add(row);
        } else {
          _agents[index] = row;
        }
        if (row.id.startsWith('db-')) {
          final id = int.tryParse(row.id.substring(3));
          if (id != null) _dbId[row.id] = Future.value(id);
        }
      }
      // A real agent row with no `parentId` (an admin converted them with no
      // parent chosen) is mapped by `AgentRepository` onto the seed national
      // placeholder's id, since that mapping happens one row at a time with
      // no view of the rest of the roster. Once a real national agent has
      // actually been fetched, reparent any such row onto that real id
      // instead — otherwise `ancestorsOf` never walks through the national
      // agent actually signed in, and every override commission they should
      // earn on that row computes as zero even though `descendantsOf`
      // (which special-cases national separately) already counts the sale
      // in their team total.
      final realNational = remote
          .where(
            (a) =>
                a.level == AgentLevel.national &&
                a.id != AgentDirectory.national.id,
          )
          .firstOrNull;
      if (realNational != null) {
        for (var i = 0; i < _agents.length; i++) {
          final agent = _agents[i];
          if (agent.id != realNational.id &&
              agent.parentId == AgentDirectory.national.id) {
            _agents[i] = agent.withParentId(realNational.id);
          }
        }
      }
      if (customers != null) {
        _customers.removeWhere((c) => c.agentId == self.id);
        _customers.addAll(customers);
      }
      loadError = customers == null || pending == null
          ? 'Some agent records could not be refreshed. Please retry.'
          : null;
      _remoteLoaded = true;
    } catch (_) {
      if (generation == _loadGeneration) {
        loadError = 'Could not load agent sales. Please retry.';
      }
    } finally {
      if (generation == _loadGeneration) {
        _remoteLoadInFlight = null;
        notifyListeners();
      }
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

  /// The agent for [phone], or null when the number is not an **approved**
  /// agent's. This is what decides whether a signed-in member sees agent-facing
  /// UI (the home screen's Agent Portal card, the menu's "Agent portal" row) —
  /// so a number with a pending or rejected registration is not matched: only
  /// someone the admin has actually approved is an agent as far as the rest of
  /// the app is concerned.
  Agent? agentForPhone(String? phone) {
    if (phone == null) {
      return null;
    }
    final clean = phone.trim();
    if (clean == _remoteAgentPhone && _remoteAgentId != null) {
      final remote = byId(_remoteAgentId!);
      if (remote != null && remote.isApproved) return remote;
    }
    for (final agent in _agents) {
      if (agent.phone == clean && agent.isApproved) {
        return agent;
      }
    }
    return null;
  }

  /// The phone of the agent row applied from Neon by `PersonaService` (a member
  /// the Super Admin converted), held so it can be swapped cleanly.
  String? _remoteAgentPhone;
  String? _remoteAgentId;

  /// Applies — or, with null, removes — the `app.agent` row the console created
  /// for the signed-in member. Keyed on phone, so [agentForPhone] and every
  /// tree getter pick it up with nothing else to change.
  void applyRemoteAgent(Agent? agent) {
    var changed = false;
    final prev = _remoteAgentPhone;
    if (prev != null && (agent == null || agent.phone != prev)) {
      _agents.removeWhere((a) => a.id == _remoteAgentId);
      _remoteAgentPhone = null;
      _remoteAgentId = null;
      changed = true;
    }
    if (agent != null) {
      final index = _agents.indexWhere((a) => a.id == agent.id);
      if (index >= 0) {
        _agents[index] = agent;
      } else {
        _agents.add(agent);
      }
      _remoteAgentPhone = agent.phone;
      _remoteAgentId = agent.id;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// The agents reporting directly to [id], in insertion order.
  List<Agent> childrenOf(String id) =>
      _agents.where((agent) => agent.parentId == id).toList(growable: false);

  /// Whoever actually holds the named geo position [slotId] — a region, a
  /// district, a ward — regardless of how far their real `parentId` chain
  /// skips to get there.
  ///
  /// `parentId` intentionally skips straight past any tier nobody has been
  /// registered into yet (so a hop-based commission override always reaches
  /// the nearest real ancestor, not a vacant seat — see [ancestorsOf]'s own
  /// doc). "My Team"'s org-chart tree must not read that shortcut as the
  /// tree's own shape, though: an assembly agent registered under an empty
  /// region and district still sits at that assembly position, under that
  /// empty region and district drawn as open "+" seats — not flattened up
  /// next to the region row itself, which is what a lookup keyed off
  /// [childrenOf] alone would draw. This is the whole-roster, id-matched
  /// lookup the tree walks by instead: see `_MindNode`/`_MindPlusNode` in
  /// `agent_team_tree_screen.dart`.
  Agent? agentAtSlot(String slotId) => _agents
      .where(
        (a) =>
            a.areaId == slotId &&
            a.approvalStatus != AgentApprovalStatus.rejected,
      )
      .firstOrNull;

  /// [childrenOf], minus anyone an admin rejected — a rejected registration
  /// gives its slot back, so it must not count against capacity or hold a
  /// named position.
  List<Agent> _slotHoldersUnder(String id) => childrenOf(id)
      .where((a) => a.approvalStatus != AgentApprovalStatus.rejected)
      .toList(growable: false);

  /// Every agent anywhere below [id] in the tree. [id] itself is not
  /// included.
  ///
  /// A national agent is meant to be the one root everyone eventually
  /// reports up to — but real data can leave someone unreachable by a plain
  /// parent-chain walk (an agent an admin converted with no parent chosen,
  /// say), so a national agent's own downline is simply every other
  /// non-national agent, not just whoever a correct chain of `parentId`
  /// happens to connect back to them. Below national, this still walks the
  /// real chain — a region or state agent only ever sees what actually
  /// reports to them.
  List<Agent> descendantsOf(String id) {
    if (byId(id)?.level == AgentLevel.national) {
      return _agents
          .where((a) => a.id != id && a.level != AgentLevel.national)
          .toList(growable: false);
    }
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
      AgentGeo.current.slotsUnder(
        parent.level,
        (parent.areaId != null && parent.areaId!.isNotEmpty)
            ? parent.areaId
            : (parent.area.isNotEmpty ? parent.area : null),
      );

  /// How many more agents [parent] can take on directly, before every
  /// position under them is filled.
  ///
  /// Where the tier below is a fixed set of named slots ([slotsUnder] — the
  /// zones, or a zone's states) the budget is that set's size; otherwise it
  /// is [AgentLevel.childCapacity], the same budget whatever tier each
  /// direct report actually ends up registered at.
  int openPositionsUnder(Agent parent) {
    final slots = slotsUnder(parent);
    final capacity = slots.isNotEmpty
        ? slots.length
        : parent.level.childCapacity;
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
  /// commission — richer than the [hopOverridePercents] override any single
  /// upline agent earns on downline volume, because a direct sale is the
  /// agent's own work. Mirrors the
  /// real backend split (`app.approve_wallet_card_activation`, migrations
  /// 0033-0040): 10% of the load is the commission pool, and 60% of that
  /// pool goes to the direct seller — 10% × 60% = 6%. This was a stale 5%
  /// left over from before that function existed; it must track whatever
  /// `COMMISSION_POOL_RATE × DIRECT_SALE_SHARE_RATE` comes to on the
  /// backend (`wallet.service.ts`), or this card's own number stops
  /// matching what the agent is actually paid.
  static const int directCommissionPercent = 6;

  /// What [agent] earned on one card.
  int commissionOnPlan(CustomerPlan plan) =>
      plan.amount * directCommissionPercent ~/ 100;

  /// What [agent] earned across every card one customer holds.
  int commissionOnSale(AgentCustomer customer) =>
      customer.plans.fold(0, (sum, p) => sum + commissionOnPlan(p));

  /// What [agent]'s own direct sales have earned them in total.
  int directSaleEarnings(Agent agent) =>
      customersOf(agent).fold(0, (sum, c) => sum + commissionOnSale(c));

  /// The combined card value of every direct sale [agent] has made.
  int directSaleVolume(Agent agent) =>
      customersOf(agent).fold(0, (sum, c) => sum + c.totalAmount);

  @visibleForTesting
  void addCustomer(AgentCustomer customer) {
    _customers.add(customer);
    notifyListeners();
  }

  /// Drops a fully-formed [agent] straight onto the roster — for building a
  /// synthetic parent chain in a test without going through the
  /// registration flow.
  @visibleForTesting
  void addAgent(Agent agent) {
    _agents.add(agent);
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

  static String? validatePhone(String? value) =>
      AuthService.validatePhone(value);

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
  /// it the first time anything needs it. Every non-seed agent already has
  /// one cached — a fetched row from [_loadFromServer], or its own
  /// [_persistNew] future kicked off at the moment it was registered.
  ///
  /// The seed national persona is a local UI placeholder only — it has no
  /// row of its own, and nothing here creates one. Filing a request under it
  /// submits `parentAgentId: null`; the staff console resolves the real
  /// parent on approval regardless of what the client sent (see
  /// [_persistNew]'s doc). Older versions of this app inserted an
  /// `APPROVED` `app.agent` row directly for exactly this case, with no
  /// "only one national agent" guard — the real cause of the two live
  /// NATIONAL rows recorded in `docs/decision-log.md`. That path is
  /// retired, not ported.
  Future<int?> _dbIdFor(Agent agent) {
    return _dbId[agent.id] ??= Future.value(null);
  }

  /// Files [agent] as an `app.agent_request` under [parent] for the admin
  /// console to approve — the app never writes `app.agent` itself. Best-effort:
  /// an unconfigured backend or a network blip just leaves the request in
  /// this session's roster (as a pending card) and absent from the database.
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

  int earnedFor(Agent agent) =>
      (agentForPhone(agent.phone) ?? agent).displayEarned;

  /// What [agent] has taken out of the commission pot: paid out on the seed
  /// data, plus anything moved into the wallet from the portal this session.
  /// Zero while the agent is still awaiting approval, same as [earnedFor] —
  /// there is nothing to have taken out of a pot that reads zero.
  int redeemedFor(Agent agent) {
    agent = agentForPhone(agent.phone) ?? agent;
    return agent.isApproved ? agent.redeemed + movedToWalletFor(agent) : 0;
  }

  /// Commission [agent] has moved into their Sahakar 360 wallet this session.
  int movedToWalletFor(Agent agent) => _movedToWallet[agent.id] ?? 0;

  /// What [agent] could ask to withdraw right now: earned, less what has been
  /// taken out ([redeemedFor]), less what is already in flight. Never negative.
  int availableEarningsFor(Agent agent) =>
      (earnedFor(agent) - redeemedFor(agent) - pendingFor(agent))
          .clamp(0, earnedFor(agent))
          .toInt();

  int withdrawableFor(Agent agent) {
    final current = agentForPhone(agent.phone) ?? agent;
    if (!current.active || !current.isApproved) return 0;
    if (!_withdrawalsLoaded.contains(agent.phone)) return 0;
    return eligibleWithdrawalAmount(
      earned: earnedFor(agent),
      redeemed: redeemedFor(agent),
      pending: pendingFor(agent),
    );
  }

  Future<void> refreshWithdrawals(Agent agent) async {
    try {
      final requests = await AgentRepository.instance.fetchWithdrawals();
      final roster = await AgentRepository.instance.fetchAll();
      if (roster == null) return;
      if (AuthService.instance.currentUser.value?.phone != agent.phone) return;
      _requests[agent.id] = requests;
      _withdrawalsLoaded.add(agent.phone);
      for (final row in roster) {
        final index = _agents.indexWhere(
          (a) => a.id == row.id || a.phone == row.phone,
        );
        if (index >= 0) _agents[index] = row;
        if (row.phone == agent.phone) _requests[row.id] = requests;
      }
      notifyListeners();
    } catch (_) {
      // Keep the last confirmed history; a request is always rechecked by the server.
    }
  }

  /// Raises a withdrawal request for [amount]. Returns null on success, or the
  /// reason it was refused.
  Future<String?> requestWithdrawal(Agent agent, int amount) async {
    if (amount < minWithdrawal) {
      return 'Minimum withdrawal is ₹${formatRupees(minWithdrawal)}';
    }
    if (amount > withdrawableFor(agent)) {
      return 'Amount exceeds your withdrawable balance';
    }

    try {
      await AgentRepository.instance.requestWithdrawal(amount);
      _requests[agent.id] = await AgentRepository.instance.fetchWithdrawals();
    } catch (_) {
      return 'Could not confirm the request. Refresh before trying again.';
    }
    notifyListeners();
    return null;
  }

  /// Moves [amount] of [agent]'s withdrawable commission into the Sahakar 360
  /// wallet, where it can be spent in the app straight away. Returns null on
  /// success, or the reason it was refused.
  String? moveEarningsToWallet(Agent agent, int amount) {
    if (amount <= 0) {
      return 'Enter an amount to add';
    }
    if (amount > availableEarningsFor(agent)) {
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
  int teamSalesTotal(Agent agent) =>
      teamOf(agent).fold(0, (sum, member) => sum + member.displayPersonalSales);

  /// How many real `parentId` hops separate [member] from [ancestor] —
  /// 1 when [ancestor] is [member]'s own immediate parent, 2 for a
  /// grandparent, and so on. Null when [ancestor] is not actually found by
  /// walking [member]'s real chain within [hopOverridePercents]' own
  /// length — a broken or unusually deep chain simply earns no override
  /// past that point, the same way the backend's own hop-walk stops rather
  /// than guessing (see `approve_wallet_card_activation`'s own doc).
  int? _hopDistance(Agent ancestor, Agent member) {
    final chain = ancestorsOf(member.id);
    final index = chain.indexWhere((a) => a.id == ancestor.id);
    if (index == -1 || index >= hopOverridePercents.length) {
      return null;
    }
    return index + 1;
  }

  /// What the viewing agent earns as override commission from one team
  /// member's own sales — the exact same decaying hop rate the backend
  /// actually credits, not a flat guess: [member]'s real distance from
  /// [agent] picks the rate out of [hopOverridePercents], applied to
  /// [commissionPoolPercent] of what they personally sold. Zero when
  /// [member] is more hops away than the table covers, or their chain
  /// never actually reaches [agent] (see [_hopDistance]).
  int commissionFrom(Agent agent, Agent member) {
    final hop = _hopDistance(agent, member);
    if (hop == null) {
      return 0;
    }
    final pool = member.displayPersonalSales * commissionPoolPercent ~/ 100;
    return pool * hopOverridePercents[hop - 1] ~/ 100;
  }

  /// Override commission [agent] earns across their whole downline — the
  /// sum of [commissionFrom] over every real team member, each at their own
  /// real distance from [agent] rather than one flat rate for all of them.
  int teamCommission(Agent agent) => teamOf(
    agent,
  ).fold(0, (sum, member) => sum + commissionFrom(agent, member));

  /// The members of [agent]'s downline that sit at [level], for the per-tier
  /// breakdown on the Team Sales card.
  List<Agent> teamAtLevel(Agent agent, AgentLevel level) =>
      teamOf(agent).where((member) => member.level == level).toList();

  /// Drops everything [ensureLoaded] fetched (and every locally-added row)
  /// back to the seed-only roster, and lets a later [ensureLoaded] fetch
  /// again. `ensureLoaded` only ever runs its remote fetch once per app
  /// lifetime (`_remoteLoaded`), so without this a member who signs out and
  /// a different member who then signs in on the same device inherits the
  /// first member's entire fetched roster — including a phantom "team"
  /// made of whoever the first member's downline was, since nothing here
  /// keys any of this state on which member is actually signed in. Call on
  /// sign-out (see `PersonaService.clear()`) so the next sign-in starts
  /// clean. Local session-only state (this session's own withdrawal
  /// requests, wallet transfers, registrations) goes with it too — none of
  /// it means anything for whoever signs in next.
  void reset() {
    _loadGeneration++;
    loadError = null;
    _teamLoader = null;
    _pendingLoader = null;
    _customerLoader = null;
    _withdrawalsLoaded.clear();
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
    _remoteAgentPhone = null;
    _remoteAgentId = null;
    _remoteLoaded = false;
    _remoteLoadInFlight = null;
    notifyListeners();
  }
}
