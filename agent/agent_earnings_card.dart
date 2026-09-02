import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dates.dart';
import '../../money.dart';
import '../../theme/app_colors.dart';
import 'agent_model.dart';
import 'agent_service.dart';

/// The earnings panel: what the agent has earned, redeemed and may withdraw on
/// the front, the withdrawal requests they have raised on the back, and a turn
/// between them.
///
/// The turn is the simple half of [WalletFlipCard]'s — one flag, one
/// controller, a mid-point face swap and a counter-rotated back — with no
/// auto-turn and no inner pager, because there are only ever two things to
/// show.
class AgentEarningsCard extends StatefulWidget {
  final Agent agent;

  const AgentEarningsCard({super.key, required this.agent});

  static const Duration flipDuration = Duration(milliseconds: 520);

  /// Both faces stand at this height so the page below does not jump as the
  /// card turns.
  static const double height = 232;

  @override
  State<AgentEarningsCard> createState() => _AgentEarningsCardState();
}

class _AgentEarningsCardState extends State<AgentEarningsCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AgentEarningsCard.flipDuration,
  );

  late final Animation<double> _turn = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flip() {
    if (_controller.status == AnimationStatus.forward ||
        _controller.value == 1) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  Future<int?> _openAmountSheet(_AmountSheet sheet) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => sheet,
    );
  }

  Future<void> _openWithdrawal() async {
    final messenger = ScaffoldMessenger.of(context);
    final withdrawable = AgentService.instance.withdrawableFor(widget.agent);
    final raised = await _openAmountSheet(
      _AmountSheet(
        title: 'Request a withdrawal',
        subtitle:
            'Withdrawable now ₹${formatRupees(withdrawable)} · minimum '
            '₹${formatRupees(AgentService.minWithdrawal)}',
        actionLabel: 'Submit request',
        emptyError: 'Enter an amount to withdraw',
        onSubmit: (amount) =>
            AgentService.instance.requestWithdrawal(widget.agent, amount),
      ),
    );
    if (raised != null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Withdrawal request submitted')),
      );
      // Turn to the back so the new request is what the agent sees next.
      if (mounted && _controller.value == 0) {
        _controller.forward();
      }
    }
  }

  Future<void> _openAddToWallet() async {
    final messenger = ScaffoldMessenger.of(context);
    final withdrawable = AgentService.instance.withdrawableFor(widget.agent);
    final added = await _openAmountSheet(
      _AmountSheet(
        title: 'Add cash to wallet',
        subtitle:
            'Available ₹${formatRupees(withdrawable)} · moves into your SHIELD '
            'wallet straight away',
        actionLabel: 'Add to wallet',
        emptyError: 'Enter an amount to add',
        onSubmit: (amount) =>
            AgentService.instance.moveEarningsToWallet(widget.agent, amount),
      ),
    );
    if (added != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '₹${formatRupees(added)} added to your SHIELD wallet',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AgentService.instance,
      builder: (context, _) {
        final withdrawable = AgentService.instance.withdrawableFor(
          widget.agent,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: _flip,
              child: SizedBox(
                height: AgentEarningsCard.height,
                child: AnimatedBuilder(
                  animation: _turn,
                  builder: (context, __) {
                    final angle = _turn.value * math.pi;
                    final showBack = _turn.value > 0.5;

                    return Semantics(
                      button: true,
                      label: showBack
                          ? 'Withdrawal requests. Tap to see your earnings.'
                          : 'Your earnings. Tap to see withdrawal requests.',
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0011)
                          ..rotateY(angle),
                        child: showBack
                            ? Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..rotateY(math.pi),
                                child: _EarningsBack(agent: widget.agent),
                              )
                            : _EarningsFront(agent: widget.agent),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Outside the card on purpose: these two act on the balance the
            // card states, they are not part of stating it, and the card's
            // own turn (front figures, back requests) has nothing to do with
            // either action being available.
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: withdrawable >= AgentService.minWithdrawal
                        ? _openWithdrawal
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Request withdrawal',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: withdrawable > 0 ? _openAddToWallet : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandBlue,
                      disabledForegroundColor: AppColors.textMuted,
                      side: const BorderSide(color: AppColors.brandBlue),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Add to wallet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The blue panel both faces are drawn on, sharing the wallet panel's look so
/// the two money surfaces in the app read as relatives.
class _EarningsShell extends StatelessWidget {
  final Widget child;

  const _EarningsShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.walletShadow.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.walletPanel),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                right: -70,
                top: -90,
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.brandGreen.withValues(alpha: 0.24),
                        AppColors.brandGreen.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _ink(double size, FontWeight weight, {Color? color}) => TextStyle(
  fontSize: size,
  height: 1.15,
  fontWeight: weight,
  color: color ?? AppColors.white,
);

const Color _muted = Color(0xFFCBD9EE);

class _EarningsFront extends StatelessWidget {
  final Agent agent;

  const _EarningsFront({required this.agent});

  @override
  Widget build(BuildContext context) {
    final service = AgentService.instance;
    final withdrawable = service.withdrawableFor(agent);

    return _EarningsShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Your earnings', style: _ink(15, FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            'WITHDRAWABLE',
            style: _ink(9, FontWeight.w800, color: _muted).copyWith(
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '₹${formatRupees(withdrawable)}',
              maxLines: 1,
              style: _ink(
                26,
                FontWeight.w800,
                color: AppColors.planActive,
              ).copyWith(letterSpacing: -0.4),
            ),
          ),
          const Spacer(),
          const Divider(height: 18, color: Color(0x3DFFFFFF)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Figure(
                  label: 'EARNED',
                  amount: service.earnedFor(agent),
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'REDEEMED',
                  amount: service.redeemedFor(agent),
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'MIN WITHDRAWAL',
                  amount: AgentService.minWithdrawal,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _FlipHint('Tap to see requests'),
        ],
      ),
    );
  }
}

class _EarningsBack extends StatelessWidget {
  final Agent agent;

  const _EarningsBack({required this.agent});

  @override
  Widget build(BuildContext context) {
    final requests = AgentService.instance.requestsFor(agent);

    return _EarningsShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Withdrawal requests', style: _ink(15, FontWeight.w800)),
          const SizedBox(height: 10),
          Expanded(
            child: requests.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      'No withdrawal requests yet. Raise one from the front '
                      'of this card.',
                      style: _ink(12.5, FontWeight.w500, color: _muted),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: requests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) =>
                        _RequestRow(request: requests[index]),
                  ),
          ),
          const SizedBox(height: 8),
          const _FlipHint('Tap to go back'),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  final WithdrawalRequest request;

  const _RequestRow({required this.request});

  @override
  Widget build(BuildContext context) {
    final colour = switch (request.status) {
      WithdrawalStatus.pending => AppColors.planWaiting,
      WithdrawalStatus.paid => AppColors.planActive,
      WithdrawalStatus.rejected => AppColors.dangerLine,
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.16)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₹${formatRupees(request.amount)}',
                  style: _ink(14, FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'Raised ${formatDate(request.requestedOn)}',
                  style: _ink(11, FontWeight.w500, color: _muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colour.withValues(alpha: 0.65)),
            ),
            child: Text(
              request.status.label,
              style: _ink(
                10.5,
                FontWeight.w800,
                color: colour,
              ).copyWith(letterSpacing: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final int amount;
  final bool alignEnd;

  const _Figure({
    required this.label,
    required this.amount,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            style: _ink(9, FontWeight.w800, color: const Color(0xCCFFFFFF))
                .copyWith(letterSpacing: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            '₹${formatRupees(amount)}',
            maxLines: 1,
            style: _ink(16, FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _FlipHint extends StatelessWidget {
  final String text;

  const _FlipHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _ink(10.5, FontWeight.w600, color: _muted),
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.flip_camera_android_rounded,
          size: 13,
          color: AppColors.white.withValues(alpha: 0.7),
        ),
      ],
    );
  }
}

/// A single-amount form raised from the earnings card — the withdrawal
/// request and the add-to-wallet move are the same shape, so they share it.
///
/// [onSubmit] applies the typed amount and returns null on success or the
/// reason it was refused; on success the sheet pops with that amount so the
/// caller can confirm it.
class _AmountSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final String emptyError;
  final String? Function(int amount) onSubmit;

  const _AmountSheet({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.emptyError,
    required this.onSubmit,
  });

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_amount.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = widget.emptyError);
      return;
    }
    final failure = widget.onSubmit(value);
    if (failure != null) {
      setState(() => _error = failure);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.subtitle,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(7),
            ],
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              prefixText: '₹ ',
              hintText: 'Amount',
              filled: true,
              fillColor: AppColors.pageTint,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.searchBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppColors.brandBlue,
                  width: 1.6,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              widget.actionLabel,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
