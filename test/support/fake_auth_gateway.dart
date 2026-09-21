import 'package:shield/module/auth/auth_service.dart';

/// In-memory stand-in for [FirebaseAuthGateway] so unit and widget tests can
/// drive the sign-in flow without a live Firebase project.
///
/// Inject it in `setUp` with
/// `AuthService.instance.useGateway(FakeAuthGateway())`, then verify with
/// [FakeAuthGateway.code].
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({this.acceptedCode = code, AuthUser? persistedUser})
      : _persisted = persistedUser;

  /// The one code [confirmCode] treats as correct.
  static const String code = '123456';

  final String acceptedCode;
  bool _sent = false;

  /// How many codes [sendCode] has been asked to send.
  int codesSent = 0;

  /// Stands in for Firebase's on-device session. Set it via the constructor to
  /// test [AuthService.restoreSession]; [saveDisplayName] updates its name.
  AuthUser? _persisted;

  AuthUser? get persistedUser => _persisted;

  @override
  Future<OtpError?> sendCode(String e164Phone) async {
    _sent = true;
    codesSent++;
    return null;
  }

  @override
  Future<OtpError?> confirmCode(String smsCode) async {
    if (!_sent) {
      return OtpError.noPendingRequest;
    }
    return smsCode == acceptedCode ? null : OtpError.wrongOtp;
  }

  @override
  Future<AuthUser?> restoreUser() async => _persisted;

  @override
  Future<String?> currentIdToken() async => null;

  @override
  Future<void> saveDisplayName(String name) async {
    final current = _persisted;
    if (current != null) {
      _persisted = AuthUser(name: name.trim(), phone: current.phone);
    }
  }

  @override
  void discard() => _sent = false;

  /// Set by [signOut] — lets a test tell "deleted outright" apart from
  /// "[AuthService.deleteAccount] fell back to a plain sign-out", since both
  /// leave [persistedUser] null the same way.
  bool signOutCalled = false;

  @override
  Future<void> signOut() async {
    signOutCalled = true;
    _sent = false;
    _persisted = null;
  }

  /// Whether the next [deleteFirebaseUser] should refuse, as Firebase does
  /// with `requires-recent-login` — set from a test to exercise
  /// [AuthService.deleteAccount]'s sign-out fallback.
  bool refuseDelete = false;

  @override
  Future<bool> deleteFirebaseUser() async {
    if (refuseDelete) {
      return false;
    }
    _sent = false;
    _persisted = null;
    return true;
  }
}
