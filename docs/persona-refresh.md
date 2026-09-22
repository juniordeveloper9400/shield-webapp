# Converted member cards

The authenticated agent and investor endpoints determine which home card appears.
Refer & Earn is offered only after a successful lookup confirms an ordinary member.
Network errors or an unavailable backend session leave the role unresolved, or retain
the last confirmed role for that account. Home displays a Retry action for an initial
failure. Session switches invalidate pending results and queue a new lookup.

The local role record uses the signed-in phone as its lookup key because the server
already authenticated ownership; admin-entered contact formatting does not change
which account receives the card. Existing sign-in, resume and polling refreshes apply.

Regression checks: `flutter test test/persona_refresh_test.dart test/home_refer_earn_test.dart test/refer_earn_access_test.dart`.
