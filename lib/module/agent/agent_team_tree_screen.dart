import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/backend/backend_http.dart';
import '../../theme/app_colors.dart';
import 'agent_detail_screen.dart';
import 'agent_directory.dart';
import 'agent_model.dart';
import 'agent_registration_screen.dart';
import 'agent_service.dart';

/// "My Team": the downline drawn as a top-to-bottom mind-map. The root sits
/// alone at the top; a round chevron button hangs off the bottom edge of any
/// card that has a tier below it. Tapping that button fans the card's own row
/// of children out beneath it — the registered downline plus the positions
/// nobody has filled yet, each an open "+" in that tier's tint — joined to
/// the parent by a curved connector, and the view glides down to bring that
/// freshly opened level into frame. Nothing deeper shows until one of those
/// buttons is tapped in turn.
///
/// Each agent opens a fixed number of positions at the tier below
/// ([AgentLevel.childCapacity]). Tapping a card's body (not its chevron)
/// opens that agent's own detail; the corner button shrinks whatever is
/// currently revealed to a single overview.
class AgentTeamTreeScreen extends StatefulWidget {
  final Agent root;

  const AgentTeamTreeScreen({super.key, required this.root});

  @override
  State<AgentTeamTreeScreen> createState() => _AgentTeamTreeScreenState();
}

class _AgentTeamTreeScreenState extends State<AgentTeamTreeScreen>
    with SingleTickerProviderStateMixin {
  /// Ids whose direct children are currently fanned out. Empty by default:
  /// "My Team" opens on the root's card alone and every tier is revealed one
  /// chevron tap at a time.
  final Set<String> _expanded = {};

  /// One key per agent card, so a freshly opened level can be found in the
  /// laid-out map and scrolled to.
  final Map<String, GlobalKey> _pillKeys = {};

  final _transform = TransformationController();

  /// Drives the glide to a level when its chevron is tapped. Built in
  /// [initState] so it always exists by the time [dispose] runs, even on a
  /// screen where no chevron was ever tapped.
  late final AnimationController _panController;

  /// Measures the laid-out map so it can be positioned or shrunk to fit.
  final _chartKey = GlobalKey();

  /// The InteractiveViewer's own size, kept from the last layout.
  Size _viewportSize = Size.zero;

  /// True once the map has been positioned at least once.
  bool _fitted = false;

  GlobalKey _keyFor(String id) => _pillKeys.putIfAbsent(id, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    _panController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // Pull the live geographic hierarchy (regions … wards) from the backend;
    // the tree is empty until it lands. Rebuild when it does.
    //
    // Deliberately plain `ensureLoaded()`, not `force: true`: this list is
    // ~22k rows flattened into one JSON payload (every region, state,
    // district, assembly, LSGD and ward), and forcing a fresh pull on every
    // single "My Team" open — as this used to do — meant re-downloading the
    // whole thing, and the body below blocking on it, every single visit,
    // even though the geographic hierarchy essentially never changes during
    // a session. Plain `ensureLoaded()` already retries on its own after an
    // earlier failure (`AgentGeo._load` only flips `_loaded` to true on a
    // non-empty success), so nothing is lost there; the one real trade-off
    // is that an admin's edit to a district or ward now shows on the next
    // app launch rather than the next visit to this screen, which is a fair
    // price for not re-fetching megabytes of largely-static data every time.
    AgentGeo.instance.addListener(_onGeoChanged);
    AgentGeo.instance.ensureLoaded();
    // Same for the roster itself — every agent already registered in
    // app.agent, so a fresh app launch (or a second device) shows who is
    // really on the team rather than just the national seed persona. The
    // ListenableBuilder further down already rebuilds on this same
    // notification; this separate listener exists only to reconcile
    // _expanded first — see _onAgentsChanged's own doc for why.
    AgentService.instance.addListener(_onAgentsChanged);
    AgentService.instance.ensureLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openOnRoot());
  }

  /// Keeps [_expanded] pointing at real content when a registration —
  /// completed from this very screen, returning to this same instance
  /// rather than a fresh mount — turns an open "+" seat already sitting
  /// open in [_expanded] into a real agent.
  ///
  /// A seat's open-position id (`slot/<parent>/<tier>/<geoId>`) is built
  /// from its PARENT's own current id (see [_MindNode]/[_MindPlusNode]), so
  /// registering a real agent into any ancestor along that chain — not
  /// just the seat itself — changes the id every descendant seat is now
  /// built with too, even though none of them personally gained or lost an
  /// occupant. Without this, `_expanded` goes on holding the old ids, which
  /// the tree no longer builds any card for at all, so that whole branch —
  /// and everything the user had drilled into beneath it — reads as having
  /// silently collapsed, even though nothing was ever closed; the branch
  /// just lost the only keys that still pointed at it.
  void _onAgentsChanged() {
    if (!mounted) return;
    var changed = false;
    final migrated = <String>{};
    // Whichever migrated entry sat deepest in its old path is the most
    // specific thing that was actually open — almost certainly the seat
    // the registration this notification came from just filled.
    String? deepestPromoted;
    var deepestSegments = -1;
    for (final entry in _expanded) {
      if (entry.startsWith('slot/')) {
        final current = _currentIdForGeoNode(entry.split('/').last);
        if (current != entry) {
          changed = true;
          if (!current.startsWith('slot/')) {
            final segments = entry.split('/').length;
            if (segments > deepestSegments) {
              deepestSegments = segments;
              deepestPromoted = current;
            }
          }
        }
        migrated.add(current);
      } else {
        migrated.add(entry);
      }
    }
    if (changed) {
      setState(() {
        _expanded
          ..clear()
          ..addAll(migrated);
      });
      // _expanded now correctly still calls this seat "open" — but nothing
      // has told the CAMERA that, so it is still sitting wherever it was
      // before the registration, with the seat's own card now showing an
      // already-expanded up-arrow the view never actually scrolled to. Left
      // alone, that reads as "still closed" and the natural next tap — on
      // an arrow that looks untouched — collapses it instead of opening it,
      // gliding the view up and away from exactly what was just registered.
      if (deepestPromoted != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _flowTo(deepestPromoted!, zoomIn: true),
        );
      }
    }
  }

  /// The id the tree would build RIGHT NOW for the geo position [geoId] —
  /// a real agent's own id if one occupies it, otherwise the open-seat
  /// `slot/…` path [_MindNode]/[_MindPlusNode] would construct for it,
  /// rebuilt from [AgentGeo]'s own parent chain rather than string surgery
  /// on a possibly-stale existing key, so it stays correct no matter how
  /// many ancestors along the way are real agents versus still-open seats.
  String _currentIdForGeoNode(String geoId) {
    final direct = AgentService.instance.agentAtSlot(geoId);
    if (direct != null) return direct.id;
    final tier = AgentGeo.current.levelOfId(geoId);
    final parentGeoId = AgentGeo.current.parentIdOf(geoId);
    // A region has no geo parent of its own — it always sits directly under
    // whichever agent this tree is rooted at (only ever meaningful when
    // that root is the national agent; a region-rooted tree has no region
    // slots to reconcile in the first place).
    final parentId = parentGeoId == null
        ? widget.root.id
        : _currentIdForGeoNode(parentGeoId);
    final tierName = tier?.name ?? 'region';
    return parentId.startsWith('slot/')
        ? '$parentId/$tierName/$geoId'
        : 'slot/$parentId/$tierName/$geoId';
  }

  void _onGeoChanged() {
    if (!mounted) return;
    setState(() {});
    if (!_fitted) {
      // The tree (and _chartKey, which _openOnRoot measures) only mounts
      // once the hierarchy actually has data -- while it is still loading,
      // the body shows _HierarchyStatus instead. initState's one-shot
      // _openOnRoot attempt runs straight after the very first frame, so on
      // a cold load it finds no chart to measure and gives up for good,
      // leaving the tree permanently at opacity 0 once it does mount (see
      // the AnimatedOpacity below) -- a blank "My Team" with nothing wrong
      // in the data at all. This rebuild is what puts the real tree on
      // screen for the first time, so retry positioning after it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openOnRoot());
    }
  }

  @override
  void dispose() {
    AgentGeo.instance.removeListener(_onGeoChanged);
    AgentService.instance.removeListener(_onAgentsChanged);
    _panController.dispose();
    _transform.dispose();
    super.dispose();
  }

  /// Guards [_openOnRoot]'s self-retry below from looping forever in some
  /// pathological case (a viewport that never gets a real size, say).
  int _openOnRootAttempts = 0;

  /// Where the screen opens: the root's card centred across the top, with the
  /// rest of the map free to fan out below it as branches are opened.
  void _openOnRoot() {
    final chartBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (chartBox == null || !chartBox.hasSize || _viewportSize.isEmpty) {
      // Nothing to measure yet -- most commonly the geo hierarchy (or the
      // roster) was still loading and the tree, with it, hadn't mounted.
      // [_onGeoChanged] already retries once real data lands; this is a
      // bounded safety net for any other reason a frame goes by with
      // nothing laid out yet, so the tree can never get stuck at opacity 0
      // (see the AnimatedOpacity below) with real content sitting right
      // there unfitted.
      if (mounted && !_fitted && _openOnRootAttempts++ < 20) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openOnRoot());
      }
      return;
    }
    final chartSize = chartBox.size;
    if (chartSize.width == 0 || chartSize.height == 0) {
      return;
    }

    const scale = 1.0;
    final dx = (_viewportSize.width - chartSize.width * scale) / 2;
    // The national card sits right at the top of the screen — the rest of
    // the map fans out into the space below it.
    const dy = _flowTopInset;

    setState(() {
      _transform.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
      _fitted = true;
    });
  }

  /// How far below the top edge a card is parked — on first open (the root)
  /// and after a chevron tap (the level just opened).
  static const double _flowTopInset = 16.0;

  /// What the corner button asks for: everything currently revealed shrunk
  /// down to a single overview, however far the open branches have grown.
  void _fitToScreen() {
    _panController.stop();
    final chartBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (chartBox == null || !chartBox.hasSize || _viewportSize.isEmpty) {
      return;
    }
    final chartSize = chartBox.size;
    if (chartSize.width == 0 || chartSize.height == 0) {
      return;
    }

    final scaleX = (_viewportSize.width - 40) / chartSize.width;
    final scaleY = (_viewportSize.height - 60) / chartSize.height;
    final scale = math.min(math.min(scaleX, scaleY), 1.0);

    final dx = math.max(
      24.0,
      (_viewportSize.width - chartSize.width * scale) / 2,
    );
    final dy = math.max(
      24.0,
      (_viewportSize.height - chartSize.height * scale) / 2,
    );

    setState(() {
      _transform.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
      _fitted = true;
    });
  }

  void _toggle(String id) {
    final opening = !_expanded.contains(id);
    setState(() {
      if (opening) {
        // Accordion: only one branch per tier stays open. Opening a card
        // collapses everything that is not one of its own ancestors — its
        // open siblings and their subtrees, and any other branch left open
        // elsewhere — then opens this card. _ancestorsOf alone only knows
        // the real parentId chain, which deliberately skips straight past
        // an empty tier (see AgentService.agentAtSlot's doc) — so an agent
        // registered under an open region/district "+" seat is invisible to
        // it, and opening that agent's own chevron would read its own
        // parent seat as "not an ancestor" and collapse it right out from
        // under the card being opened. _openGeoSlotsEnclosing covers that:
        // whichever already-open "+" seats this id's real geo position
        // sits under also get to stay.
        final keep = _ancestorsOf(id)..addAll(_openGeoSlotsEnclosing(id));
        _expanded.removeWhere((e) => !keep.contains(e));
        _expanded.add(id);
      } else {
        // Collapsing a card collapses everything beneath it too.
        _expanded.removeWhere((e) => e == id || _ancestorsOf(e).contains(id));
      }
    });
    // Opening a card glides down to the tier it just revealed; closing one
    // glides back up to its parent, so the chevron pulls the view in the
    // direction it points. When the tier just opened already has a real,
    // registered agent somewhere in it — not just open "+" positions — land
    // on THEM instead of the row's own start: a real person several seats
    // into a wide row (a district's 17 assemblies, say) is what the tap was
    // almost certainly trying to reach, and is more useful to land on than
    // an empty seat that happens to sort first.
    final preferredAgentId = opening ? _firstRealAgentUnder(id)?.id : null;
    final computedParent = opening ? null : _parentId(id);
    final focus = preferredAgentId ?? (opening ? id : (computedParent ?? id));
    // Falls back to whatever _flowTo itself resolves to when [focus] can't
    // be found: the tapped tier itself when a preferred real agent's card
    // isn't there this frame (its GlobalKey not yet attached — the tier it
    // sits in only just got these extra "irregular report" cards added), or
    // this tree's own root when closing an agent whose recorded parent
    // isn't actually part of this tree at all (see _parentId's own doc on
    // the more-than-one-NATIONAL-row case). Either way, a lookup miss lands
    // somewhere real instead of leaving the whole tap looking like it did
    // nothing at all.
    final fallback = preferredAgentId != null
        ? id
        : (!opening && computedParent != null ? widget.root.id : null);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _flowTo(focus, zoomIn: opening, fallback: fallback),
    );
  }

  /// The first real, registered agent occupying one of [id]'s own named
  /// slots, in slot order — or null when every seat under [id] is still
  /// open, or [id] heads no named slots at all.
  ///
  /// [id] is either a real agent's own id (its slots come from
  /// [AgentService.slotsUnder]) or an open `slot/…` position (its geo id is
  /// the path's own tail — the same convention [_openGeoSlotsEnclosing] and
  /// [AgentGeo.levelOfId] use).
  Agent? _firstRealAgentUnder(String id) {
    final AgentLevel level;
    final String? geoId;
    if (id.startsWith('slot/')) {
      geoId = id.split('/').last;
      final tierOfSlot = AgentGeo.current.levelOfId(geoId);
      if (tierOfSlot == null) return null;
      level = tierOfSlot;
    } else {
      final agent = AgentService.instance.byId(id);
      if (agent == null) return null;
      level = agent.level;
      geoId = agent.areaId;
    }
    // slotsUnder ignores [level] for every tier but national (see its own
    // doc) — passing it through here is just what lets national's fixed
    // six regions resolve without a real geo id of their own.
    final slots = AgentGeo.current.slotsUnder(level, geoId);
    for (final slot in slots) {
      final filled = AgentService.instance.agentAtSlot(slot.id);
      if (filled != null) return filled;
    }
    return null;
  }

  /// Every currently-open "+" geo seat (a `slot/…` id already in [_expanded])
  /// [id]'s own real geo position sits under — region, state, district, …
  /// whatever tiers between them are still vacant. [_ancestorsOf] alone
  /// cannot see these: a real agent's own `parentId` skips straight past a
  /// vacant tier (see `AgentService.agentAtSlot`'s doc), so it has no entry
  /// for the open seat that vacant tier is drawn as, even while that seat's
  /// card is what visually encloses [id] on screen right now.
  Set<String> _openGeoSlotsEnclosing(String id) {
    final areaId = AgentService.instance.byId(id)?.areaId;
    if (areaId == null) {
      return const {};
    }
    return _expanded.where((e) {
      if (!e.startsWith('slot/')) {
        return false;
      }
      final tail = e.split('/').last;
      return AgentGeo.current.levelOfId(tail) != null &&
          AgentGeo.current.isWithin(areaId, tail);
    }).toSet();
  }

  /// Every id on the path from [id] up to the root, not including [id] itself.
  /// Drives the accordion in [_toggle]: an id is kept open only while the card
  /// being opened sits somewhere beneath it.
  Set<String> _ancestorsOf(String id) {
    final chain = <String>{};
    var current = _parentId(id);
    var guard = 0;
    while (current != null && chain.add(current) && guard++ < 64) {
      current = _parentId(current);
    }
    return chain;
  }

  /// The card a collapse should glide back to: a real agent's parent (or the
  /// root), or, for an open "+" position, the slot or agent one step up its
  /// path.
  String? _parentId(String id) {
    if (id.startsWith('slot/')) {
      final parts = id.split('/');
      // slot/<agentId>/<tier>/<i>[/<tier>/<i>...] — drop the last tier+index
      // pair; what remains is the parent slot, or just the real agent id.
      if (parts.length > 4) {
        return parts.sublist(0, parts.length - 2).join('/');
      }
      return parts.length > 1 ? parts[1] : null;
    }
    final agent = AgentService.instance.byId(id);
    final rawParent = agent?.parentId;
    // A fetched agent with no real recorded parent (a NULL app.agent.parent_id)
    // is mapped, at the data layer (AgentRepository._toAgent), to the local
    // seed persona's own id — correct when that seed is genuinely this
    // tree's root, but a dangling reference to an agent that plays no part
    // in this tree at all when a *different* real NATIONAL-level row is who
    // actually signed in (the database can hold more than one — see
    // decision-log.md). Redirect it to this tree's own root instead, so
    // collapsing such an agent glides up to a card that actually exists in
    // the tree being looked at, rather than silently going nowhere.
    if (rawParent == AgentDirectory.national.id &&
        widget.root.id != AgentDirectory.national.id) {
      return id == widget.root.id ? null : widget.root.id;
    }
    return rawParent ?? (id == widget.root.id ? null : widget.root.id);
  }

  /// Glides the view so [id]'s card sits high and centred, its tier fanned
  /// out in the frame below it. Retries once with [fallback] — the tier
  /// that was actually tapped, when [id] is a preferred-focus substitute for
  /// it — rather than silently doing nothing at all when [id] itself can't
  /// be found (no built, mounted card behind its key this frame).
  void _flowTo(String id, {bool zoomIn = false, String? fallback}) {
    final pillBox =
        _pillKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    final chartBox = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (pillBox == null ||
        chartBox == null ||
        !pillBox.hasSize ||
        _viewportSize.isEmpty) {
      if (fallback != null && fallback != id) {
        _flowTo(fallback, zoomIn: zoomIn);
      }
      return;
    }

    // The card's position inside the (untransformed) map content.
    final topLeft = pillBox.localToGlobal(Offset.zero, ancestor: chartBox);
    final currentScale = _transform.value.getMaxScaleOnAxis();
    // Always zoom IN on the level just tapped (never out) — a wide tier (a
    // real Kerala district can open up to 17 assembly seats) still ends up
    // wider than the viewport at this scale, but that reads as "pan sideways
    // to see the rest", the same way any zoomed-in map does. Zooming out to
    // force the whole row into frame instead (tried once) shrank everything
    // so far that the newly-opened cards became too small to read — worse
    // than the pan.
    final scale = zoomIn ? math.max(1.0, currentScale) : currentScale;

    final targetX = _targetXFor(pillBox, topLeft, scale, zoomIn);
    final targetY = _flowTopInset - topLeft.dy * scale;

    final target = Matrix4.identity()
      ..translateByDouble(targetX, targetY, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);

    _animateTransformTo(target);
  }

  /// Where to land [pillBox]'s card horizontally.
  ///
  /// Normally dead centre — same as always, and what a collapse (`!zoomIn`)
  /// always gets. But a tier that was just opened (`zoomIn`) with more than
  /// one sibling — [pillBox]'s render object's own parent is always the
  /// `_RenderMindBranch` [_MindBranch] built it into, and that branch now
  /// measures wider than the card alone once it has fanned children out
  /// beneath it — lands with the LEFT edge of that whole newly-fanned row
  /// just inside the frame instead.
  ///
  /// Centering the tapped card, as this used to do unconditionally, only
  /// ever brings whichever siblings sit nearest the row's own middle into
  /// view: opening National's 6 real regions this way puts East and West
  /// India on screen and leaves South India (Kerala's own region) off both
  /// edges, with nothing on screen to suggest panning would find it — a
  /// real Kerala district can open a dozen-plus assembly seats too (17, for
  /// Malappuram), so the same thing happens one tier further down. Landing
  /// on the row's own start and panning right from there reads as an
  /// ordinary zoomed-in map instead of "the chevron did nothing".
  double _targetXFor(RenderBox pillBox, Offset topLeft, double scale, bool zoomIn) {
    final branchBox = pillBox.parent;
    if (zoomIn &&
        branchBox is _RenderMindBranch &&
        branchBox.hasSize &&
        branchBox.size.width > pillBox.size.width + 1) {
      // The branch's own local origin (x=0) is the left edge of its widest
      // row; `nodeCenterX` is this card's offset from that origin, already
      // computed by _RenderMindBranch.performLayout to centre the card over
      // its children — so subtracting it back out of the card's own known
      // global position recovers the row's left edge, with no extra layout
      // pass needed.
      final rowLeftEdge =
          topLeft.dx - (branchBox.nodeCenterX - pillBox.size.width / 2);
      const margin = 20.0;
      return margin - rowLeftEdge * scale;
    }
    return _viewportSize.width / 2 - (topLeft.dx + pillBox.size.width / 2) * scale;
  }

  void _animateTransformTo(Matrix4 target) {
    _panController.stop();
    final anim = Matrix4Tween(begin: _transform.value, end: target).animate(
      CurvedAnimation(parent: _panController, curve: Curves.easeInOutCubic),
    );
    void tick() => _transform.value = anim.value;
    anim.addListener(tick);
    _panController
      ..reset()
      ..forward().whenCompleteOrCancel(() => anim.removeListener(tick));
  }

  Future<void> _addUnder(
    Agent parent, [
    AgentLevel? level,
    GeoSlot? slot,
  ]) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AgentRegistrationScreen(
          scopeRoot: widget.root,
          initialParent: parent,
          initialLevel: level,
          initialSlot: slot,
        ),
      ),
    );
    if (added != true || !mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Agent registered')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'My Team',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _fitToScreen,
            icon: const Icon(Icons.center_focus_strong_rounded),
            color: AppColors.textMuted,
            tooltip: 'Fit whole team',
          ),
          IconButton(
            onPressed: () => _addUnder(widget.root),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            color: AppColors.brandBlue,
            tooltip: 'Add agent',
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      // The whole tree hangs off the geographic hierarchy (regions … wards).
      // `initState` only loads it once per session now (see its own doc), so
      // this blocking state is normally seen only on the very first "My
      // Team" open, or after the Retry button below forces a reload
      // following a failure — either way, waiting for that load rather than
      // drawing the tree off a half-populated [AgentGeo.current] avoids a
      // slot rendered as the generic tier name ("+ District") when the real
      // one ("+ Thiruvananthapuram") is a network round-trip away, which
      // looks exactly like a placement that genuinely has no name, not like
      // a page still catching up.
      body: (AgentGeo.instance.isLoading || AgentGeo.current.regions.isEmpty)
          ? _HierarchyStatus(
              attempted:
                  AgentGeo.instance.hasAttempted &&
                  !AgentGeo.instance.isLoading,
              error: AgentGeo.instance.lastError,
              configured: BackendHttp.isConfigured,
              onRetry: () {
                setState(() {});
                AgentGeo.instance.ensureLoaded(force: true);
              },
            )
          : ListenableBuilder(
              listenable: AgentService.instance,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  _viewportSize = constraints.biggest;
                  return ClipRect(
                    child: AnimatedOpacity(
                      opacity: _fitted ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: InteractiveViewer(
                        transformationController: _transform,
                        constrained: false,
                        boundaryMargin: const EdgeInsets.all(600),
                        minScale: 0.1,
                        maxScale: 3.5,
                        child: Padding(
                          key: _chartKey,
                          padding: const EdgeInsets.fromLTRB(40, 16, 40, 96),
                          child: _MindNode(
                            // Re-read rather than trusting widget.root as-is: a
                            // photo added to the root from its own detail screen
                            // would otherwise never show here.
                            agent:
                                AgentService.instance.byId(widget.root.id) ??
                                widget.root,
                            depth: 0,
                            expanded: _expanded,
                            keyFor: _keyFor,
                            onToggle: _toggle,
                            onOpen: (agent) => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AgentDetailScreen(agent: agent),
                              ),
                            ),
                            onAdd: _addUnder,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Shown in place of the tree while the geographic hierarchy (`app.region` …
/// `app.ward`) has not loaded — a skeleton shaped like the mind-map on the
/// first attempt, then a plain reason and a retry once an attempt has
/// finished with nothing.
class _HierarchyStatus extends StatelessWidget {
  final bool attempted;
  final Object? error;
  final bool configured;
  final VoidCallback onRetry;

  const _HierarchyStatus({
    required this.attempted,
    required this.error,
    required this.configured,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (!attempted) {
      return const _HierarchySkeleton();
    }

    final String reason;
    if (!configured) {
      reason =
          'This build has no database connection.\n'
          'Run it with --dart-define-from-file=.env';
    } else if (error != null) {
      reason = 'Could not reach the database.\n$error';
    } else {
      reason =
          'The region … ward tables are empty.\n'
          'Seed them (migrations 0014–0016, then the Kerala geo import) '
          'and retry.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_tree_outlined,
              size: 40,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              'The team hierarchy is not available yet',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pulsing placeholder shaped like the tree it is about to become — a root
/// card over a fanned-out row of three — so the first-load wait reads as the
/// same mind-map settling in rather than a bare spinner.
class _HierarchySkeleton extends StatefulWidget {
  const _HierarchySkeleton();

  @override
  State<_HierarchySkeleton> createState() => _HierarchySkeletonState();
}

class _HierarchySkeletonState extends State<_HierarchySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.45,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const Color _bone = Color(0xFFE3E6F0);

  Widget _pill({required double width, required double height}) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: _bone,
      borderRadius: BorderRadius.circular(10),
    ),
  );

  Widget _dot() => Container(
    width: 26,
    height: 26,
    decoration: const BoxDecoration(color: _bone, shape: BoxShape.circle),
  );

  Widget _branch() => Column(
    children: [_pill(width: 92, height: 58), const SizedBox(height: 8), _dot()],
  );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _pulse,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pill(width: 150, height: 54),
              const SizedBox(height: 10),
              _dot(),
              const SizedBox(height: 32),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _branch(),
                  const SizedBox(width: 20),
                  _branch(),
                  const SizedBox(width: 20),
                  _branch(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pastel a card carries, cycled by how deep it sits — so each step down
/// from the root reads as its own ring, the way a mind-map does, rather than
/// every card being one flat colour.
const List<Color> _mindTints = [
  Color(0xFFC7CAF4), // periwinkle — the root
  Color(0xFFC4D0EF), // light blue
  Color(0xFFB2DCC9), // mint
  Color(0xFFE6D7F0), // lilac
  Color(0xFFF2E2C6), // sand
];

Color _mindTint(int depth) => _mindTints[depth % _mindTints.length];

/// The line joining a card to each of its children.
const Color _connectorColor = Color(0xFF8A97C9);

/// The round chevron button under a card.
const Color _caretColor = Color(0xFF8188D6);

/// One agent and, once its chevron is tapped, the row of its children fanned
/// out below. Recursive — each child is another [_MindNode], collapsed until
/// its own chevron is tapped.
class _MindNode extends StatelessWidget {
  final Agent agent;
  final int depth;
  final Set<String> expanded;
  final GlobalKey Function(String id) keyFor;
  final void Function(String id) onToggle;
  final void Function(Agent agent) onOpen;
  final void Function(Agent parent, AgentLevel level, [GeoSlot? slot]) onAdd;

  const _MindNode({
    required this.agent,
    required this.depth,
    required this.expanded,
    required this.keyFor,
    required this.onToggle,
    required this.onOpen,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final service = AgentService.instance;
    final children = service.childrenOf(agent.id);

    // The fixed named slots this agent's tier opens — the six zones under the
    // national agent, a zone's states under a region agent — or empty where
    // the tier just doubles. Named slots drive the capacity; otherwise it is
    // the plain childCapacity budget. Id-keyed — see [Agent.areaId].
    final slots = service.slotsUnder(agent);
    // Normally the enum successor, but read from the data so an irregular
    // branch is honoured — a ward sitting straight under an assembly, say.
    // Never for the national agent itself, though: it heads no single real
    // slot ([Agent.areaId] is null for it), so there is nothing to look up.
    final childLevel =
        (agent.level == AgentLevel.national ||
                agent.areaId == null ||
                slots.isEmpty
            ? null
            : AgentGeo.current.childLevelOfId(agent.areaId!)) ??
        agent.level.child;
    final capacity = slots.isNotEmpty
        ? slots.length
        : agent.level.childCapacity;
    // A recruit still awaiting an admin's approval has their own detail
    // screen locked (nothing to review there yet — see `_showLockedNotice`),
    // but the tier they would head is not: a recruiter needs to see the
    // whole shape of their team, approved or not, so the chevron still fans
    // it out — real reports if any exist, open positions otherwise.
    final locked = !agent.isApproved;
    final canExpand = (childLevel != null) && (capacity > 0);
    final isExpanded = canExpand && expanded.contains(agent.id);

    return _MindBranch(
      connectorColor: _connectorColor,
      node: _MindPill(
        pillKey: keyFor(agent.id),
        boxKey: ValueKey('mind-pill-${agent.id}'),
        title: agent.name,
        // A slot agent's card names the place they head (the zone, or the
        // ward's own code), not just the bare tier name.
        subtitle: _slotSubtitle(agent),
        code: agent.agentCode,
        depth: depth,
        toggleLabel: agent.name,
        expanded: isExpanded,
        locked: locked,
        onTap: () => onOpen(agent),
        onToggle: canExpand ? () => onToggle(agent.id) : null,
        badge: agent.isApproved
            ? null
            : _ApprovalTag(status: agent.approvalStatus),
      ),
      children: isExpanded
          ? _buildChildNodes(children, childLevel, slots, capacity)
          : const [],
    );
  }

  /// "Region · South", "Ward · Valiyangadi", or just the bare tier name for
  /// a slot with no named place at all.
  ///
  /// Always the readable [Agent.area] — never [AgentGeo.codeForId]'s printed
  /// code (`AC136-L1-W005` and the like). The open "+" position this agent
  /// filled showed its place by the same readable name (see
  /// [_MindPlusPill.slotLabel]); this card has to keep showing it, not swap
  /// it out for a code the moment someone actually registers there.
  static String _slotSubtitle(Agent agent) {
    if (agent.area.isNotEmpty) {
      return '${agent.level.label} · ${agent.area}';
    }
    return agent.level.label;
  }

  _MindNode _child(Agent child) => _MindNode(
    agent: child,
    depth: depth + 1,
    expanded: expanded,
    keyFor: keyFor,
    onToggle: onToggle,
    onOpen: onOpen,
    onAdd: onAdd,
  );

  _MindPlusNode _slot(AgentLevel level, String slotId, {GeoSlot? slot}) =>
      _MindPlusNode(
        level: level,
        depth: depth + 1,
        slotId: slotId,
        realParent: agent,
        slot: slot,
        expanded: expanded,
        keyFor: keyFor,
        onToggle: onToggle,
        onOpen: onOpen,
        onAdd: onAdd,
      );

  /// The rows under an expanded agent: its filled reports, then the open
  /// positions. With named slots ([slots] — the zones, or a zone's states)
  /// each slot is either whoever actually holds that geo position
  /// ([AgentService.agentAtSlot] — not just this agent's own direct
  /// [childrenOf], which a skipped-past empty tier would miss entirely) or
  /// an open "+ North" card; otherwise the plain "+ child" cards fill the
  /// remaining [capacity].
  List<Widget> _buildChildNodes(
    List<Agent> children,
    AgentLevel? childLevel,
    List<GeoSlot> slots,
    int capacity,
  ) {
    if (childLevel == null) {
      return const [];
    }
    if (slots.isEmpty) {
      return [
        for (final child in children) _child(child),
        for (var i = children.length; i < capacity; i++)
          _slot(childLevel, 'slot/${agent.id}/${childLevel.name}/$i'),
      ];
    }
    final service = AgentService.instance;
    final nodes = <Widget>[
      for (final slot in slots)
        if (service.agentAtSlot(slot.id) case final Agent filled)
          _child(filled)
        else
          _slot(
            slot.level,
            'slot/${agent.id}/${slot.level.name}/${slot.id}',
            slot: slot,
          ),
      // Anyone whose slot isn't one of the named ones, and isn't nested
      // somewhere under one of them either (that agent's own slot — matched
      // above — already draws them there, at their real geo depth), still
      // shows here as an irregular direct report.
      for (final child in children)
        if (child.areaId == null ||
            !slots.any((s) => AgentGeo.current.isWithin(child.areaId!, s.id)))
          _child(child),
    ];
    return nodes;
  }
}

/// One open position on the fixed org shape — a "+" card in that tier's tint.
/// Tapping the card opens registration reporting to [realParent] (the nearest
/// agent who actually exists) at this position's tier. Its own chevron fans
/// out the [AgentLevel.childCapacity] positions below it, in turn, so the
/// whole shape can be previewed a tier at a time even where nobody has
/// registered yet.
class _MindPlusNode extends StatelessWidget {
  final AgentLevel level;
  final int depth;

  /// Stable id for this slot's place in the preview shape — path-built from
  /// the real parent and the chain of slot indices, so its expanded state
  /// survives rebuilds.
  final String slotId;

  /// The real agent a registration from anywhere in this slot's subtree
  /// reports to.
  final Agent realParent;

  /// The named slot this position stands for — a region, a ward, and so on
  /// — when it is one of a real parent's fixed named slots rather than a
  /// plain doubling position. Shown on the card in place of the bare tier
  /// name, and what a registration into it is placed against.
  final GeoSlot? slot;

  final Set<String> expanded;
  final GlobalKey Function(String id) keyFor;
  final void Function(String id) onToggle;
  final void Function(Agent agent) onOpen;
  final void Function(Agent parent, AgentLevel level, [GeoSlot? slot]) onAdd;

  const _MindPlusNode({
    required this.level,
    required this.depth,
    required this.slotId,
    required this.realParent,
    required this.expanded,
    required this.keyFor,
    required this.onToggle,
    required this.onOpen,
    required this.onAdd,
    this.slot,
  });

  @override
  Widget build(BuildContext context) {
    final slot = this.slot;

    // If this open slot itself names a place, its own preview positions are
    // that place's named children rather than the plain doubling shape.
    final previewSlots = AgentGeo.current.slotsUnder(level, slot?.id);
    final previewCapacity = previewSlots.isNotEmpty
        ? previewSlots.length
        : level.childCapacity;
    // The successor read from the data, so an irregular branch is honoured
    // (falls back to the enum successor for the regular tiers).
    final childLevel =
        (previewSlots.isEmpty || slot == null
            ? null
            : AgentGeo.current.childLevelOfId(slot.id)) ??
        level.child;

    final canExpand = (childLevel != null) && (previewCapacity > 0);
    final isExpanded = canExpand && expanded.contains(slotId);

    return _MindBranch(
      connectorColor: _connectorColor,
      node: _MindPlusPill(
        pillKey: keyFor(slotId),
        level: level,
        depth: depth,
        toggleLabel: '${level.label} position',
        expanded: isExpanded,
        onAdd: () => onAdd(realParent, level, slot),
        onToggle: canExpand ? () => onToggle(slotId) : null,
        slotLabel: slot?.name,
        // For an LSGD show its kind (Corporation / Municipality / Grama
        // Panchayat); every other tier shows its printed code.
        slotCode: slot == null
            ? null
            : (slot.typeLabel.isNotEmpty
                  ? slot.typeLabel
                  : (slot.code.isNotEmpty ? slot.code : null)),
      ),
      children: isExpanded
          ? [
              for (var i = 0; i < previewCapacity; i++)
                if ((previewSlots.isEmpty
                        ? null
                        : AgentService.instance.agentAtSlot(previewSlots[i].id))
                    case final Agent filled)
                  // Someone actually holds this position — their real
                  // parentId may skip straight past every empty tier back
                  // to whichever ancestor is real (see [AgentService.
                  // agentAtSlot]'s doc), so this preview walk, not
                  // [AgentService.childrenOf], is what finds them and
                  // draws them at their true geo depth instead of at
                  // wherever their parentId shortcut lands.
                  _MindNode(
                    agent: filled,
                    depth: depth + 1,
                    expanded: expanded,
                    keyFor: keyFor,
                    onToggle: onToggle,
                    onOpen: onOpen,
                    onAdd: onAdd,
                  )
                else
                  _MindPlusNode(
                    level: previewSlots.isNotEmpty
                        ? previewSlots[i].level
                        : childLevel,
                    depth: depth + 1,
                    slotId: previewSlots.isNotEmpty
                        ? '$slotId/${previewSlots[i].level.name}/${previewSlots[i].id}'
                        : '$slotId/${childLevel.name}/$i',
                    realParent: realParent,
                    slot: previewSlots.isNotEmpty ? previewSlots[i] : null,
                    expanded: expanded,
                    keyFor: keyFor,
                    onToggle: onToggle,
                    onOpen: onOpen,
                    onAdd: onAdd,
                  ),
            ]
          : const [],
    );
  }
}

/// What a locked card's body tap shows instead of opening the detail screen.
void _showLockedNotice(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text(
          "Not yet approved — this agent's details open once the admin "
          'approves the registration.',
        ),
      ),
    );
}

/// A filled agent card: a rounded pill in its depth's tint carrying the name
/// and tier, with — when the agent heads a tier — a round chevron button
/// under it. The pill body opens the agent's detail (unless [locked] — a
/// recruit still awaiting approval shows a notice instead); the button fans
/// the tier below in or out.
class _MindPill extends StatelessWidget {
  final Key pillKey;
  final Key boxKey;
  final String title;
  final String subtitle;

  /// The printed agent code, shown under the tier.
  final String code;
  final int depth;
  final String toggleLabel;
  final bool expanded;

  /// A recruit awaiting approval: draw a lock by the name and skip the
  /// chevron, so the card reads as a held place rather than a working agent.
  final bool locked;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  final Widget? badge;

  const _MindPill({
    required this.pillKey,
    required this.boxKey,
    required this.title,
    required this.subtitle,
    required this.code,
    required this.depth,
    required this.toggleLabel,
    required this.expanded,
    required this.onTap,
    required this.onToggle,
    this.locked = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final tint = _mindTint(depth);

    return Column(
      key: pillKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: tint,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            // A locked (not-yet-approved) card does not open its detail
            // screen — there is nothing to review there until the console
            // has approved or rejected the registration; a lock icon plus
            // this tap tells the recruiter why, instead of the card silently
            // opening as if it were a working agent.
            onTap: locked ? () => _showLockedNotice(context) : onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              key: boxKey,
              constraints: const BoxConstraints(maxWidth: 240),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (locked) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 1, right: 4),
                          child: Icon(
                            Icons.lock_outline,
                            size: 13,
                            color: AppColors.textDark.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: AppColors.textDark.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: AppColors.textDark.withValues(alpha: 0.45),
                    ),
                  ),
                  if (badge != null) ...[const SizedBox(height: 6), badge!],
                ],
              ),
            ),
          ),
        ),
        if (onToggle != null) ...[
          // No explicit gap here on purpose — _CaretButton's own enlarged
          // tap target (see its own doc) already centres the small visible
          // circle inside extra invisible padding, which supplies the
          // breathing room this used to add explicitly; stacking both made
          // the pill-to-caret gap noticeably taller than before.
          _CaretButton(
            expanded: expanded,
            label: toggleLabel,
            onTap: onToggle!,
          ),
        ],
      ],
    );
  }
}

/// The "+" card for a still-open position. Same pill shape as [_MindPill], in
/// the tier's tint, with a lead "+" instead of a name; tapping the card opens
/// registration. When the tier has positions of its own, a chevron under it
/// fans those out as their own "+" cards.
class _MindPlusPill extends StatelessWidget {
  final Key pillKey;
  final AgentLevel level;
  final int depth;
  final String toggleLabel;
  final bool expanded;
  final VoidCallback onAdd;
  final VoidCallback? onToggle;

  /// Shown on the card instead of the plain tier name — used to name the six
  /// zones on a national agent's open region slots ("North", "South", …).
  final String? slotLabel;

  /// The slot's own printed code (`AC136`, `TVC-L1`), passed straight from
  /// the [GeoSlot] the caller already has — never re-derived from
  /// [slotLabel] here, since a bare name is not enough to find the right
  /// slot back out of the real hierarchy (see [Agent.areaId]).
  final String? slotCode;

  const _MindPlusPill({
    required this.pillKey,
    required this.level,
    required this.depth,
    required this.toggleLabel,
    required this.expanded,
    required this.onAdd,
    required this.onToggle,
    this.slotLabel,
    this.slotCode,
  });

  @override
  Widget build(BuildContext context) {
    final tint = _mindTint(depth);

    return Column(
      key: pillKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Add a ${level.label.toLowerCase()} agent here',
          child: Material(
            color: tint.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tint),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: AppColors.textDark.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 6),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slotLabel ?? level.label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                            color: AppColors.textDark.withValues(alpha: 0.75),
                          ),
                        ),
                        if (slotCode != null && slotCode!.isNotEmpty)
                          Text(
                            slotCode!,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                              color: AppColors.textDark.withValues(alpha: 0.5),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (onToggle != null) ...[
          // No explicit gap here on purpose — _CaretButton's own enlarged
          // tap target (see its own doc) already centres the small visible
          // circle inside extra invisible padding, which supplies the
          // breathing room this used to add explicitly; stacking both made
          // the pill-to-caret gap noticeably taller than before.
          _CaretButton(
            expanded: expanded,
            label: toggleLabel,
            onTap: onToggle!,
          ),
        ],
      ],
    );
  }
}

/// The round chevron button under a card. Points down while the branch is
/// folded, up while it is open.
class _CaretButton extends StatelessWidget {
  final bool expanded;
  final String label;
  final VoidCallback onTap;

  /// The visible circle — kept small and delicate, matching the rest of the
  /// mind-map's scale.
  static const double _visibleSize = 26;

  /// The actual tappable area — well past Material's own 48dp minimum
  /// target guidance, on top of the visible circle rather than shrunk to
  /// match it. A tap landing on this card almost always follows a manual
  /// pan to reach a sibling several seats into a wide row (a district's own
  /// row of assemblies, say) — exactly the moment `InteractiveViewer`'s own
  /// pan/scale gesture recognizer is still "warm" and most likely to win a
  /// tie against a small, freshly-tapped target instead of letting it
  /// through as a plain tap. A generous hit area is what actually fixes
  /// that in practice; nothing server- or state-side was ever wrong here.
  static const double _tapSize = 48;

  const _CaretButton({
    required this.expanded,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: expanded ? 'Collapse $label' : 'Expand $label',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: _tapSize,
            height: _tapSize,
            child: Center(
              child: Container(
                width: _visibleSize,
                height: _visibleSize,
                decoration: const BoxDecoration(
                  color: _caretColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small "Pending" / "Rejected" tag shown on a card for a recruit whose
/// parent has not yet signed off — an approved agent shows nothing extra.
class _ApprovalTag extends StatelessWidget {
  final AgentApprovalStatus status;

  const _ApprovalTag({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: status.accent,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout: a node on top, its children fanned out in a row beneath it, joined
// by curved connectors from the card's bottom centre to each child's top.
// ---------------------------------------------------------------------------

class _MindBranch extends MultiChildRenderObjectWidget {
  final Color connectorColor;

  _MindBranch({
    required Widget node,
    required List<Widget> children,
    required this.connectorColor,
  }) : super(children: [node, ...children]);

  @override
  _RenderMindBranch createRenderObject(BuildContext context) =>
      _RenderMindBranch(connectorColor: connectorColor);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMindBranch renderObject,
  ) {
    renderObject.connectorColor = connectorColor;
  }
}

class _MindBranchParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderMindBranch extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MindBranchParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MindBranchParentData> {
  Color connectorColor;

  /// Horizontal gap between two neighbouring sibling branches.
  static const double siblingGap = 20;

  /// Vertical gap between a card's bottom edge and its children — where the
  /// curved connectors live.
  static const double branchGap = 40;

  /// The horizontal centre of this branch's own card, relative to the branch
  /// origin — where a parent's connector should land.
  double nodeCenterX = 0.0;

  _RenderMindBranch({required this.connectorColor});

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MindBranchParentData) {
      child.parentData = _MindBranchParentData();
    }
  }

  List<_RenderMindBranch> _childBranches(RenderBox node) {
    final out = <_RenderMindBranch>[];
    var c = (node.parentData as _MindBranchParentData).nextSibling;
    while (c != null) {
      if (c is _RenderMindBranch) {
        out.add(c);
      }
      c = (c.parentData as _MindBranchParentData).nextSibling;
    }
    return out;
  }

  @override
  void performLayout() {
    if (firstChild == null) {
      size = constraints.smallest;
      nodeCenterX = 0;
      return;
    }

    final node = firstChild!;
    node.layout(const BoxConstraints(), parentUsesSize: true);

    final branches = _childBranches(node);
    for (final b in branches) {
      b.layout(const BoxConstraints(), parentUsesSize: true);
    }

    if (branches.isEmpty) {
      (node.parentData as _MindBranchParentData).offset = Offset.zero;
      size = node.size;
      nodeCenterX = size.width / 2.0;
      return;
    }

    // Lay the child branches out left to right.
    final childX = <double>[];
    var x = 0.0;
    for (var i = 0; i < branches.length; i++) {
      childX.add(x);
      x += branches[i].size.width;
      if (i < branches.length - 1) {
        x += siblingGap;
      }
    }
    final childrenWidth = x;
    final childY = node.size.height + branchGap;

    // Align the card's centre with the midpoint between the first and last
    // child's own centres, padding left/right if the card overhangs.
    final firstCenter = childX.first + branches.first.nodeCenterX;
    final lastCenter = childX.last + branches.last.nodeCenterX;
    final mid = (firstCenter + lastCenter) / 2.0;

    final leftPad = math.max(0.0, node.size.width / 2.0 - mid);
    final rightPad = math.max(
      0.0,
      node.size.width / 2.0 - (childrenWidth - mid),
    );
    final totalWidth = childrenWidth + leftPad + rightPad;
    nodeCenterX = leftPad + mid;

    (node.parentData as _MindBranchParentData).offset = Offset(
      nodeCenterX - node.size.width / 2.0,
      0,
    );

    var maxBottom = node.size.height;
    for (var i = 0; i < branches.length; i++) {
      (branches[i].parentData as _MindBranchParentData).offset = Offset(
        leftPad + childX[i],
        childY,
      );
      maxBottom = math.max(maxBottom, childY + branches[i].size.height);
    }

    size = Size(totalWidth, maxBottom);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final node = firstChild;
    if (node == null) {
      return;
    }
    final branches = _childBranches(node);

    if (branches.isNotEmpty) {
      final canvas = context.canvas;
      final linePaint = Paint()
        ..color = connectorColor
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;

      final startX = offset.dx + nodeCenterX;
      final startY = offset.dy + node.size.height;

      for (final b in branches) {
        final bd = b.parentData as _MindBranchParentData;
        final endX = offset.dx + bd.offset.dx + b.nodeCenterX;
        final endY = offset.dy + bd.offset.dy;
        final dy = (endY - startY) / 2.0;
        final path = Path()
          ..moveTo(startX, startY)
          ..cubicTo(startX, startY + dy, endX, endY - dy, endX, endY);
        canvas.drawPath(path, linePaint);
      }
    }

    final nodeData = node.parentData as _MindBranchParentData;
    context.paintChild(node, offset + nodeData.offset);
    for (final b in branches) {
      final bd = b.parentData as _MindBranchParentData;
      context.paintChild(b, offset + bd.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
