import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// MSG91 Widget OTP — runs MSG91's own JS widget directly in the page,
/// exactly like shieldweb's `src/lib/msg91Otp.ts` already does, since
/// MSG91's Widget product has no real server-to-server "send": see
/// `backend/api/src/modules/otp/otp.service.ts`'s own doc on why
/// `sendMsg91Otp`/`verifyMsg91Otp` turned out not to be a supported flow at
/// all, and why this (running the widget somewhere with a real browser
/// context) is the actual supported shape.
///
/// Web-only — this file is only ever imported behind a `kIsWeb` check (see
/// `AuthService`/`AgentPhoneVerifier`). Native builds have no browser
/// context and need a WebView-hosted equivalent instead, not yet built.
///
/// `MSG91_WIDGET_ID`/`MSG91_WIDGET_TOKEN_AUTH` are compiled in via
/// `--dart-define`, the same browser-safe values shieldweb's own
/// `VITE_MSG91_WIDGET_ID`/`VITE_MSG91_TOKEN_AUTH` carry — safe to ship in a
/// client bundle by MSG91's own design (`tokenAuth` is the scoped,
/// throttled token made specifically for this).
const String _widgetId = String.fromEnvironment('MSG91_WIDGET_ID');
const String _tokenAuth = String.fromEnvironment('MSG91_WIDGET_TOKEN_AUTH');
const String _scriptUrl = 'https://verify.msg91.com/otp-provider.js';

Future<void>? _scriptLoading;
bool _widgetInitialized = false;

Future<void> _loadScript() {
  return _scriptLoading ??= Future(() async {
    if (web.document.querySelector('script[src="$_scriptUrl"]') != null) {
      return;
    }
    final completer = Completer<void>();
    final script = web.HTMLScriptElement()
      ..src = _scriptUrl
      ..async = true;
    script.onload = (JSAny? _) {
      if (!completer.isCompleted) completer.complete();
    }.toJS;
    script.onerror = (JSAny? _) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Could not load the OTP verification script.'));
      }
    }.toJS;
    web.document.head!.appendChild(script);
    return completer.future;
  });
}

Future<void> _ensureWidget() async {
  if (_widgetId.isEmpty || _tokenAuth.isEmpty) {
    throw StateError(
      'OTP sending is not configured in this build (missing MSG91_WIDGET_ID/MSG91_WIDGET_TOKEN_AUTH).',
    );
  }
  await _loadScript();
  if (!web.window.hasProperty('initSendOTP'.toJS).toDart) {
    throw StateError('The OTP verification script did not load correctly.');
  }
  if (!_widgetInitialized) {
    final config = {
      'widgetId': _widgetId,
      'tokenAuth': _tokenAuth,
      'exposeMethods': true,
      'success': (JSAny? _) {}.toJS,
      'failure': (JSAny? _) {}.toJS,
    }.jsify();
    web.window.callMethod('initSendOTP'.toJS, config);
    _widgetInitialized = true;
  }
}

/// Sends a real SMS OTP to [identifier] — MSG91 format: country-code
/// prefixed digits only (e.g. `919876543210`), no `+`. Throws on failure.
Future<void> sendWidgetOtp(String identifier) async {
  await _ensureWidget();
  final completer = Completer<void>();
  final onSuccess = (JSAny? _) {
    if (!completer.isCompleted) completer.complete();
  }.toJS;
  final onFailure = (JSAny? err) {
    if (!completer.isCompleted) completer.completeError(StateError(_describeJsError(err)));
  }.toJS;
  web.window.callMethod('sendOtp'.toJS, identifier.toJS, onSuccess, onFailure);
  return completer.future;
}

/// Verifies [code] against the last [sendWidgetOtp] call and returns the
/// MSG91 access-token on success — hand this to the backend
/// (`/v1/member/auth/widget/verify`, `/widget/register`, or
/// `/v1/agent/otp/verify-widget`) to actually confirm it server-side; the
/// token alone proves nothing on its own.
Future<String> verifyWidgetOtp(String code) async {
  final completer = Completer<String>();
  final onSuccess = (JSAny? data) {
    if (completer.isCompleted) return;
    final token = _accessTokenFrom(data);
    if (token != null) {
      completer.complete(token);
    } else {
      completer.completeError(StateError('Could not verify that code.'));
    }
  }.toJS;
  final onFailure = (JSAny? err) {
    if (!completer.isCompleted) completer.completeError(StateError(_describeJsError(err)));
  }.toJS;
  web.window.callMethod('verifyOtp'.toJS, code.toJS, onSuccess, onFailure);
  return completer.future;
}

String? _accessTokenFrom(JSAny? data) {
  if (data == null) return null;
  if (data.isA<JSString>()) return (data as JSString).toDart;
  if (data.isA<JSObject>()) {
    final obj = data as JSObject;
    for (final key in ['access-token', 'message', 'token']) {
      if (obj.hasProperty(key.toJS).toDart) {
        final value = obj.getProperty(key.toJS);
        if (value.isA<JSString>()) return (value as JSString).toDart;
      }
    }
  }
  return null;
}

String _describeJsError(JSAny? err) {
  if (err == null) return 'Could not send the code.';
  if (err.isA<JSString>()) return (err as JSString).toDart;
  if (err.isA<JSObject>()) {
    final obj = err as JSObject;
    if (obj.hasProperty('message'.toJS).toDart) {
      final msg = obj.getProperty('message'.toJS);
      if (msg.isA<JSString>()) return (msg as JSString).toDart;
    }
  }
  return 'Could not send the code.';
}
