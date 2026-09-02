import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_colors.dart';
import 'agent_detail_screen.dart';
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

  GlobalKey _keyFor(String id) =>
      _pillKeys.putIfAbsent(id, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    _panController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _openOnRoot());
  }

  @override
  void dispose() {
    _panController.dispose();
    _transform.dispose();
    super.dispose();
  }

  /// Where the screen opens: the root's card centred across the top, with the
  /// rest of the map free to fan out below it as branches are opened.
  void _openOnRoot() {
    final chartBox =
        _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (chartBox == null || !chartBox.hasSize || _viewportSize.isEmpty) {
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
    final chartBox =
        _chartKey.currentContext?.findRenderObject() as RenderBox?;
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

    final dx =
        math.max(24.0, (_viewportSize.width - chartSize.width * scale) / 2);
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
      if (!_expanded.remove(id)) {
        _expanded.add(id);
      }
    });
    // Opening a card glides down to the tier it just revealed; closing one
    // glides back up to its parent, so the chevron pulls the view in the
    // direction it points.
    final focus = opening ? id : (_parentId(id) ?? id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _flowTo(focus));
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
    return agent?.parentId ?? (id == widget.root.id ? null : widget.root.id);
  }

  /// Glides the view so [id]'s card sits high and centred, its tier fanned
  /// out in the frame below it.
  void _flowTo(String id) {
    final pillBox =
        _pillKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    final chartBox =
        _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (pillBox == null ||
        chartBox == null ||
        !pillBox.hasSize ||
        _viewportSize.isEmpty) {
      return;
    }

    // The card's position inside the (untransformed) map content.
    final topLeft = pillBox.localToGlobal(Offset.zero, ancestor: chartBox);
    final scale = _transform.value.getMaxScaleOnAxis();

    final targetX = _viewportSize.width / 2 - (topLeft.dx + pillBox.size.width / 2) * scale;
    final targetY = _flowTopInset - topLeft.dy * scale;

    final target = Matrix4.identity()
      ..translateByDouble(targetX, targetY, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);

    _animateTransformTo(target);
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

  Future<void> _addUnder(Agent parent, [AgentLevel? level]) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AgentRegistrationScreen(
          scopeRoot: widget.root,
          initialParent: parent,
          initialLevel: level,
        ),
      ),
    );
    if (added != true || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Agent registered')),
    );
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
      body: ListenableBuilder(
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
                      agent: AgentService.instance.byId(widget.root.id) ??
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
  final void Function(Agent parent, AgentLevel level) onAdd;

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
    final capacity = agent.level.childCapacity;
    final childLevel = agent.level.child;
    final canExpand = capacity > 0;
    final isExpanded = canExpand && expanded.contains(agent.id);

    return _MindBranch(
      connectorColor: _connectorColor,
      node: _MindPill(
        pillKey: keyFor(agent.id),
        boxKey: ValueKey('mind-pill-${agent.id}'),
        title: agent.name,
        subtitle: agent.level.label,
        code: agent.agentCode,
        depth: depth,
        toggleLabel: agent.name,
        expanded: isExpanded,
        onTap: () => onOpen(agent),
        onToggle: canExpand ? () => onToggle(agent.id) : null,
        badge:
            agent.isApproved ? null : _ApprovalTag(status: agent.approvalStatus),
      ),
      children: isExpanded
          ? [
              for (final child in children)
                _MindNode(
                  agent: child,
                  depth: depth + 1,
                  expanded: expanded,
                  keyFor: keyFor,
                  onToggle: onToggle,
                  onOpen: onOpen,
                  onAdd: onAdd,
                ),
              // The positions nobody has filled yet — shown as "+" cards that
              // fan out into their own preview positions when tapped, all the
              // way down to ward. Registering into any of them reports the
              // new agent to [agent] directly, so a national agent can open a
              // ward without a region between them.
              for (var i = children.length; i < capacity; i++)
                _MindPlusNode(
                  level: childLevel!,
                  depth: depth + 1,
                  slotId: 'slot/${agent.id}/${childLevel.name}/$i',
                  realParent: agent,
                  expanded: expanded,
                  keyFor: keyFor,
                  onToggle: onToggle,
                  onAdd: onAdd,
                ),
            ]
          : const [],
    );
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

  final Set<String> expanded;
  final GlobalKey Function(String id) keyFor;
  final void Function(String id) onToggle;
  final void Function(Agent parent, AgentLevel level) onAdd;

  const _MindPlusNode({
    required this.level,
    required this.depth,
    required this.slotId,
    required this.realParent,
    required this.expanded,
    required this.keyFor,
    required this.onToggle,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final childLevel = level.child;
    final canExpand = level.childCapacity > 0;
    final isExpanded = canExpand && expanded.contains(slotId);

    return _MindBranch(
      connectorColor: _connectorColor,
      node: _MindPlusPill(
        pillKey: keyFor(slotId),
        level: level,
        depth: depth,
        toggleLabel: '${level.label} position',
        expanded: isExpanded,
        onAdd: () => onAdd(realParent, level),
        onToggle: canExpand ? () => onToggle(slotId) : null,
      ),
      children: isExpanded
          ? [
              for (var i = 0; i < level.childCapacity; i++)
                _MindPlusNode(
                  level: childLevel!,
                  depth: depth + 1,
                  slotId: '$slotId/${childLevel.name}/$i',
                  realParent: realParent,
                  expanded: expanded,
                  keyFor: keyFor,
                  onToggle: onToggle,
                  onAdd: onAdd,
                ),
            ]
          : const [],
    );
  }
}

/// A filled agent card: a rounded pill in its depth's tint carrying the name
/// and tier, with — when the agent heads a tier — a round chevron button
/// under it. The pill body opens the agent's detail; the button fans the
/// tier below in or out.
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
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              key: boxKey,
              constraints: const BoxConstraints(maxWidth: 240),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
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
                  if (badge != null) ...[
                    const SizedBox(height: 6),
                    badge!,
                  ],
                ],
              ),
            ),
          ),
        ),
        if (onToggle != null) ...[
          const SizedBox(height: 6),
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

  const _MindPlusPill({
    required this.pillKey,
    required this.level,
    required this.depth,
    required this.toggleLabel,
    required this.expanded,
    required this.onAdd,
    required this.onToggle,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
                    Text(
                      level.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: AppColors.textDark.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (onToggle != null) ...[
          const SizedBox(height: 6),
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
        color: _caretColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 26,
            height: 26,
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
  void updateRenderObject(BuildContext context, _RenderMindBranch renderObject) {
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
