import '../orders/purchase_service.dart';
import '../wallet/wallet_service.dart';

/// What "Your earnings" adds up to across both ways Sahakar 360 gives money back:
/// the discount on every order, and the 10% bonus Sahakar 360 adds when a
/// privilege plan is activated. One place for the sum, so the home card and
/// the detail screen can never disagree about what it comes to.
///
/// A privilege plan does not discount a printed price the way an order
/// does — the member pays the card's full load and Sahakar 360 adds 10% on top —
/// but it still reads on the same "printed vs. paid vs. kept" shape: the
/// card's credited value (load plus bonus) standing in for a printed price,
/// its load standing in for what was paid, and the bonus itself standing in
/// for what was saved.
class MemberEarnings {
  const MemberEarnings._();

  /// What everything would be worth at full value: printed price on every
  /// order, and the credited value — load plus bonus — of every privilege
  /// plan.
  static int get totalPrice => PurchaseService.instance.mrpTotal + _planCredited;

  /// What actually left the member's pocket: the discounted order price, and
  /// a plan's own load. The bonus was never paid — it was added.
  static int get paid => PurchaseService.instance.paidTotal + _planPaid;

  /// The one figure "Your earnings" is: order discounts plus plan bonuses.
  /// Worked out as [totalPrice] less [paid] rather than added up from the two
  /// sources separately, so it can never disagree with either of them.
  static int get saved => (totalPrice - paid).clamp(0, totalPrice);

  static double get savedFraction => totalPrice <= 0 ? 0 : saved / totalPrice;

  /// "26%" — [savedFraction] as a whole number of percent.
  static String get savedPercentLabel =>
      '${(savedFraction * 100).round()}%';

  /// Every plan the member has activated, oldest first — the list the
  /// bonus breakdown is drawn from.
  static List<WalletCard> get plans => WalletService.instance.cards;

  static int get _planCredited =>
      plans.fold(0, (sum, card) => sum + card.load.credited);

  static int get _planPaid =>
      plans.fold(0, (sum, card) => sum + card.load.amount);
}
