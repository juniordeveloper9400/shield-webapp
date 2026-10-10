import 'package:shield/module/auth/auth_service.dart';

/// In-memory stand-in for [BackendMemberOtpTransport] so tests can drive
/// the member sign-in/registration flow without a live backend.
///
/// Inject it in `setUp` with
/// `AuthService.instance.useTransport(FakeMemberOtpTransport())`, then
/// verify with [FakeMemberOtpTransport.code].
class FakeMemberOtpTransport implements MemberOtpTransport {
  FakeMemberOtpTransport({this.acceptedCode = code});

  /// The one code [confirmCode] treats as correct.
  static const String code = '123456';

  final String acceptedCode;
  bool _sent = false;

  /// How many codes [sendCode] has been asked to send.
  int codesSent = 0;

  @override
  Future<MemberOtpOutcome> sendCode(String phone) async {
    _sent = true;
    codesSent++;
    return const MemberOtpOutcome.success();
  }

  @override
  Future<MemberOtpOutcome> confirmCode(String phone, String otp, {String? name}) async {
    if (!_sent) {
      return const MemberOtpOutcome.failed(OtpError.noPendingRequest);
    }
    return otp == acceptedCode
        ? const MemberOtpOutcome.success()
        : const MemberOtpOutcome.failed(OtpError.wrongOtp);
  }
}
