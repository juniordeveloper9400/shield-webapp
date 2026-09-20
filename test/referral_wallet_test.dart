import 'package:flutter_test/flutter_test.dart';
import 'package:shield/module/wallet/wallet_service.dart';

void main() {
  setUp(() => WalletService.instance.reset());
  test('earned money is spendable without buying a plan', () {
    final wallet = WalletService.instance;
    wallet.creditEarnings(amount: 200);
    expect(wallet.isActivated, isTrue);
    expect(wallet.spendBalance(amount: 200, label: 'Purchase'), isTrue);
    expect(wallet.balance, 0);
    expect(wallet.spendBalance(amount: 1, label: 'Overdraft'), isFalse);
  });
  test('earnings-only wallet cannot top up a nonexistent plan', () {
    final wallet = WalletService.instance;
    wallet.creditEarnings(amount: 200);
    expect(wallet.topUp(amount: 100), isFalse);
  });
}
