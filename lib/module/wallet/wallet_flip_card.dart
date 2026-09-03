import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../dates.dart';
import '../../money.dart';
import '../../theme/app_colors.dart';
import '../privilege/plan_status_badge.dart';
import '../privilege/privilege_card_face.dart';
import '../privilege/privilege_tier.dart';
import 'wallet_service.dart';

/// The wallet panel: the account's figures on the front, the plans behind it
/// on the back, and a turn between them.
///
/// A panel, not a payment card. There is no chip, no contactless mark, no
/// stripe and no long number anywhere on it, because none of those are true
/// here — nothing is swiped, tapped or keyed in, and drawing them would
/// promise a card that does not exist. What the two faces are is two sections
/// of the wallet stacked in the same space: a summary of what can be spent,
/// and the list of plans it came from.
///
/// It turns rather than stacking them down the screen because they answer the
/// same question from two sides, and the turn is what says they are the same
/// thing rather than two panels that happen to sit together.
class WalletFlipCard extends StatefulWidget {
  /// Every card on the account, oldest first. One or two in practice; the
  /// back is built from the list either way rather than from a single card,
  /// so a second one needs no second layout.
  final List<WalletCard> cards;

  /// The whole wallet balance, cards and everything else in it.
  final int balance;

  /// What comes due this month, what has gone against it, and what is left.
  final int monthlyRedeemable;
  final int redeemed;
  final int monthlyBalance;

  /// The moment the panel is drawn for, defaulting to now.
  ///
  /// Injectable because which plans have come due is a question about the
  /// date, and a panel that can only ever be seen on today's date cannot be
  /// shown standing on the 24th with one plan open and another still waiting.
  final DateTime? asOf;

  const WalletFlipCard({
    super.key,
    required this.cards,
    required this.balance,
    required this.monthlyRedeemable,
    required this.redeemed,
    required this.monthlyBalance,
    this.asOf,
  });

  /// Long enough to read as a card being turned over rather than as a redraw,
  /// short enough not to be in the way of the balance underneath it.
  static const Duration flipDuration = Duration(milliseconds: 620);

  /// The one size the panel is, whatever is in the wallet.
  ///
  /// It used to grow by a tile for every plan after the first, so taking a
  /// second plan pushed the whole page down and left the panel standing over
  /// the screen with a hole in the middle of it. A wallet is a wallet whether
  /// it holds one plan or three: the panel keeps its size, and the plans it
  /// cannot fit are reached by opening it — see [expandedHeightFor].
  ///
  /// Both faces take this height, because a panel that changed size halfway
  /// through turning would shove the page about underneath it.
  ///
  /// Room for the front in full, and for the back with one plan on it. Down
  /// from 276. Every amount came down to one of three sizes, the balance came
  /// off the back where it was only a second copy of the front's, and the air
  /// between the rows was cut — the panel was tall because of what was
  /// printed on it, not because it needed the room.
  static const double collapsedHeight = 222;

  /// How tall the panel stands while the member has it open on every plan.
  ///
  /// Only ever reached by tapping the arrow on the back. Adding a plan does
  /// not reach it, which is the point: the panel changes size when the member
  /// asks it to and at no other time.
  static double expandedHeightFor(int cardCount) =>
      collapsedHeight + math.max(0, cardCount - 1) * _planTileHeight;

  /// What one more plan adds to the back once it is open.
  static const double _planTileHeight = 92;

  /// How many plan tiles the back shows before it has to be opened.
  ///
  /// One. The collapsed panel has room for a single tile under its heading,
  /// and a second one half cut off would be worse than a line saying it is
  /// there.
  static const int collapsedPlans = 1;

  /// How long the panel takes to open out and fold back.
  ///
  /// Shorter than the turn: the turn has a whole face to swap and this only
  /// has a height to change, and a panel that took as long to open as it does
  /// to turn over would read as a second flip.
  static const Duration openDuration = Duration(milliseconds: 300);

  @override
  State<WalletFlipCard> createState() => _WalletFlipCardState();
}

class _WalletFlipCardState extends State<WalletFlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WalletFlipCard.flipDuration,
  );

  late final Animation<double> _turn = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  /// Whether the member has opened the panel out onto the plans that do not
  /// fit on it.
  ///
  /// Held here rather than on the back, because it is the panel's height it
  /// governs and the back is rebuilt every frame of the turn — a flag kept
  /// down there would be thrown away halfway through.
  bool _expanded = false;

  /// How much taller than [WalletFlipCard.collapsedHeight] the open panel
  /// stands. Nothing, where every plan already fits.
  double get _openBy =>
      WalletFlipCard.expandedHeightFor(widget.cards.length) -
      WalletFlipCard.collapsedHeight;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(WalletFlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A wallet that drops back to a single plan has nothing left to open out
    // onto, and would otherwise stay standing at the height of the plans it
    // no longer holds.
    if (_expanded && widget.cards.length <= WalletFlipCard.collapsedPlans) {
      _expanded = false;
    }
  }

  void _flip() {
    if (_controller.status == AnimationStatus.forward ||
        _controller.value == 1) {
      _controller.reverse();
      // Folded shut on the way to the front. The front has one plan's worth
      // of nothing to say, and would stand there at the height of a back the
      // member can no longer see.
      setState(() => _expanded = false);
    } else {
      _controller.forward();
    }
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return GestureDetector(
          onTap: _flip,
          // The panel grows and shrinks under the member's finger rather than
          // jumping, so the page below it is seen to move out of the way
          // instead of simply being somewhere else the next frame.
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _expanded ? _openBy : 0),
            duration: WalletFlipCard.openDuration,
            curve: Curves.easeInOutCubic,
            builder: (context, open, child) => SizedBox(
              width: width,
              height: WalletFlipCard.collapsedHeight + open,
              child: child,
            ),
            // Built once and handed through: the faces do not depend on the
            // height, and rebuilding them every frame of the opening would
            // restart the back's own page timer under it.
            child: AnimatedBuilder(
              animation: _turn,
              builder: (context, _) {
                final angle = _turn.value * math.pi;
                // Swapped at the halfway point, where the card is edge-on
                // and neither face is readable — which is the only moment
                // the change cannot be seen.
                final back = _turn.value > 0.5;

                return Semantics(
                  button: true,
                  // Inside the builder, so the label turns over with the
                  // card. Outside it, a screen reader would go on offering
                  // the balance long after the cards had come round.
                  label: back
                      ? 'Your privilege cards. Tap to see your balance.'
                      : 'Wallet balance. Tap to see your privilege cards.',
                  child: Transform(
                    alignment: Alignment.center,
                    // A little perspective, so the far edge of the card
                    // shortens as it turns instead of the face merely
                    // squashing horizontally.
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0011)
                      ..rotateY(angle),
                    child: back
                        // Counter-rotated, or the back would be drawn
                        // mirrored once it comes round.
                        ? Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()..rotateY(math.pi),
                            child: _WalletCardBack(
                              cards: widget.cards,
                              asOf: widget.asOf ?? DateTime.now(),
                              expanded: _expanded,
                              onToggleExpanded: _toggleExpanded,
                            ),
                          )
                        : _WalletCardFront(
                            balance: widget.balance,
                            monthlyRedeemable: widget.monthlyRedeemable,
                            redeemed: widget.redeemed,
                            monthlyBalance: widget.monthlyBalance,
                            cardCount: widget.cards.length,
                          ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Type on the wallet panel: white, like the type on a privilege card face
/// and on the top-up button the panel now shares its blue with.
///
/// Named rather than called through, so the one place deciding what ink this
/// panel is set in stays here — the panel has been teal, navy, near-white and
/// blue, and every one of those moves turned on this single question.
TextStyle _onPanel(double size, FontWeight weight) =>
    PrivilegeCardFace.onCard(size, weight);

/// The sizes every amount on this panel is set at, and no others.
///
/// Three: the balance the front leads with, the monthly figures under it, and
/// an amount on a tile. They used to be picked per call site — 34, 19, 19, 14,
/// 12.5 — which is why no two of them lined up, and part of why the panel had
/// to be so tall to hold them.
abstract final class _AmountSize {
  static const double balance = 26;
  static const double figure = 16;
  static const double tile = 13;
}

/// The blue panel both faces are drawn on, whatever is in the wallet.
class _CardShell extends StatelessWidget {
  final Widget child;

  const _CardShell({required this.child});

  static final BorderRadius radius = BorderRadius.circular(18);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: AppColors.walletShadow.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          // Flat, and the button's own blue. No gradient: the panel is here
          // to match the control sitting under it, and one that darkened
          // across its own face would stop matching it halfway along.
          decoration: const BoxDecoration(color: AppColors.walletPanel),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Light catching the corner, in the brand green. It is the one
              // warm thing on a panel that is otherwise the app's navy, and
              // it is fixed rather than taking a plan's colour — the panel
              // holds more than one plan, and a highlight that changed with
              // whichever was listed first would say nothing. Which plan is
              // which, and which of them can be spent, is said on the tiles.
              Positioned(
                right: -70,
                top: -90,
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.brandGreen.withValues(alpha: 0.24),
                        AppColors.brandGreen.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// What is in the wallet and what may be drawn from it this month.
class _WalletCardFront extends StatelessWidget {
  final int balance;
  final int monthlyRedeemable;
  final int redeemed;
  final int monthlyBalance;
  final int cardCount;

  const _WalletCardFront({
    required this.balance,
    required this.monthlyRedeemable,
    required this.redeemed,
    required this.monthlyBalance,
    required this.cardCount,
  });

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PanelHeading('SHIELD wallet'),
            const SizedBox(height: 12),
            const _CardCaption('TOTAL BALANCE'),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '₹${formatRupees(balance)}.00',
                maxLines: 1,
                style: _onPanel(
                  _AmountSize.balance,
                  FontWeight.w800,
                ).copyWith(letterSpacing: -0.4),
              ),
            ),
            const Spacer(),
            const Divider(height: 18, color: Color(0x3DFFFFFF)),
            // "Monthly" said once, over the three figures it qualifies,
            // rather than repeated inside two of their labels. That is what
            // buys the width to set them at a size worth reading: at 320px
            // "MONTHLY REDEEMABLE" did not fit its column and was being
            // clipped even at the smaller size.
            const _CardCaption('THIS MONTH'),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CardFigure(
                    label: 'REDEEMABLE',
                    amount: monthlyRedeemable,
                  ),
                ),
                Expanded(
                  child: _CardFigure(label: 'REDEEMED', amount: redeemed),
                ),
                Expanded(
                  child: _CardFigure(
                    label: 'REMAINING',
                    amount: monthlyBalance,
                    alignEnd: true,
                    highlight: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _FlipHint(
              text: cardCount == 1
                  ? 'Tap to see your plan'
                  : 'Tap to see your $cardCount plans',
            ),
          ],
        ),
      ),
    );
  }
}

/// The plans behind the balance, over two pages.
///
/// The first page is the plans themselves — which ones the account holds,
/// what each carries, and whether its month has come round. The second is how
/// their money is actually being let out: a twelfth at a time, so many of
/// twelve gone and so much still to come.
///
/// Two pages rather than one long face because they answer different
/// questions — "what do I hold" and "what can I spend and when" — and neither
/// could be read if both were printed on a panel this size.
///
/// It turns itself to the second page shortly after coming round, and again
/// back, then stops. A page nobody knows is there is a page nobody swipes to,
/// and a panel that keeps sliding under the eye while it is being read is not
/// showing the member anything — it is taking it away again. The same reason
/// the reward graph blinks four times and then holds still.
class _WalletCardBack extends StatefulWidget {
  final List<WalletCard> cards;
  final DateTime asOf;

  /// Whether the panel is standing open on every plan, or on the one it has
  /// room for.
  final bool expanded;

  /// Turns the panel open and shut. Held by the panel rather than here,
  /// because it is the panel's height that answers.
  final VoidCallback onToggleExpanded;

  const _WalletCardBack({
    required this.cards,
    required this.asOf,
    required this.expanded,
    required this.onToggleExpanded,
  });

  /// How long a page holds before the back turns itself to the next.
  static const Duration dwell = Duration(milliseconds: 2400);

  /// How long that turn takes.
  static const Duration turn = Duration(milliseconds: 420);

  /// How many times it turns itself before leaving the pages alone: over to
  /// the second page and back, and then it is the member's to drive.
  static const int autoTurns = 2;

  @override
  State<_WalletCardBack> createState() => _WalletCardBackState();
}

class _WalletCardBackState extends State<_WalletCardBack> {
  static const int _pageCount = 2;

  final PageController _pages = PageController();

  Timer? _timer;
  int _page = 0;
  int _turnsLeft = _WalletCardBack.autoTurns;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  /// One shot, re-armed after each turn it is still allowed, rather than a
  /// repeating timer that would outlive the turns and have to be stopped from
  /// somewhere else.
  void _arm() {
    _timer?.cancel();
    if (_turnsLeft <= 0) {
      return;
    }
    _timer = Timer(_WalletCardBack.dwell, _advance);
  }

  void _advance() {
    if (!mounted || !_pages.hasClients || _turnsLeft <= 0) {
      return;
    }
    _turnsLeft--;
    _pages.animateToPage(
      (_page + 1) % _pageCount,
      duration: _WalletCardBack.turn,
      curve: Curves.easeInOutCubic,
    );
    _arm();
  }

  /// A finger on the panel is the member taking the pages over, and the back
  /// stops turning itself from then on — including the turn already armed.
  void _stopAuto() {
    _timer?.cancel();
    _turnsLeft = 0;
  }

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Listener(
                onPointerDown: (_) => _stopAuto(),
                child: PageView(
                  controller: _pages,
                  onPageChanged: (index) => setState(() => _page = index),
                  children: [_plansPage(), _releasePage()],
                ),
              ),
            ),
            // No balance down here. It is the first thing on the front, in
            // the size the panel leads with, and a second copy in a smaller
            // one only asked which of the two was the real figure.
            const SizedBox(height: 8),
            Row(
              children: [
                _Pips(count: _pageCount, active: _page),
                const SizedBox(width: 10),
                const Expanded(child: _FlipHint(text: 'Tap to go back')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// How many tiles a page prints: every plan while the panel is open, and
  /// only what fits while it is not.
  int get _shown => widget.expanded
      ? widget.cards.length
      : math.min(widget.cards.length, WalletFlipCard.collapsedPlans);

  /// The plans there is no room for on the closed panel.
  int get _hidden => widget.cards.length - _shown;

  Widget _plansPage() {
    return _PanelPage(
      children: [
        _PanelHeading(
          widget.cards.length == 1 ? 'Your plan' : 'Your plans',
          // The count is worth saying only when there is more than one:
          // "1" next to "Your plan" tells nobody anything.
          trailing: widget.cards.length == 1 ? null : '${widget.cards.length}',
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _shown; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _PlanTile(card: widget.cards[i], asOf: widget.asOf),
        ],
        _openControl(),
      ],
    );
  }

  Widget _releasePage() {
    return _PanelPage(
      children: [
        const _PanelHeading('Monthly release'),
        const SizedBox(height: 10),
        for (var i = 0; i < _shown; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _ReleaseTile(card: widget.cards[i], asOf: widget.asOf),
        ],
        _openControl(),
      ],
    );
  }

  /// The arrow that opens the panel onto the plans it is not tall enough to
  /// show, sitting directly under the last tile it has room for — which is
  /// where the plans it is standing in for would have been.
  ///
  /// Nothing at all where every plan already fits: a control offering to show
  /// what is already on the panel is a control that lies.
  Widget _openControl() {
    if (widget.cards.length <= WalletFlipCard.collapsedPlans) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _OpenPanelControl(
        expanded: widget.expanded,
        hidden: _hidden,
        onTap: widget.onToggleExpanded,
      ),
    );
  }
}

/// The line that opens the back out onto every plan and folds it shut again.
///
/// An arrow, the same chevron the programme card is opened with, turned to
/// point the way the panel is about to move. The panel does not grow when a
/// plan is taken — it grows when this is tapped, and that is the whole of the
/// difference: a wallet that resized itself under the member every time they
/// bought something was a wallet whose size meant nothing.
class _OpenPanelControl extends StatelessWidget {
  final bool expanded;

  /// How many plans are being stood in for. Only read while closed.
  final int hidden;

  final VoidCallback onTap;

  const _OpenPanelControl({
    required this.expanded,
    required this.hidden,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final plans = hidden == 1 ? 'plan' : 'plans';
    final label = expanded ? 'Show less' : '$hidden more $plans';

    return Semantics(
      button: true,
      label: expanded ? 'Show fewer plans' : 'Show $hidden more $plans',
      child: GestureDetector(
        // Its own detector, inside the panel's. The innermost wins the tap,
        // so opening the panel does not also turn it back over — which is
        // what a bare icon painted on the face would have done.
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _onPanel(
                  11.5,
                  FontWeight.w700,
                ).copyWith(color: const Color(0xFFCBD9EE)),
              ),
            ),
            const SizedBox(width: 4),
            // Down while there is more below, up once there is not: the arrow
            // points at what tapping it does, not at where the list is.
            AnimatedRotation(
              turns: expanded ? -0.25 : 0.25,
              duration: WalletFlipCard.openDuration,
              curve: Curves.easeInOutCubic,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One page of the back, hung from the top of the face and cut off at the
/// bottom edge of it.
///
/// Cut off rather than squeezed, because the panel opens over 300ms and its
/// contents change on the first frame of that: for a third of a second the
/// tiles are taller than the panel holding them. A column told to fit would
/// spend that third of a second reporting an overflow; one hung in a clip
/// simply grows out from under the edge as the edge comes up to meet it.
///
/// It is also what keeps a member reading at triple text size out of a red
/// and yellow bar — the tile runs past the edge and is trimmed, rather than
/// breaking the face it is printed on.
class _PanelPage extends StatelessWidget {
  final List<Widget> children;

  const _PanelPage({required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 0,
        maxHeight: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Which of the back's pages is showing.
class _Pips extends StatelessWidget {
  final int count;
  final int active;

  const _Pips({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: i == active ? 15 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(
                alpha: i == active ? 0.92 : 0.32,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ],
      ],
    );
  }
}

/// One plan on the back: which plan it is, what it carries, and the two dates
/// that matter — when it was last recharged and when it expires.
///
/// A tile on the panel rather than a line printed on a card back. The plans
/// are a list, and a list is what they should look like.
class _PlanTile extends StatelessWidget {
  final WalletCard card;
  final DateTime asOf;

  const _PlanTile({required this.card, required this.asOf});

  @override
  Widget build(BuildContext context) {

    // Green where the plan's month has come round, red where it has not,
    // grey once it has expired. The
    // stripe used to carry the tier's own colour, which said which plan it was
    // — something the name printed beside it already says. What a member wants
    // off one glance at a wallet holding two plans is which of them they can
    // spend today, and that is what it says now.
    return _StripeTile(
      stripe: _planStripe(card, asOf),
      padding: const EdgeInsets.fromLTRB(11, 9, 12, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _onPanel(14, FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                card.loadedLabel,
                maxLines: 1,
                style: _onPanel(_AmountSize.tile, FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _StatusLine(card: card, asOf: asOf),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _BackDate(
                  icon: Icons.autorenew_rounded,
                  label: 'Recharged',
                  value: card.rechargedOnLabel,
                ),
              ),
              Expanded(
                child: _BackDate(
                  icon: Icons.event_busy_rounded,
                  label: 'Expires',
                  value: card.expiresOnLabel,
                  // An expired plan is the one thing on this face that has to
                  // be read before the amounts, so it is the one thing not
                  // printed in white.
                  warn: card.isExpired,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A white tile with a coloured bar down its left edge.
///
/// The bar is a child rather than a [Border] side, because a border whose
/// sides are different colours cannot be given rounded corners — and the tile
/// has to be rounded to sit on this panel with everything else.
class _StripeTile extends StatelessWidget {
  /// How wide the coloured bar runs.
  static const double _stripeWidth = 3;

  final Color stripe;
  final EdgeInsets padding;
  final Widget child;

  const _StripeTile({
    required this.stripe,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.16)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        // A stack rather than a row, so the tile stays as tall as whatever is
        // written on it. A row stretched to run the bar down the full edge
        // would have to be given that height from outside, and the panel sizes
        // these tiles from their contents.
        child: Stack(
          children: [
            Padding(
              padding: padding.copyWith(left: padding.left + _stripeWidth),
              child: child,
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _stripeWidth,
              child: ColoredBox(color: stripe),
            ),
          ],
        ),
      ),
    );
  }
}

Color _statusColour(bool active) =>
    active ? AppColors.planActive : AppColors.planWaiting;

/// The stripe / accent colour for a plan card: greyed once the plan has
/// expired, otherwise green when this month has come round and salmon while
/// it waits.
Color _planStripe(WalletCard card, DateTime asOf) => card.isExpired
    ? PlanStatusBadge.colourOf(PlanStatus.expired)
    : _statusColour(card.isActiveOn(asOf));

/// Whether a plan's month has come round, and the date it turns over on.
///
/// The two things a member with more than one plan cannot work out for
/// themselves: the plans were taken on different days, so they come due on
/// different days, and nothing else on the panel says which is which.
class _StatusLine extends StatelessWidget {
  final WalletCard card;
  final DateTime asOf;

  const _StatusLine({required this.card, required this.asOf});

  @override
  Widget build(BuildContext context) {
    final expired = card.isExpired;
    final active = card.isActiveOn(asOf);
    // Grey once the plan has lapsed; otherwise green when this month has come
    // round and salmon while it waits.
    final colour = expired
        ? PlanStatusBadge.colourOf(PlanStatus.expired)
        : _statusColour(active);
    final label = expired ? 'Expired' : (active ? 'Active' : 'Waiting');
    // Active, and the date is the next turnover. Waiting, and it is the day
    // this month that the plan opens. Expired, and it is the day it lapsed.
    final due = active ? card.nextDueOn(asOf) : card.dueDayIn(asOf);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colour.withValues(alpha: 0.65)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: _onPanel(
                  10,
                  FontWeight.w800,
                ).copyWith(color: colour, letterSpacing: 0.3),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            expired
                ? 'Expired ${formatDayMonth(card.expiresOn)}'
                : active
                    ? 'Renews ${formatDayMonth(due)}'
                    : 'Opens ${formatDayMonth(due)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _onPanel(11.5, FontWeight.w800).copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}

/// How one plan's money is being let out: a twelfth a month, so many of the
/// twelve gone and so much of it still to come.
///
/// The second page of the back, and the answer to the question the first page
/// raises. A plan carrying ₹11,000 does not hand over ₹11,000: it hands over
/// ₹916 twelve times, and a member looking at a ₹14,472 balance has no way to
/// know that from the front.
class _ReleaseTile extends StatelessWidget {
  final WalletCard card;
  final DateTime asOf;

  const _ReleaseTile({required this.card, required this.asOf});

  @override
  Widget build(BuildContext context) {
    final colour = _planStripe(card, asOf);
    final released = card.instalmentOn(asOf);
    const total = PrivilegeProgramme.validityMonths;

    return _StripeTile(
      stripe: colour,
      padding: const EdgeInsets.fromLTRB(11, 8, 12, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _onPanel(13, FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹${formatRupees(card.monthlyRedeemable)} / month',
                maxLines: 1,
                style: _onPanel(
                  _AmountSize.tile,
                  FontWeight.w800,
                ).copyWith(color: colour),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: released / total,
              minHeight: 5,
              backgroundColor: AppColors.white.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$released of $total released',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _onPanel(
                    10.5,
                    FontWeight.w600,
                  ).copyWith(color: const Color(0xFFCBD9EE)),
                ),
              ),
              const SizedBox(width: 8),
              // "left", not "still to come": on a 320pt phone a six-figure
              // amount plus that phrase runs past the edge of the tile, and
              // the shorter word is the one carrying the meaning anyway.
              Text(
                '₹${formatRupees(card.remainingAfter(asOf))} left',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _onPanel(
                  10.5,
                  FontWeight.w700,
                ).copyWith(color: const Color(0xFFCBD9EE)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackDate extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool warn;

  const _BackDate({
    required this.icon,
    required this.label,
    required this.value,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final colour = warn ? const Color(0xFFF3A6A4) : const Color(0xFFCBD9EE);
    return Row(
      children: [
        Icon(icon, size: 12, color: colour),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '$label $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _onPanel(10.5, FontWeight.w600).copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}

/// One of the three figures under the balance.
class _CardFigure extends StatelessWidget {
  final String label;
  final int amount;
  final bool alignEnd;

  /// Printed in the brand green: what is left to spend is the figure the
  /// front is actually asked for, and the other two are the working behind it.
  final bool highlight;

  const _CardFigure({
    required this.label,
    required this.amount,
    this.alignEnd = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        _CardCaption(label, alignEnd: alignEnd, size: 10),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            '₹${formatRupees(amount)}',
            maxLines: 1,
            style: _onPanel(_AmountSize.figure, FontWeight.w800).copyWith(
              color: highlight ? AppColors.planActive : AppColors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// The small caps a figure is labelled with.
class _CardCaption extends StatelessWidget {
  final String text;
  final bool alignEnd;

  /// Bigger under the three figures than over the balance, because there it
  /// is the only thing naming a number that would otherwise be a bare amount.
  final double size;

  const _CardCaption(this.text, {this.alignEnd = false, this.size = 9});

  @override
  Widget build(BuildContext context) {
    // Scaled down to fit rather than cut off with an ellipsis. A caption is
    // the only thing telling you which number you are looking at, and
    // "REDEEMAB…" on a narrow phone would cost the reader the very word they
    // needed. Set at the size below wherever there is room for it, and a
    // little smaller where there is not.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: _onPanel(
          size,
          FontWeight.w800,
        ).copyWith(letterSpacing: 0.7, color: const Color(0xCCFFFFFF)),
      ),
    );
  }
}

/// The line that names a face, with the SHIELD mark against it.
///
/// The mark is the brand's, not a card issuer's badge: it is here so the
/// panel is recognisably SHIELD's, and it is the only ornament on either
/// face.
class _PanelHeading extends StatelessWidget {
  final String text;

  /// A count set in a small capsule, for a face that has more than one of
  /// something to show.
  final String? trailing;

  const _PanelHeading(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _onPanel(15, FontWeight.w800).copyWith(letterSpacing: 0.2),
          ),
        ),
        if (trailing != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(trailing!, style: _onPanel(12, FontWeight.w800)),
          ),
          const SizedBox(width: 10),
        ],
        const PrivilegeIssuerMark(size: 26),
      ],
    );
  }
}

/// Says the panel turns over. A panel that flips with nothing to say so is a
/// panel nobody flips.
class _FlipHint extends StatelessWidget {
  final String text;

  const _FlipHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Flexible, not bare: the hint is the longest run of prose on the
        // card and the widest phrase of it must give way rather than push
        // the icon off the edge.
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _onPanel(
              10.5,
              FontWeight.w600,
            ).copyWith(color: const Color(0xFFCBD9EE)),
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.flip_camera_android_rounded,
          size: 13,
          color: AppColors.white.withValues(alpha: 0.7),
        ),
      ],
    );
  }
}
