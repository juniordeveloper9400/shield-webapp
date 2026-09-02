import 'package:flutter/foundation.dart';

import 'investor_directory.dart';
import 'investor_model.dart';

/// Access into the investor world: resolving who the signed-in investor is.
class InvestorService extends ChangeNotifier {
  InvestorService._();

  static final InvestorService instance = InvestorService._();

  /// Whether the signed-in investor has asked to switch their return plan.
  ///
  /// Set for the session when the portal's "Request … plan" action is used, so
  /// the button reads back as "Change requested" and cannot be tapped twice.
  /// The durable record is the `app.investor_plan_change_request` row
  /// [InvestorRepository] writes; this is only the running app's memory of it.
  bool _planChangeRequested = false;

  bool get planChangeRequested => _planChangeRequested;

  /// Records that a plan-change request has been sent.
  void markPlanChangeRequested() {
    if (_planChangeRequested) {
      return;
    }
    _planChangeRequested = true;
    notifyListeners();
  }

  /// The investor for [phone], or null when the number is not one. Only the
  /// seed persona carries a real number in this demo.
  Investor? investorForPhone(String? phone) {
    if (phone == null) {
      return null;
    }
    final clean = phone.trim();
    for (final investor in InvestorDirectory.seed) {
      if (investor.phone == clean) {
        return investor;
      }
    }
    return null;
  }

  @visibleForTesting
  void reset() {
    _planChangeRequested = false;
    notifyListeners();
  }
}
