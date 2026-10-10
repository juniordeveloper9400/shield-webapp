import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/backend/backend_http.dart';
import '../../data/backend/backend_session.dart';
import '../../data/backend/member_repository.dart';
import '../location/address_book.dart';
import '../persona/persona_service.dart';
import '../registration/registration_service.dart';
import '../wallet/wallet_service.dart';
import 'msg91_widget_otp.dart' as widget_otp;
import 'otp_send_throttle.dart';

/// A signed-in member.
///
/// Identity is the mobile number: it is what the code was sent to, and it is
/// what the backend keys the account on. The name is what the member typed on
/// the way in and is only ever used for display.
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

  /// MSG91 (or the backend's own `AuthThrottle`) is rate-limiting this
  /// device or number.
  tooManyRequests,

  /// Unused by the current MSG91-backed transport — kept because the UI
  /// still switches over it. Historical: the app's own on-device cap (four
  /// code requests inside an hour), removed once Firebase's own
  /// `too-many-requests` block turned out harsher and this just piled a
  /// redundant hour-long lock on top of it. See [AuthService.sendCooldownRemaining].
  throttled,

  /// Unused by the current MSG91-backed transport — kept because the UI
  /// still switches over it. Historical: Firebase Phone Auth's project-wide
  /// SMS allowance being used up.
  quotaExceeded,

  /// The send or verify call could not reach the backend.
  network,

  /// The backend call took too long to answer. The flow is abandoned rather
  /// than left spinning forever.
  timeout,

  /// OTP sending/verification is unavailable right now — the backend is
  /// unreachable, or `BACKEND_API_BASE_URL` was not configured at build
  /// time.
  unavailable,

  /// The backend reports MSG91 itself is not configured on the server.
  configError,

  /// Anything the backend reported that does not map to one of the above.
  unknown,
}

/// On web, MSG91's JS widget; everywhere else, the backend-direct calls
/// that currently cannot send a code at all — see [AuthService]'s own doc.
MemberOtpTransport _defaultTransport() => kIsWeb ? WidgetMemberOtpTransport() : BackendMemberOtpTransport();

/// Phone-number sign-in for the member session.
///
/// The flow is two calls — [requestOtp] sends the SMS, [verifyOtp] checks the
/// code — and the same [currentUser] notifier every screen already listens
/// to. The work behind those two calls is delegated to a
/// [MemberOtpTransport], chosen by [_defaultTransport]: on web,
/// [WidgetMemberOtpTransport] (MSG91's JS widget, run in the page — see
/// `msg91_widget_otp.dart`); everywhere else, [BackendMemberOtpTransport]
/// (`backend/api`'s `/v1/member/auth/otp/*`, same backend the root `shield`
/// member app uses) — which currently cannot actually send a code at all,
/// since MSG91's Widget product turned out to have no real server-to-server
/// "send" (see `backend/api/src/modules/otp/otp.service.ts`'s own doc).
/// Native builds need a WebView-hosted widget to fix that; not yet built.
/// There is no demo or offline fallback — a real code is sent and checked.
/// Tests inject an in-memory fake with [useTransport] before driving the
/// flow.
///
/// Because the backend is the *only* way a code is sent or checked, sign-in
/// hard-depends on `BACKEND_API_BASE_URL` being configured and the backend
/// being reachable.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  /// The fixed code [FakeMemberOtpTransport] treats as correct, exposed here
  /// so widget tests can type a known value into the OTP field. No
  /// production path uses this — real sign-in runs real MSG91 verification.
  static const String demoOtp = '1234';

  /// Digits in a code. The OTP field draws this many boxes. Confirmed via a
  /// real MSG91 widget send on the root `shield` app (2026-10-10) — the
  /// widget dashboard's own "OTP Length: 4" setting, same widget this app
  /// shares.
  static const int otpLength = 4;

  /// How long the member waits before a resend is offered.
  static const Duration resendCooldown = Duration(seconds: 30);

  /// Null while signed out. Widgets listen to this to decide what to show.
  final ValueNotifier<AuthUser?> currentUser = ValueNotifier<AuthUser?>(null);

  /// Sends and checks the code. [_defaultTransport] by default (web runs
  /// MSG91's JS widget — see `msg91_widget_otp.dart`; native currently
  /// cannot send a code at all, see that file's own doc on the gap); tests
  /// swap it with [useTransport].
  MemberOtpTransport _transport = _defaultTransport();

  /// The backend's own `reason` string behind the most recent failure, or
  /// null. Shown under the "not set up" line so a support screenshot names
  /// the exact thing to fix.
  String? _lastDiagnostic;

  String? get lastAuthDiagnostic => _lastDiagnostic;

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

  /// The name a member signs in under. A number that already has an account
  /// keeps the name stored on it, whatever was typed on the way in — typing a
  /// different name on the create-account path must not rename an existing
  /// member. Only a number with no stored name takes the typed one (a new
  /// account), then a neutral placeholder that registration will overwrite.
  Future<String> _nameFor(_PendingLogin pending) async {
    final stored = (await _nameByPhone(pending.phone))?.trim() ?? '';
    if (stored.isNotEmpty) {
      return stored;
    }
    final typed = pending.name.trim();
    return typed.isEmpty ? 'Member' : typed;
  }

  /// Persists the freshly signed-in user, then re-runs the persona/
  /// registration/wallet/address reloads every screen in this app depends
  /// on — the backend session is already live by the time this runs (see
  /// [verifyOtp]), so this replaces what `_bridgeToBackend`'s success branch
  /// used to do, not just the Neon-direct bookkeeping below it.
  void _afterSignIn(AuthUser user) {
    _freshSignIn = user;
    // Signed in — clear the hourly send cap so a later sign-in starts fresh.
    _sendCooldownRemaining = null;
    unawaited(_sendThrottle.reset());
    unawaited(
      MemberRepository.instance.upsertOnSignIn(
        name: user.name,
        phone: user.phone,
      ),
    );
    unawaited(PersonaService.instance.reload(user.phone));
    unawaited(RegistrationService.instance.loadForSignedInMember(user.phone));
    unawaited(WalletService.instance.refreshFromDatabase(user.phone));
    unawaited(AddressBook.instance.refreshFromDatabase());
  }

  /// Restores a persisted sign-in at launch, so a member who has signed in
  /// once goes straight into the app without seeing the login screen again.
  ///
  /// Unlike the old Firebase version — which asked Firebase's own on-device
  /// `currentUser` for this — there is no local identity left to ask: the
  /// durable thing this now restores from is `BackendSession`'s persisted
  /// refresh token. Once that is live again, `GET /v1/member/me` supplies
  /// the name and phone to restore — see `MemberRepository.currentProfile`.
  ///
  /// Call from `main()` at launch. A no-op when already signed in, when
  /// there is no persisted backend session on this device, or when the
  /// backend is unreachable right now.
  Future<void> restoreSession() async {
    if (isSignedIn) {
      return;
    }

    bool restored;
    try {
      restored = await BackendSession.instance.restore();
    } catch (error) {
      debugPrint('restoreSession: backend unavailable — $error');
      return;
    }
    if (!restored) {
      return;
    }

    final profile = await MemberRepository.instance.currentProfile();
    if (profile == null) {
      // The session token itself was valid, but the profile fetch failed or
      // the account is gone — never show a signed-in shell with no member
      // behind it.
      await BackendSession.instance.signOut();
      return;
    }

    var name = profile.name.trim();
    if (name.isEmpty) {
      name = (await MemberRepository.instance.nameByPhone(profile.phone))
              ?.trim() ??
          '';
    }

    final user = AuthUser(
      name: name.isEmpty ? 'Member' : name,
      phone: profile.phone,
    );
    currentUser.value = user;
    unawaited(MemberRepository.instance.touchLogin(profile.phone));
    // Same re-check _afterSignIn's own doc describes: a restored session
    // needs the exact same persona/registration/wallet/address reload a
    // freshly completed sign-in gets, since nothing else triggers it here.
    unawaited(PersonaService.instance.reload(profile.phone));
    unawaited(RegistrationService.instance.loadForSignedInMember(profile.phone));
    unawaited(WalletService.instance.refreshFromDatabase(profile.phone));
    unawaited(AddressBook.instance.refreshFromDatabase());
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

  /// Whether [phone] already has an account — an `app.users` row, meaning the
  /// number has signed in before. `true` / `false` when the database answered,
  /// `null` when it could not be reached (the caller should let the sign-in
  /// through rather than block a member on a network blip).
  ///
  /// The login screen uses this to send an unknown number to "Create account"
  /// instead of firing an OTP at a number with no account.
  Future<bool?> hasAccount(String phone) => _phoneExists(phone.trim());

  Future<bool?> Function(String phone) _phoneExists =
      MemberRepository.instance.phoneExists;
  Future<String?> Function(String phone) _nameByPhone =
      MemberRepository.instance.nameByPhone;

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

    // The device-side cap is gone (see [OtpSendThrottle]); this call only
    // clears anything an older build left stored so an updated app recovers.
    await _sendThrottle.blockedFor();

    _lastDiagnostic = null;
    final result = await _transport.sendCode(cleanPhone);
    if (!result.ok) {
      _lastDiagnostic = result.diagnostic;
      return result.failure;
    }

    _pending = _PendingLogin(name: cleanName, phone: cleanPhone);
    return null;
  }

  /// Signs the pending member in when [code] matches. Returns null on
  /// success. Picks sign-in vs. registration on the backend by whether
  /// [_pending] carries a typed name — the same split [requestOtp]'s caller
  /// already made via [hasAccount] before ever sending a code.
  Future<OtpError?> verifyOtp(String code) async {
    final pending = _pending;
    if (pending == null) {
      return OtpError.noPendingRequest;
    }

    final result = await _transport.confirmCode(
      pending.phone,
      code.trim(),
      name: pending.name.isEmpty ? null : pending.name,
    );
    if (!result.ok) {
      _lastDiagnostic = result.diagnostic;
      return result.failure;
    }

    _pending = null;

    final user = AuthUser(
      name: await _nameFor(pending),
      phone: pending.phone,
    );
    currentUser.value = user;
    _afterSignIn(user);
    return null;
  }

  /// Drops the half-finished sign-in — the member went back to edit details.
  void cancelOtp() {
    _pending = null;
  }

  Future<void> logOut() async {
    _pending = null;
    _freshSignIn = null;
    await BackendSession.instance.signOut();
    currentUser.value = null;
    // Otherwise this member's registration details would still be sitting in
    // memory — and visible on the register bar — for whichever account (or
    // none) signs in next on this device.
    RegistrationService.instance.clearForSignOut();
    // Same reason: without this the next member signed in on this device
    // would open the wallet screen to the previous member's balance and
    // ledger for the instant before refreshFromDatabase's next call lands.
    WalletService.instance.reset();
    AddressBook.instance.reset();
  }

  /// Permanently deletes the signed-in member's account and ends the
  /// session — see [MemberRepository.deleteAccount] for exactly what gets
  /// cleared (soft-deleted, not a row wiped out from under their order
  /// history). A no-op when nobody is signed in.
  ///
  /// There is no separate remote identity left to delete the way the old
  /// Firebase version had to — a phone number verified through MSG91 leaves
  /// nothing behind to clean up beyond the backend session, which
  /// [MemberRepository.deleteAccount] already revokes server-side; this
  /// still ends the local session the same way [logOut] does.
  Future<void> deleteAccount() async {
    final user = currentUser.value;
    if (user == null) {
      return;
    }
    await MemberRepository.instance.deleteAccount(user.phone);
    await BackendSession.instance.signOut();
    _pending = null;
    _freshSignIn = null;
    currentUser.value = null;
    RegistrationService.instance.clearForSignOut();
    WalletService.instance.reset();
    AddressBook.instance.reset();
  }

  /// Test hook: puts a member straight into the session, skipping the round
  /// trip, so tests of other screens do not have to drive the whole flow.
  @visibleForTesting
  void signInAs({String name = 'Rahul Nair', String phone = '9000000002'}) {
    _pending = null;
    currentUser.value = AuthUser(name: name.trim(), phone: phone.trim());
  }

  /// Test hook: back to a signed-out session with nothing pending and the
  /// real backend transport restored. Pair with [useTransport] before
  /// driving the sign-in flow.
  @visibleForTesting
  void reset() {
    _pending = null;
    _freshSignIn = null;
    _transport = _defaultTransport();
    _lastDiagnostic = null;
    _phoneExists = MemberRepository.instance.phoneExists;
    _nameByPhone = MemberRepository.instance.nameByPhone;
    currentUser.value = null;
  }

  /// Test hook: answer "has this number an account" and "what name is stored
  /// on it" from memory instead of the members table.
  @visibleForTesting
  void useMemberLookup({
    required Future<bool?> Function(String phone) phoneExists,
    required Future<String?> Function(String phone) nameByPhone,
  }) {
    _phoneExists = phoneExists;
    _nameByPhone = nameByPhone;
  }

  /// Test hook: run send/verify against [transport] — an in-memory fake —
  /// so the flow can be exercised without a live backend.
  @visibleForTesting
  void useTransport(MemberOtpTransport transport) {
    _transport = transport;
  }
}

/// A send or confirm attempt's outcome: [ok] true on success, otherwise the
/// [failure] category plus the backend's own [diagnostic] reason string to
/// show alongside it.
@immutable
class MemberOtpOutcome {
  final bool ok;
  final OtpError? failure;
  final String? diagnostic;

  const MemberOtpOutcome.success() : ok = true, failure = null, diagnostic = null;

  const MemberOtpOutcome.failed(this.failure, [this.diagnostic]) : ok = false;
}

/// The send/verify half of [AuthService], swapped between the real
/// backend-calling implementation and an in-memory stand-in for tests.
abstract class MemberOtpTransport {
  /// Starts verification for a bare 10-digit number. Returns null once the
  /// code is on its way, otherwise the failure.
  Future<MemberOtpOutcome> sendCode(String phone);

  /// Checks [code] against the last [sendCode] for [phone]. [name] is
  /// non-null only on the sign-up path — see [AuthService.verifyOtp]'s own
  /// doc on why that alone is enough to pick sign-in vs. registration.
  Future<MemberOtpOutcome> confirmCode(String phone, String code, {String? name});
}

/// Calls `backend/api`'s MSG91-backed `/v1/member/auth/otp/*` endpoints —
/// the same ones the root `shield` member app uses (see that app's
/// `backend/api/src/modules/auth/auth.service.ts`). On a successful
/// [confirmCode], the backend has already minted a session in the same
/// call — this adopts it into [BackendSession] directly.
class BackendMemberOtpTransport implements MemberOtpTransport {
  BackendMemberOtpTransport({BackendHttp? http}) : _http = http ?? BackendHttp.instance;

  final BackendHttp _http;

  @override
  Future<MemberOtpOutcome> sendCode(String phone) async {
    if (!_http.isEnabled) {
      return const MemberOtpOutcome.failed(OtpError.unavailable);
    }
    try {
      final result = await _http.request(
        'POST',
        '/v1/member/auth/otp/send',
        body: {'phone': phone},
        auth: false,
      ) as Map<String, dynamic>;
      if (result['ok'] == true) {
        return const MemberOtpOutcome.success();
      }
      return MemberOtpOutcome.failed(OtpError.configError, result['reason'] as String?);
    } on BackendHttpException catch (error) {
      BackendHttp.log('AuthService.requestOtp failed', error: error);
      return MemberOtpOutcome.failed(
        error.isTooManyRequests ? OtpError.tooManyRequests : OtpError.network,
      );
    } catch (error) {
      BackendHttp.log('AuthService.requestOtp failed', error: error);
      return const MemberOtpOutcome.failed(OtpError.network);
    }
  }

  @override
  Future<MemberOtpOutcome> confirmCode(String phone, String code, {String? name}) async {
    if (!_http.isEnabled) {
      return const MemberOtpOutcome.failed(OtpError.unavailable);
    }
    try {
      final Map<String, dynamic> result;
      if (name == null) {
        result = await _http.request(
          'POST',
          '/v1/member/auth/otp/verify',
          body: {'phone': phone, 'code': code},
          auth: false,
        ) as Map<String, dynamic>;
      } else {
        result = await _http.request(
          'POST',
          '/v1/member/auth/otp/register',
          body: {'phone': phone, 'code': code, 'name': name},
          auth: false,
        ) as Map<String, dynamic>;
      }
      final accessToken = result['accessToken'] as String?;
      final refreshToken = result['refreshToken'] as String?;
      if (accessToken == null || refreshToken == null) {
        return const MemberOtpOutcome.failed(OtpError.unknown);
      }
      await BackendSession.instance.setTokens(accessToken: accessToken, refreshToken: refreshToken);
      return const MemberOtpOutcome.success();
    } on BackendHttpException catch (error) {
      BackendHttp.log('AuthService.verifyOtp failed', error: error);
      if (error.isTooManyRequests) {
        return const MemberOtpOutcome.failed(OtpError.tooManyRequests);
      }
      if (error.isNotFound) {
        return const MemberOtpOutcome.failed(
          OtpError.unknown,
          'This number is not registered yet — go back and create an account.',
        );
      }
      return MemberOtpOutcome.failed(OtpError.wrongOtp, error.message);
    } catch (error) {
      BackendHttp.log('AuthService.verifyOtp failed', error: error);
      return const MemberOtpOutcome.failed(OtpError.network);
    }
  }
}

/// Runs MSG91's own JS widget (web only — see `msg91_widget_otp.dart`'s own
/// doc on the native gap) to send/verify the code, then has the backend
/// confirm the resulting access-token server-side
/// (`/v1/member/auth/widget/verify`/`/widget/register`) before treating it
/// as a real sign-in — the token alone, client-side, proves nothing. Used
/// instead of [BackendMemberOtpTransport] because MSG91's Widget product
/// has no real server-to-server "send": see
/// `backend/api/src/modules/otp/otp.service.ts`'s own doc on why
/// `sendMsg91Otp`/`verifyMsg91Otp` (what [BackendMemberOtpTransport] calls)
/// turned out not to be a supported flow at all.
class WidgetMemberOtpTransport implements MemberOtpTransport {
  WidgetMemberOtpTransport({BackendHttp? http}) : _http = http ?? BackendHttp.instance;

  final BackendHttp _http;

  /// MSG91 identifiers are plain digits, country-code-prefixed, no `+`.
  String _identifierFor(String phone) => '91$phone';

  @override
  Future<MemberOtpOutcome> sendCode(String phone) async {
    try {
      await widget_otp.sendWidgetOtp(_identifierFor(phone));
      return const MemberOtpOutcome.success();
    } on UnsupportedError catch (error) {
      BackendHttp.log('AuthService.requestOtp (widget) failed', error: error);
      return const MemberOtpOutcome.failed(OtpError.unavailable);
    } catch (error) {
      BackendHttp.log('AuthService.requestOtp (widget) failed', error: error);
      return MemberOtpOutcome.failed(OtpError.unknown, error is StateError ? error.message : null);
    }
  }

  @override
  Future<MemberOtpOutcome> confirmCode(String phone, String code, {String? name}) async {
    final String accessToken;
    try {
      accessToken = await widget_otp.verifyWidgetOtp(code);
    } on UnsupportedError catch (error) {
      BackendHttp.log('AuthService.verifyOtp (widget) failed', error: error);
      return const MemberOtpOutcome.failed(OtpError.unavailable);
    } catch (error) {
      BackendHttp.log('AuthService.verifyOtp (widget) failed', error: error);
      return MemberOtpOutcome.failed(OtpError.wrongOtp, error is StateError ? error.message : null);
    }

    if (!_http.isEnabled) {
      return const MemberOtpOutcome.failed(OtpError.unavailable);
    }
    try {
      final Map<String, dynamic> result;
      if (name == null) {
        result = await _http.request(
          'POST',
          '/v1/member/auth/widget/verify',
          body: {'phone': phone, 'accessToken': accessToken},
          auth: false,
        ) as Map<String, dynamic>;
      } else {
        result = await _http.request(
          'POST',
          '/v1/member/auth/widget/register',
          body: {'phone': phone, 'accessToken': accessToken, 'name': name},
          auth: false,
        ) as Map<String, dynamic>;
      }
      final newAccessToken = result['accessToken'] as String?;
      final refreshToken = result['refreshToken'] as String?;
      if (newAccessToken == null || refreshToken == null) {
        return const MemberOtpOutcome.failed(OtpError.unknown);
      }
      await BackendSession.instance.setTokens(accessToken: newAccessToken, refreshToken: refreshToken);
      return const MemberOtpOutcome.success();
    } on BackendHttpException catch (error) {
      BackendHttp.log('AuthService.verifyOtp (widget) failed', error: error);
      if (error.isTooManyRequests) {
        return const MemberOtpOutcome.failed(OtpError.tooManyRequests);
      }
      if (error.isNotFound) {
        return const MemberOtpOutcome.failed(
          OtpError.unknown,
          'This number is not registered yet — go back and create an account.',
        );
      }
      return MemberOtpOutcome.failed(OtpError.wrongOtp, error.message);
    } catch (error) {
      BackendHttp.log('AuthService.verifyOtp (widget) failed', error: error);
      return const MemberOtpOutcome.failed(OtpError.network);
    }
  }
}

class _PendingLogin {
  final String name;
  final String phone;

  const _PendingLogin({required this.name, required this.phone});
}
