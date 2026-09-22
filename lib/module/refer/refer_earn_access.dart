import 'package:flutter/material.dart';

import '../agent/agent_service.dart';
import '../auth/auth_service.dart';
import '../investor/investor_service.dart';
import '../persona/persona_service.dart';

/// Whether the signed-in member is offered Refer & Earn at all.
///
/// Only a plain member is. A member the Super Admin has made an agent or an
/// investor is shown their agent / investor details instead, and nothing
/// about Refer & Earn — not the home card, the menu row, the Account row nor
/// the Rewards card. Every one of those goes through here, so the rule is
/// stated once and cannot drift between screens.
///
/// Nothing is offered until [PersonaService] has resolved who the member is.
/// Offering it first and taking it away would flash Refer & Earn at every
/// agent on each sign-in — the reason the home slot holds a skeleton until
/// then — so the answer stays "no" until it is known, then a plain member
/// gets it without doing anything.
class ReferEarnAccess {
  const ReferEarnAccess._();

  /// Everything [isOffered] reads; rebuild on this.
  static Listenable get changes => Listenable.merge([
    AuthService.instance.currentUser,
    PersonaService.instance,
    AgentService.instance,
    InvestorService.instance,
  ]);

  static bool get isOffered {
    final phone = AuthService.instance.currentUser.value?.phone;
    if (phone == null || !PersonaService.instance.isResolved ||
        PersonaService.instance.isConverted) {
      return false;
    }
    return AgentService.instance.agentForPhone(phone) == null &&
        InvestorService.instance.investorForPhone(phone) == null;
  }
}

/// Shows [child] to a member who is offered Refer & Earn, and nothing to an
/// agent or an investor. Follows the persona live, so a member converted (or
/// un-converted) while the screen is open gains or loses it in place.
class ReferEarnGate extends StatelessWidget {
  final Widget child;

  const ReferEarnGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ReferEarnAccess.changes,
      builder: (context, _) =>
          ReferEarnAccess.isOffered ? child : const SizedBox.shrink(),
    );
  }
}
