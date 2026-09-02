import '../registration/shield_store.dart';
import 'investor_model.dart';

/// The seed investor — [InvestorService] is what a screen actually reads;
/// this is only where that starts from. A backend would replace it wholesale.
class InvestorDirectory {
  const InvestorDirectory._();

  /// The outlet [demo]'s stake is in, and the one the home feed's
  /// investment offer points at — a demo with one investor only ever has
  /// the one opportunity to advertise.
  static final ShieldStore featuredStore = StoreDirectory.all.first;

  /// The demo persona. Signing in with [Investor.phone] is what the login
  /// screen recognises — the same way the agent number turns the home
  /// "Refer & Earn" card into the Agent Portal card, this one adds the
  /// Investor Access card alongside it.
  static final Investor demo = Investor(
    id: 'inv-001',
    name: 'Rasheed Koya',
    phone: '9876543210',
    investorCode: 'SHD-INV-001',
    investedStore: featuredStore,
    // ₹1,50,000 a unit, ten units — ₹15,00,000 in.
    totalUnits: 10,
    unitPrice: 150000,
    investedSince: DateTime(2023, 4, 1),
    roiPercent: 18.5,
    planType: InvestorPlanType.yearly,
  );

  static final List<Investor> seed = [demo];
}
