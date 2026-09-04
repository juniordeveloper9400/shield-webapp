import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../widgets/labelled_field.dart';
import 'auth_service.dart';
import 'auth_widgets.dart';
import 'otp_field.dart';

/// Which half of the flow is on screen.
enum _Step { details, otp }

/// Sign in (returning member — number only) or create account (new member —
/// name + number). Both finish with the same one-time code step.
enum _Mode {
  signIn('Sign in', 'Sign in to SHIELD',
      'Enter your registered mobile number and we will send a one-time code.'),
  signUp('Create account', 'Create your SHIELD account',
      'Tell us your name and mobile number — we verify the number with a '
          'one-time code.');

  const _Mode(this.tab, this.title, this.subtitle);

  final String tab;
  final String title;
  final String subtitle;
}

/// The auth gate: a Sign in / Create account switch over a mobile number (and,
/// for a new member, a name), then a one-time code.
///
/// One screen rather than separate routes — the code step replaces the details
/// in place, so the member only ever sees the one thing being asked of them
/// next.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _otpFocus = FocusNode();

  _Step _step = _Step.details;

  /// Opens on Sign in — most people reaching this screen already have an
  /// account. A new member switches to Create account from the link below.
  _Mode _mode = _Mode.signIn;

  /// A send or verify round trip is in flight — blocks the buttons and a
  /// re-entrant submit from the keyboard's "done" action or an autofilled code.
  bool _busy = false;

  /// A resend is in flight — kept apart from [_busy] so it can show its own
  /// "Sending…" state on the link without disabling the whole code step.
  bool _resending = false;
  String? _error;

  Timer? _cooldown;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    // The number field appears the moment the name is usable, so both fields
    // have to rebuild this screen as they are typed into.
    _name.addListener(_repaint);
    _phone.addListener(_repaint);
    _otp.addListener(_clearErrorOnEdit);
    // Android instant verification / SMS auto-retrieval can complete the
    // sign-in without a code ever being typed. RootScreen swaps this screen
    // out when that happens; drop the keyboard first so it does not linger
    // over the next screen.
    AuthService.instance.currentUser.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    AuthService.instance.currentUser.removeListener(_onSessionChanged);
    _name
      ..removeListener(_repaint)
      ..dispose();
    _phone
      ..removeListener(_repaint)
      ..dispose();
    _otp
      ..removeListener(_clearErrorOnEdit)
      ..dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (AuthService.instance.isSignedIn) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _repaint() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Editing a rejected code takes the boxes out of the error state.
  void _clearErrorOnEdit() {
    if (_error != null && mounted) {
      setState(() => _error = null);
    }
  }

  bool get _nameReady => AuthService.validateName(_name.text) == null;

  bool get _phoneReady => AuthService.validatePhone(_phone.text) == null;

  bool get _needsName => _mode == _Mode.signUp;

  /// The name to send with the OTP request: the typed name when creating an
  /// account, `null` on sign-in (the name is read back from `app.users`).
  String? get _nameArg => _needsName ? _name.text : null;

  bool get _canSubmit => _phoneReady && (!_needsName || _nameReady);

  void _switchMode(_Mode mode) {
    if (_busy || _mode == mode) {
      return;
    }
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  // ---- Actions ----

  Future<void> _sendOtp() async {
    if (_busy) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final failure = await AuthService.instance.requestOtp(
      name: _nameArg,
      phone: _phone.text,
    );
    if (!mounted) {
      return;
    }
    if (failure != null) {
      setState(() {
        _busy = false;
        _error = _sendErrorText(failure);
      });
      return;
    }

    _otp.clear();
    setState(() {
      _busy = false;
      _step = _Step.otp;
      _error = null;
    });
    _startCooldown();
    _announceCode();
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending || _busy) {
      return;
    }
    setState(() {
      _resending = true;
      _error = null;
    });

    final failure = await AuthService.instance.requestOtp(
      name: _nameArg,
      phone: _phone.text,
    );
    if (!mounted) {
      return;
    }
    if (failure != null) {
      setState(() {
        _resending = false;
        _error = _sendErrorText(failure);
      });
      return;
    }
    _otp.clear();
    setState(() {
      _resending = false;
      _error = null;
    });
    _otpFocus.requestFocus();
    _startCooldown();
    _announceCode();
  }

  /// Turns a send-time [OtpError] into a line for the form.
  String _sendErrorText(OtpError failure) {
    switch (failure) {
      case OtpError.invalidName:
      case OtpError.invalidPhone:
        return 'Could not send the code. Check your details.';
      case OtpError.tooManyRequests:
        return 'Too many attempts from this device. Try again later.';
      case OtpError.quotaExceeded:
        return 'Verification is temporarily unavailable. Try again later.';
      case OtpError.configError:
        return 'SMS verification is not set up for this app yet. '
            'Please contact support.${_diagnosticSuffix()}';
      case OtpError.network:
        return 'No connection. Check your network and try again.';
      case OtpError.timeout:
        return 'Verification timed out before the code was sent. '
            'Check your connection and tap Resend.${_diagnosticSuffix()}';
      case OtpError.unavailable:
        return 'Verification is unavailable on this device right now.';
      case OtpError.noPendingRequest:
      case OtpError.wrongOtp:
      case OtpError.codeExpired:
      case OtpError.unknown:
        return 'Could not send the code. Please try again.${_diagnosticSuffix()}';
    }
  }

  /// The raw Firebase code, appended in parentheses when there is one — turns
  /// a support screenshot into a precise pointer at the console setting to fix
  /// (`unauthorized-domain`, `operation-not-allowed`, `billing-not-enabled`…).
  String _diagnosticSuffix() {
    final code = AuthService.instance.lastAuthDiagnostic;
    return code == null || code.isEmpty ? '' : '\n($code)';
  }

  Future<void> _verify([String? completed]) async {
    // Guard against a second entry: a filled field fires onCompleted while the
    // member may also tap "Verify & continue", and an autofilled code can land
    // mid-request.
    if (_busy) {
      return;
    }
    final code = completed ?? _otp.text;
    if (code.length < AuthService.otpLength) {
      setState(() => _error = 'Enter the ${AuthService.otpLength}-digit code');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    var failure = await AuthService.instance.verifyOtp(code);
    if (!mounted) {
      return;
    }
    // Android instant verification can complete the sign-in from its own
    // callback while this manual verify is in flight — then verifyOtp reports
    // "no pending request" even though the member is in. Treat being signed in
    // as success and let the tail below finish the flow.
    if (failure != null && AuthService.instance.isSignedIn) {
      failure = null;
    }
    if (failure == OtpError.wrongOtp) {
      _otp.clear();
      setState(() {
        _busy = false;
        _error = 'That code is incorrect. Check the SMS and try again.';
      });
      // Put the keyboard back so the member can retype straight away.
      _otpFocus.requestFocus();
      return;
    }
    if (failure == OtpError.tooManyRequests) {
      setState(() {
        _busy = false;
        _error = 'Too many attempts. Wait a while before trying again.';
      });
      return;
    }
    if (failure == OtpError.network) {
      setState(() {
        _busy = false;
        _error = 'No connection. Check your network and try again.';
      });
      return;
    }
    if (failure == OtpError.timeout) {
      setState(() {
        _busy = false;
        _error = 'Verification timed out. Check your connection and try again.';
      });
      return;
    }
    if (failure == OtpError.unavailable) {
      setState(() {
        _busy = false;
        _error = 'Verification is unavailable on this device right now.';
      });
      return;
    }
    if (failure == OtpError.noPendingRequest || failure == OtpError.codeExpired) {
      // The verification session is gone — start over rather than retry blindly.
      setState(() {
        _busy = false;
        _step = _Step.details;
        _error = 'That code expired. Request a new one.';
      });
      return;
    }
    if (failure != null) {
      setState(() {
        _busy = false;
        _error = 'Could not verify the code. Please try again.';
      });
      return;
    }

    _cooldown?.cancel();
    setState(() => _busy = false);
    // The sent-code notice is stale the moment the code is accepted, and
    // leaving it up would hold back whatever the next screen has to say.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    // Signed in. As the launch gate this screen is the whole route and the
    // session change swaps it out; pushed over the app, it pops itself.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(true);
    }
  }

  void _backToDetails() {
    AuthService.instance.cancelOtp();
    _cooldown?.cancel();
    _otp.clear();
    setState(() {
      _step = _Step.details;
      _error = null;
      _secondsLeft = 0;
    });
  }

  void _startCooldown() {
    _cooldown?.cancel();
    setState(() => _secondsLeft = AuthService.resendCooldown.inSeconds);
    _cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
      }
    });
  }

  /// Confirms the SMS is on its way.
  void _announceCode() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text('OTP sent to +91 ${_phone.text}'),
        ),
      );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back on the code step returns to the details rather than leaving.
      canPop: _step == _Step.details,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _backToDetails();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AuthBrandMark(),
                    const SizedBox(height: 26),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _step == _Step.details
                          ? _buildDetails()
                          : _buildOtp(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetails() {
    return Column(
      key: const ValueKey(_Step.details),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeSwitch(mode: _mode, onChanged: _switchMode),
        const SizedBox(height: 22),
        AuthHeading(title: _mode.title, subtitle: _mode.subtitle),
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Only on the create-account path. Kept out of the tree entirely
              // on sign-in so the Form has nothing to validate but the number.
              if (_needsName) ...[
                LabelledField(
                  label: 'Full name',
                  hint: 'Enter your name',
                  controller: _name,
                  icon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [LengthLimitingTextInputFormatter(40)],
                  validator: AuthService.validateName,
                ),
                const SizedBox(height: 14),
              ],
              LabelledField(
                label: 'Mobile number',
                hint: '10-digit mobile number',
                controller: _phone,
                icon: Icons.phone_iphone_rounded,
                prefixText: '+91  ',
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: AuthService.validatePhone,
                onSubmitted: _canSubmit ? _sendOtp : null,
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          AuthErrorNote(message: _error!),
        ],
        const SizedBox(height: 20),
        AuthButton(
          label: 'Get OTP',
          busy: _busy,
          onPressed: _canSubmit ? _sendOtp : null,
        ),
        const SizedBox(height: 14),
        _ModeSwitchLink(mode: _mode, onSwitch: _switchMode),
        const SizedBox(height: 12),
        const Text(
          'By continuing you agree to the Terms of Use and Privacy Policy.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildOtp() {
    return Column(
      key: const ValueKey(_Step.otp),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthHeading(
          title: 'Verify your number',
          subtitle:
              'Enter the ${AuthService.otpLength}-digit code sent to '
              '+91 ${_phone.text}.',
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _backToDetails,
            icon: const Icon(Icons.arrow_back_rounded, size: 17),
            label: const Text('Change details'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brandBlue,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        OtpField(
          controller: _otp,
          focusNode: _otpFocus,
          length: AuthService.otpLength,
          hasError: _error != null,
          onCompleted: _verify,
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          AuthErrorNote(message: _error!),
        ],
        const SizedBox(height: 14),
        _ResendRow(
          secondsLeft: _secondsLeft,
          busy: _resending,
          onResend: _resend,
        ),
        const SizedBox(height: 18),
        AuthButton(label: 'Verify & continue', busy: _busy, onPressed: _verify),
      ],
    );
  }
}

/// The Sign in / Create account segmented switch at the top of the details
/// step.
class _ModeSwitch extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onChanged;

  const _ModeSwitch({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.pageTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final m in _Mode.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: m == mode ? AppColors.white : AppColors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: m == mode
                        ? [
                            BoxShadow(
                              color: AppColors.textDark.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    m.tab,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: m == mode
                          ? AppColors.brandBlue
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The "New to SHIELD? Create an account" / "Already have an account? Sign in"
/// line under the button.
class _ModeSwitchLink extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onSwitch;

  const _ModeSwitchLink({required this.mode, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    final toSignUp = mode == _Mode.signIn;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          toSignUp ? 'New to SHIELD?' : 'Already have an account?',
          style: const TextStyle(fontSize: 13.5, color: AppColors.textBody),
        ),
        TextButton(
          onPressed: () =>
              onSwitch(toSignUp ? _Mode.signUp : _Mode.signIn),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            toSignUp ? 'Create an account' : 'Sign in',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.brandBlue,
            ),
          ),
        ),
      ],
    );
  }
}

/// Countdown, then a live resend link — or a "Sending…" note while a resend
/// is in flight.
class _ResendRow extends StatelessWidget {
  final int secondsLeft;
  final bool busy;
  final VoidCallback onResend;

  const _ResendRow({
    required this.secondsLeft,
    required this.busy,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Text(
        'Sending a new code…',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      );
    }

    if (secondsLeft > 0) {
      final seconds = secondsLeft.toString().padLeft(2, '0');
      return Text(
        'Resend code in 0:$seconds',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      );
    }

    // Wrap, not Row: at a large text scale the prompt and the link stack
    // instead of running off the edge.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Did not get the code?',
          style: TextStyle(fontSize: 13.5, color: AppColors.textBody),
        ),
        TextButton(
          onPressed: onResend,
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Resend OTP',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.brandBlue,
            ),
          ),
        ),
      ],
    );
  }
}
