import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../auth/auth_service.dart' show FirebaseAuthGateway, OtpError;

/// Sends and checks a real SMS code for the **agent-registration** screen,
/// without ever signing the device in.
///
/// The recruiter is already signed in (member Firebase Phone Auth). Verifying
/// the *new* agent's number on the primary `FirebaseAuth.instance` would swap
/// the device's session onto that number. So this runs the whole round trip on
/// a **secondary Firebase app** (`agentReg`) through an `ephemeral`
/// [FirebaseAuthGateway] that signs out the moment the code checks out — all we
/// want from it is proof the recruit holds the number.
///
/// Best-effort like the rest of the app: if Firebase is not configured on this
/// build, [sendCode] returns [OtpError.unavailable] and the screen surfaces
/// that instead of white-screening.
class AgentOtpVerifier {
  AgentOtpVerifier._();

  static final AgentOtpVerifier instance = AgentOtpVerifier._();

  /// Test hook — a fake the agent-registration screen uses in place of the
  /// real Firebase round trip.
  @visibleForTesting
  static AgentOtpVerifier? debugOverride;

  static AgentOtpVerifier get current => debugOverride ?? instance;

  FirebaseApp? _app;
  FirebaseAuthGateway? _gateway;

  /// The gateway bound to the secondary app, built on first use. Null when
  /// Firebase could not be brought up on this platform.
  Future<FirebaseAuthGateway?> _ensureGateway() async {
    final existing = _gateway;
    if (existing != null) {
      return existing;
    }
    try {
      _app ??= await _openSecondaryApp();
      final auth = fb.FirebaseAuth.instanceFor(app: _app!);
      return _gateway = FirebaseAuthGateway(auth: auth, ephemeral: true);
    } catch (error) {
      debugPrint('AgentOtpVerifier: secondary Firebase app unavailable — $error');
      return null;
    }
  }

  Future<FirebaseApp> _openSecondaryApp() async {
    try {
      return Firebase.app('agentReg');
    } on FirebaseException {
      return Firebase.initializeApp(
        name: 'agentReg',
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  }

  /// Sends a code to [e164Phone] (`+91XXXXXXXXXX`). Null once it is on its way,
  /// otherwise the reason it did not go.
  Future<OtpError?> sendCode(String e164Phone) async {
    final gateway = await _ensureGateway();
    if (gateway == null) {
      return OtpError.unavailable;
    }
    try {
      return await gateway.sendCode(e164Phone);
    } catch (error) {
      debugPrint('AgentOtpVerifier.sendCode: $error');
      return OtpError.unavailable;
    }
  }

  /// Checks [code] against the last [sendCode]. Null on success — the number is
  /// proven and no session is left behind.
  Future<OtpError?> confirmCode(String code) async {
    final gateway = _gateway;
    if (gateway == null) {
      return OtpError.noPendingRequest;
    }
    try {
      return await gateway.confirmCode(code);
    } catch (error) {
      debugPrint('AgentOtpVerifier.confirmCode: $error');
      return OtpError.unknown;
    }
  }

  /// Forget the pending verification (recruiter went back to edit the number).
  void discard() {
    _gateway?.discard();
    _gateway = null;
  }
}
