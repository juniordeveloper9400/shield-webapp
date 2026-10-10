import 'package:flutter/foundation.dart';

import '../../data/backend/backend_http.dart';
import '../auth/auth_service.dart' show OtpError;

/// Proves the agent-registration form's recruit owns the phone number they
/// gave, via `backend/api`'s MSG91-backed `/v1/agent/otp/*` endpoints
/// (member-authenticated — the recruiting member's own session carries the
/// call, same as the root `shield` app's own `AgentPhoneVerifier`) — never
/// signs anyone in.
///
/// Delegates the actual network calls to an [AgentOtpTransport] so tests can
/// inject fakes with [useTransport] instead of a live backend.
class AgentOtpVerifier {
  AgentOtpVerifier._();

  static final AgentOtpVerifier instance = AgentOtpVerifier._();

  /// Test hook — a fake the agent-registration screen uses in place of the
  /// real backend round trip.
  @visibleForTesting
  static AgentOtpVerifier? debugOverride;

  static AgentOtpVerifier get current => debugOverride ?? instance;

  AgentOtpTransport _transport = BackendAgentOtpTransport();

  bool _pending = false;
  String? _phone;

  /// Test hook: run send/confirm against [transport] — an in-memory fake —
  /// instead of the real backend.
  @visibleForTesting
  void useTransport(AgentOtpTransport transport) {
    _transport = transport;
  }

  /// Sends a code to [e164Phone] (`+91XXXXXXXXXX`). Null once it is on its
  /// way, otherwise the reason it did not go.
  Future<OtpError?> sendCode(String e164Phone) async {
    final result = await _transport.sendCode(e164Phone);
    if (result.failure == null) {
      _phone = e164Phone;
      _pending = true;
    }
    return result.failure;
  }

  /// Checks [code] against the last [sendCode]. Null on success — the number
  /// is proven and no session is left behind.
  Future<OtpError?> confirmCode(String code) async {
    final phone = _phone;
    if (!_pending || phone == null) {
      return OtpError.noPendingRequest;
    }
    final result = await _transport.confirmCode(phone, code.trim());
    if (result.failure == null) {
      _pending = false;
      _phone = null;
    }
    return result.failure;
  }

  /// Forget the pending verification (recruiter went back to edit the number).
  void discard() {
    _pending = false;
    _phone = null;
  }

  /// Test hook: forget any injected transport and pending state.
  @visibleForTesting
  void reset() {
    _transport = BackendAgentOtpTransport();
    _pending = false;
    _phone = null;
  }
}

/// A send or confirm attempt's outcome: null [failure] on success.
@immutable
class AgentOtpOutcome {
  final OtpError? failure;

  const AgentOtpOutcome.success() : failure = null;

  const AgentOtpOutcome.failed(this.failure);
}

/// The send/verify half of [AgentOtpVerifier], swapped between the real
/// backend call and an in-memory stand-in for tests.
abstract class AgentOtpTransport {
  Future<AgentOtpOutcome> sendCode(String e164Phone);
  Future<AgentOtpOutcome> confirmCode(String e164Phone, String code);
}

/// Calls `backend/api`'s `/v1/agent/otp/send-msg91` and `/verify-msg91` —
/// the same endpoints the root `shield` app's own `AgentPhoneVerifier` uses.
class BackendAgentOtpTransport implements AgentOtpTransport {
  BackendAgentOtpTransport({BackendHttp? http}) : _http = http ?? BackendHttp.instance;

  final BackendHttp _http;

  @override
  Future<AgentOtpOutcome> sendCode(String e164Phone) async {
    if (!_http.isEnabled) {
      return const AgentOtpOutcome.failed(OtpError.unavailable);
    }
    try {
      final result = await _http.request(
        'POST',
        '/v1/agent/otp/send-msg91',
        body: {'phone': e164Phone},
      ) as Map<String, dynamic>;
      if (result['ok'] == true) {
        return const AgentOtpOutcome.success();
      }
      return const AgentOtpOutcome.failed(OtpError.configError);
    } on BackendHttpException catch (error) {
      BackendHttp.log('AgentOtpVerifier.sendCode failed', error: error);
      return AgentOtpOutcome.failed(
        error.isTooManyRequests ? OtpError.tooManyRequests : OtpError.network,
      );
    } catch (error) {
      BackendHttp.log('AgentOtpVerifier.sendCode failed', error: error);
      return const AgentOtpOutcome.failed(OtpError.network);
    }
  }

  @override
  Future<AgentOtpOutcome> confirmCode(String e164Phone, String code) async {
    if (!_http.isEnabled) {
      return const AgentOtpOutcome.failed(OtpError.unavailable);
    }
    try {
      final result = await _http.request(
        'POST',
        '/v1/agent/otp/verify-msg91',
        body: {'phone': e164Phone, 'code': code},
      ) as Map<String, dynamic>;
      if (result['ok'] == true) {
        return const AgentOtpOutcome.success();
      }
      return const AgentOtpOutcome.failed(OtpError.wrongOtp);
    } on BackendHttpException catch (error) {
      BackendHttp.log('AgentOtpVerifier.confirmCode failed', error: error);
      return AgentOtpOutcome.failed(
        error.isTooManyRequests ? OtpError.tooManyRequests : OtpError.network,
      );
    } catch (error) {
      BackendHttp.log('AgentOtpVerifier.confirmCode failed', error: error);
      return const AgentOtpOutcome.failed(OtpError.network);
    }
  }
}
