import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import '../../data/neon/member_repository.dart';
import 'otp_send_throttle.dart';

/// A signed-in member.
///
/// Identity is the mobile number: it is what the code was sent to, and it is
/// what the backend keys the account on. The name is what the member typed on
/// the way in and is only ever used for display — Firebase Phone Auth does not
/// carry one, so the app holds it alongside the session.
@immutable
class AuthUser {
  final String name;
  final String phone;

  const AuthUser({required this.name, required this.phone});

  /// One or two letters for the avatar circle.
  String get initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return '?';
    }
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }

  /// `+91 9876543210` — the form the account and menu screens show.
  String get displayPhone => '+91 $phone';
}

/// Why a step of the OTP flow was rejected.
enum OtpError {
  invalidName,
  invalidPhone,
  noPendingRequest,
  wrongOtp,

  /// The verification session lapsed before the code was entered.
  codeExpired,

  /// Firebase is rate-limiting this device or number.
  tooManyRequests,

  /// The app's own cap — four code requests inside an hour — has been hit.
  /// Unlike [tooManyRequests] this never reaches Firebase; it keeps the
  /// device well inside Firebase's harsher, opaque block. See
  /// [AuthService.sendCooldownRemaining] for the wait.
  throttled,

  /// The project's SMS allowance is used up.
  quotaExceeded,

  /// The send or verify call could not reach Firebase.
  network,

  /// Firebase never called back — usually the reCAPTCHA "verifying you're not
  /// a robot" fallback opened and stalled, so `codeSent` never fired and no
  /// SMS went out. The flow is abandoned rather than left spinning forever.
  timeout,

  /// Firebase Phone Auth is not available on this build — usually
  /// `Firebase.initializeApp()` failed at launch because the current platform
  /// has no configured options (only Android is wired; see FIREBASE_SETUP.md).
  unavailable,

  /// The Firebase project itself is not set up to send this SMS and retrying
  /// will not help: the Phone provider is disabled, the project is still on
  /// the no-billing Spark plan, or this build's SHA fingerprints are not
  /// registered. See FIREBASE_SETUP.md.
  configError,

  /// Anything Firebase reported that does not map to one of the above.
  unknown,
}

/// Phone-number sign-in for the member session.
///
/// The flow is two calls — [requestOtp] sends the SMS, [verifyOtp] checks the
/// code — and the same [currentUser] notifier every screen already listens to.
/// The work behind those two calls is delegated to an [AuthGateway]; in the
/// app that is always [FirebaseAuthGateway] (Firebase Phone Auth), built lazily
/// on first use so `Firebase.initializeApp()` in `main()` has already run.
/// There is no demo or offline fallback — a real code is sent and checked.
/// Tests inject an in-memory fake with [useGateway] before driving the flow.
///
/// Finishing the Firebase side (project `shield-zabnix`) is a checklist in
/// `FIREBASE_SETUP.md` at the repo root: `flutterfire configure`, enable the
/// Phone provider, register the app's SHA fingerprints, add an APNs key for
/// iOS. The Admin SDK service account (`firebase-adminsdk-…@…gserviceaccount
/// .com`) is a server credential and must never be added to this app.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  /// Stand-in code the agent registration screen's placeholder OTP step still
  /// accepts (see `agent_registration_screen.dart`). The member sign-in flow
  /// below does real Firebase verification and never uses this.
  static const String demoOtp = '123456';

  /// Digits in a code. The OTP field draws this many boxes.
  static const int otpLength = 6;

  /// How long the member waits before a resend is offered.
  static const Duration resendCooldown = Duration(seconds: 30);

  /// Null while signed out. Widgets listen to this to decide what to show.
  final ValueNotifier<AuthUser?> currentUser = ValueNotifier<AuthUser?>(null);

  /// Sends and checks the code. Null until first used or injected by a test;
  /// the app builds a [FirebaseAuthGateway] on first access via [_activeGateway].
  AuthGateway? _gateway;

  /// The gateway to run send/verify against, building the Firebase one on
  /// first use. Only reached from [requestOtp] / [verifyOtp], which run after
  /// `Firebase.initializeApp()`; tests must call [useGateway] first so this
  /// never constructs a real Firebase client.
  AuthGateway get _activeGateway =>
      _gateway ??= FirebaseAuthGateway(onResolved: _resolvePendingFromGateway);

  /// The raw Firebase error code behind the most recent config failure
  /// (`operation-not-allowed`, `unauthorized-domain`, `billing-not-enabled`,
  /// …), or null. Shown under the "not set up" line so a support screenshot
  /// names the exact Firebase console setting to fix.
  String? get lastAuthDiagnostic {
    final gateway = _gateway;
    return gateway is FirebaseAuthGateway ? gateway.lastDiagnostic : null;
  }

  /// The local cap on code requests: four an hour, then the send button is
  /// refused until the oldest ages out.
  final OtpSendThrottle _sendThrottle = OtpSendThrottle();

  /// How long the member must wait before another code can be requested, set
  /// whenever [requestOtp] returns [OtpError.throttled]. Read by the login
  /// form to say "try again in N min".
  Duration? _sendCooldownRemaining;

  Duration? get sendCooldownRemaining => _sendCooldownRemaining;

  /// Set between [requestOtp] and [verifyOtp] — the half-finished sign-in.
  _PendingLogin? _pending;

  /// The member from the most recent *active* sign-in, held until the shell
  /// reads it once with [consumeFreshSignIn]. A session restored at launch does
  /// not set this, so the welcome shows only when someone actually signs in.
  AuthUser? _freshSignIn;

  bool get isSignedIn => currentUser.value != null;

  /// Returns the just-signed-in member once, then forgets them. The app shell
  /// calls this on first build to decide whether to greet the member.
  AuthUser? consumeFreshSignIn() {
    final user = _freshSignIn;
    _freshSignIn = null;
    return user;
  }

  /// True once a code has been sent and not yet verified or abandoned.
  bool get hasPendingOtp => _pending != null;

  String? get pendingName => _pending?.name;

  String? get pendingPhone => _pending?.phone;

  /// Android instant verification / SMS auto-retrieval signs the member into
  /// Firebase without the code ever being typed. When that happens the gateway
  /// calls this, and the half-finished sign-in is completed the same way
  /// [verifyOtp] would have — so the member is not left sitting on the code
  /// screen while Firebase already considers them signed in.
  void _resolvePendingFromGateway() {
    final pending = _pending;
    if (pending == null) {
      return;
    }
    _pending = null;
    final user = AuthUser(name: pending.name, phone: pending.phone);
    currentUser.value = user;
    _afterSignIn(user);
  }

  /// Persists the freshly signed-in user: writes the name onto the Firebase
  /// profile so the next launch has it, and records the account in the
  /// `app.users` table. Both are best-effort and never block the sign-in.
  void _afterSignIn(AuthUser user) {
    _freshSignIn = user;
    // Signed in — clear the hourly send cap so a later sign-in starts fresh.
    _sendCooldownRemaining = null;
    unawaited(_sendThrottle.reset());
    unawaited(_activeGateway.saveDisplayName(user.name));
    unawaited(
      MemberRepository.instance.upsertOnSignIn(
        name: user.name,
        phone: user.phone,
      ),
    );
  }

  /// Restores a persisted sign-in at launch, so a member who has signed in
  /// once goes straight into the app without seeing the login screen again.
  ///
  /// Call from `main()` once `Firebase.initializeApp()` has run. A no-op when
  /// already signed in, when there is no live session on the device, or when
  /// Firebase is unavailable on this build.
  Future<void> restoreSession() async {
    if (isSignedIn) {
      return;
    }

    final AuthUser? restored;
    try {
      restored = await _activeGateway.restoreUser();
    } catch (error) {
      debugPrint('restoreSession: gateway unavailable — $error');
      return;
    }
    if (restored == null || restored.phone.isEmpty) {
      return;
    }

    // Phone Auth keeps the number but not the name. Take it from the profile,
    // falling back to the members table, then to a neutral placeholder that
    // registration will overwrite.
    var name = restored.name.trim();
    if (name.isEmpty) {
      name = (await MemberRepository.instance.nameByPhone(restored.phone))
              ?.trim() ??
          '';
    }

    currentUser.value = AuthUser(
      name: name.isEmpty ? 'Member' : name,
      phone: restored.phone,
    );
    unawaited(MemberRepository.instance.touchLogin(restored.phone));
  }

  /// Null when [value] is usable as a name, otherwise the reason it is not.
  static String? validateName(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'Name is required';
    }
    if (text.length < 2) {
      return 'Enter at least 2 characters';
    }
    if (!RegExp(r"^[A-Za-z][A-Za-z .'-]*$").hasMatch(text)) {
      return 'Use letters only';
    }
    return null;
  }

  /// Null when [value] is a plausible Indian mobile number.
  static String? validatePhone(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'Mobile number is required';
    }
    if (text.length != 10 || int.tryParse(text) == null) {
      return 'Enter a valid 10-digit number';
    }
    if (!RegExp(r'^[6-9]').hasMatch(text)) {
      return 'Mobile numbers start with 6-9';
    }
    return null;
  }

  /// Sends a code to [phone] and holds the details until it is verified.
  /// Returns null when the code went out, otherwise the reason it did not.
  ///
  /// [name] is given on the sign-up path and left null on the sign-in path —
  /// a returning member's name is read back from `app.users` in [verifyOtp].
  Future<OtpError?> requestOtp({
    String? name,
    required String phone,
  }) async {
    final cleanName = name?.trim() ?? '';
    final cleanPhone = phone.trim();
    if (name != null && validateName(cleanName) != null) {
      return OtpError.invalidName;
    }
    if (validatePhone(cleanPhone) != null) {
      return OtpError.invalidPhone;
    }

    // The app's own cap — four requests an hour — checked before Firebase is
    // touched, so a member who keeps tapping never trips Firebase's own
    // harsher block.
    final blocked = await _sendThrottle.blockedFor();
    if (blocked != null) {
      _sendCooldownRemaining = blocked;
      return OtpError.throttled;
    }

    final OtpError? failure;
    try {
      failure = await _activeGateway.sendCode('+91$cleanPhone');
    } catch (error) {
      // No Firebase app on this platform, or the plugin threw before it could
      // report a typed failure. Surface it as unavailable rather than letting
      // it escape as an unhandled async error.
      debugPrint('requestOtp: gateway unavailable — $error');
      return OtpError.unavailable;
    }
    // A real attempt reached Firebase — count it toward the hourly cap
    // whatever it came back with.
    unawaited(_sendThrottle.recordSend());
    if (failure != null) {
      return failure;
    }

    _pending = _PendingLogin(name: cleanName, phone: cleanPhone);
    return null;
  }

  /// Signs the pending member in when [code] matches. Returns null on success.
  Future<OtpError?> verifyOtp(String code) async {
    final pending = _pending;
    if (pending == null) {
      return OtpError.noPendingRequest;
    }

    final OtpError? failure;
    try {
      failure = await _activeGateway.confirmCode(code.trim());
    } catch (error) {
      debugPrint('verifyOtp: gateway unavailable — $error');
      return OtpError.unavailable;
    }
    if (failure != null) {
      return failure;
    }

    _pending = null;

    // Sign-up carries the name; sign-in does not, so read the returning
    // member's name back from `app.users`, falling back to a neutral
    // placeholder that registration will overwrite.
    var name = pending.name.trim();
    if (name.isEmpty) {
      name = (await MemberRepository.instance.nameByPhone(pending.phone))
              ?.trim() ??
          '';
    }

    final user = AuthUser(
      name: name.isEmpty ? 'Member' : name,
      phone: pending.phone,
    );
    currentUser.value = user;
    _afterSignIn(user);
    return null;
  }

  /// Drops the half-finished sign-in — the member went back to edit details.
  void cancelOtp() {
    _pending = null;
    _gateway?.discard();
  }

  Future<void> logOut() async {
    _pending = null;
    _freshSignIn = null;
    await _gateway?.signOut();
    currentUser.value = null;
  }

  /// Test hook: puts a member straight into the session, skipping the round
  /// trip, so tests of other screens do not have to drive the whole flow.
  @visibleForTesting
  void signInAs({String name = 'Rahul Nair', String phone = '9000000002'}) {
    _pending = null;
    currentUser.value = AuthUser(name: name.trim(), phone: phone.trim());
  }

  /// Test hook: back to a signed-out session with nothing pending and no
  /// gateway. Pair with [useGateway] before driving the sign-in flow.
  @visibleForTesting
  void reset() {
    _pending = null;
    _freshSignIn = null;
    _gateway = null;
    currentUser.value = null;
  }

  /// Test hook: run send/verify against [gateway] — an in-memory fake — so the
  /// flow can be exercised without a live Firebase project.
  @visibleForTesting
  void useGateway(AuthGateway gateway) {
    _gateway = gateway;
  }
}

/// The send/verify half of [AuthService], swapped between the real Firebase
/// implementation and an in-memory stand-in.
abstract class AuthGateway {
  /// Starts verification for an E.164 number (`+91XXXXXXXXXX`). Returns null
  /// once the code is on its way, otherwise the failure.
  Future<OtpError?> sendCode(String e164Phone);

  /// Checks [code] against the last [sendCode]. Returns null when it matches.
  Future<OtpError?> confirmCode(String code);

  /// The member a persisted sign-in restores to, or null when there is no
  /// live session on this device. Called once at launch so a signed-in member
  /// never sees the login screen again until they sign out.
  Future<AuthUser?> restoreUser();

  /// Stores [name] on the persisted session — Firebase Phone Auth keeps the
  /// number but carries no name, so it is written to the user's profile here
  /// and read back by [restoreUser] on the next launch.
  Future<void> saveDisplayName(String name);

  /// Forgets the pending verification without signing out.
  void discard();

  Future<void> signOut();
}

/// Firebase Phone Auth. Holds the `verificationId` from [sendCode] and pairs
/// it with the typed code in [confirmCode].
class FirebaseAuthGateway implements AuthGateway {
  FirebaseAuthGateway({this.onResolved});

  /// Called when Android instant verification or SMS auto-retrieval signs the
  /// member in before a code was ever typed, so [AuthService] can finish the
  /// pending sign-in itself.
  final void Function()? onResolved;

  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;

  String? _verificationId;
  int? _resendToken;

  /// The raw Firebase code from the last [_map]ped failure — see
  /// [AuthService.lastAuthDiagnostic].
  String? _lastDiagnostic;

  String? get lastDiagnostic => _lastDiagnostic;

  /// Web only. `verifyPhoneNumber`'s callback API is unreliable in a browser —
  /// when the reCAPTCHA step fails (most often the deploy origin is not in the
  /// Firebase project's Authorized domains) none of its callbacks fire and the
  /// send just hangs to the client deadline. `signInWithPhoneNumber` runs the
  /// same reCAPTCHA but returns a [fb.ConfirmationResult] and throws a typed
  /// error instead of stalling, so web uses it and keeps the handle here to
  /// pair with the typed code in [confirmCode].
  fb.ConfirmationResult? _webConfirmation;

  /// How long to wait for Firebase to call back before giving up. Covers the
  /// case where the reCAPTCHA fallback web page opens and never resolves, which
  /// otherwise leaves [sendCode] hanging and the "Get OTP" button spinning.
  static const Duration _callbackDeadline = Duration(seconds: 70);

  /// Ceiling on a single verify round trip.
  static const Duration _verifyDeadline = Duration(seconds: 30);

  @override
  Future<OtpError?> sendCode(String e164Phone) async {
    _lastDiagnostic = null;
    if (kIsWeb) {
      return _sendCodeWeb(e164Phone);
    }

    final result = Completer<OtpError?>();

    await _auth.verifyPhoneNumber(
      phoneNumber: e164Phone,
      // The SMS auto-retrieval window once the code is on its way. This does
      // not bound the reCAPTCHA step, so it is not a substitute for the
      // client-side deadline applied to [result] below.
      timeout: const Duration(seconds: 60),
      forceResendingToken: _resendToken,
      verificationCompleted: (credential) async {
        // Android instant validation / auto-retrieval: no code is ever typed,
        // so sign in here and let [AuthService] promote the pending login.
        try {
          await _auth.signInWithCredential(credential);
          _verificationId = null;
          // On pure instant verification `codeSent` never fires — unblock the
          // send call so the flow is not left spinning on "Get OTP".
          if (!result.isCompleted) {
            result.complete(null);
          }
          onResolved?.call();
        } catch (_) {
          // Fall through to the manual code path, which will surface any error.
        }
      },
      verificationFailed: (e) {
        if (!result.isCompleted) {
          result.complete(_map(e));
        }
      },
      codeSent: (verificationId, resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        if (!result.isCompleted) {
          result.complete(null);
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId = verificationId;
        if (!result.isCompleted) {
          result.complete(null);
        }
      },
    );

    // If none of the callbacks above fire — the classic symptom of the
    // reCAPTCHA fallback stalling — stop waiting so the caller can surface a
    // real error instead of an endless spinner.
    return result.future.timeout(
      _callbackDeadline,
      onTimeout: () => OtpError.timeout,
    );
  }

  /// Web send path: [fb.FirebaseAuth.signInWithPhoneNumber] runs the reCAPTCHA
  /// and returns a [fb.ConfirmationResult], throwing a typed
  /// [fb.FirebaseAuthException] on failure rather than leaving the call hanging
  /// the way `verifyPhoneNumber`'s browser callbacks do.
  Future<OtpError?> _sendCodeWeb(String e164Phone) async {
    try {
      _webConfirmation = await _auth
          .signInWithPhoneNumber(e164Phone)
          .timeout(_callbackDeadline);
      return null;
    } on TimeoutException {
      return OtpError.timeout;
    } on fb.FirebaseAuthException catch (e) {
      return _map(e);
    } catch (error) {
      debugPrint('signInWithPhoneNumber (web): $error');
      return OtpError.unknown;
    }
  }

  @override
  Future<OtpError?> confirmCode(String code) async {
    if (kIsWeb) {
      final confirmation = _webConfirmation;
      if (confirmation == null) {
        return OtpError.noPendingRequest;
      }
      try {
        await confirmation.confirm(code).timeout(_verifyDeadline);
        _webConfirmation = null;
        return null;
      } on TimeoutException {
        return OtpError.timeout;
      } on fb.FirebaseAuthException catch (e) {
        return _map(e);
      } catch (_) {
        return OtpError.unknown;
      }
    }

    final verificationId = _verificationId;
    if (verificationId == null) {
      return OtpError.noPendingRequest;
    }
    try {
      final credential = fb.PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );
      await _auth.signInWithCredential(credential).timeout(_verifyDeadline);
      _verificationId = null;
      return null;
    } on TimeoutException {
      return OtpError.timeout;
    } on fb.FirebaseAuthException catch (e) {
      return _map(e);
    } catch (_) {
      return OtpError.unknown;
    }
  }

  @override
  Future<AuthUser?> restoreUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    // Phone Auth stores the number as E.164 (`+91XXXXXXXXXX`); the app keys
    // members on the bare ten digits.
    final e164 = user.phoneNumber ?? '';
    final phone = e164.startsWith('+91')
        ? e164.substring(3)
        : e164.replaceAll(RegExp(r'[^0-9]'), '');
    return AuthUser(name: user.displayName ?? '', phone: phone);
  }

  @override
  Future<void> saveDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null || name.trim().isEmpty || user.displayName == name.trim()) {
      return;
    }
    try {
      await user.updateDisplayName(name.trim());
    } catch (error) {
      // Non-fatal: the name is also written to the members table, and the
      // next launch falls back to that when the profile has no name.
      debugPrint('saveDisplayName: $error');
    }
  }

  @override
  void discard() {
    _verificationId = null;
    _webConfirmation = null;
  }

  @override
  Future<void> signOut() => _auth.signOut();

  OtpError _map(fb.FirebaseAuthException e) {
    // Always surface the raw failure — without this every send/verify error
    // collapses to one vague line and there is no way to tell a billing block
    // from a bad SHA from a real quota hit. Check `flutter run` / `adb logcat`.
    debugPrint(
      'FirebaseAuth: code="${e.code}" message="${e.message}" '
      'plugin="${e.plugin}"',
    );
    _lastDiagnostic = e.code.isEmpty ? null : e.code;
    switch (e.code) {
      case 'invalid-verification-code':
        return OtpError.wrongOtp;
      case 'invalid-phone-number':
        return OtpError.invalidPhone;
      case 'session-expired':
      case 'code-expired':
        return OtpError.codeExpired;
      case 'too-many-requests':
        return OtpError.tooManyRequests;
      case 'quota-exceeded':
        return OtpError.quotaExceeded;
      case 'network-request-failed':
        return OtpError.network;
      case 'captcha-check-failed':
      case 'web-context-cancelled':
      case 'web-context-already-presented':
      case 'missing-app-credential':
      case 'invalid-app-credential':
        // The reCAPTCHA step was shown and failed, was dismissed, or handed
        // back a token Firebase rejected. On a debug Android build this fires
        // when Play Integrity can't vouch for the app; on web it is a failed or
        // abandoned reCAPTCHA. Retrying (Resend) gets a fresh challenge.
        return OtpError.timeout;
      case 'operation-not-allowed':
      case 'billing-not-enabled':
      case 'missing-client-identifier':
      case 'app-not-authorized':
      case 'unauthorized-domain':
      case 'internal-error':
        // Permanent, project-side misconfiguration rather than a transient
        // limit: Phone provider off, project still on the Spark (no-billing)
        // plan, SHA-1/SHA-256 not registered, the API key restricted, or — on
        // web — the page's origin missing from the project's Authorized
        // domains. None of these clear by retrying — see FIREBASE_SETUP.md.
        assert(() {
          debugPrint(
            'FirebaseAuth: "${e.code}" is a console-side misconfiguration. '
            'Phone Auth needs the Blaze plan for real numbers (or a test '
            'number) and the Phone provider enabled. On Android also register '
            "this build's SHA-1/SHA-256 on the shield-zabnix app; on web add "
            'the deploy origin (the Vercel domain) under Authentication → '
            'Settings → Authorized domains.',
          );
          return true;
        }());
        return OtpError.configError;
      default:
        return OtpError.unknown;
    }
  }
}

class _PendingLogin {
  final String name;
  final String phone;

  const _PendingLogin({required this.name, required this.phone});
}
