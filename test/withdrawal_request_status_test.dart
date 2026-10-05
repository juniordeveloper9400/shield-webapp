import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/agent/agent_model.dart';

WithdrawalRequest _request(WithdrawalStatus status) => WithdrawalRequest(
  amount: 3000,
  requestedOn: DateTime(2026, 10, 5),
  status: status,
);

void main() {
  test('pending and approved requests still hold the amount back', () {
    expect(_request(WithdrawalStatus.pending).isInFlight, isTrue);
    expect(_request(WithdrawalStatus.approved).isInFlight, isTrue);
  });

  test('paid and rejected requests no longer hold anything back', () {
    expect(_request(WithdrawalStatus.paid).isInFlight, isFalse);
    expect(_request(WithdrawalStatus.rejected).isInFlight, isFalse);
  });
}
