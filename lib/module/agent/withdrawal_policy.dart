const minimumAgentWithdrawal = 3000;

int eligibleWithdrawalAmount({
  required int earned,
  required int redeemed,
  required int pending,
}) {
  final available = earned - redeemed - pending;
  return available >= minimumAgentWithdrawal ? available : 0;
}
