import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// A rounded, bordered card of [AccountMenuItem]s, divided between each one —
/// the same card look the Account screen and its Settings screen both use,
/// so a group reads the same wherever it shows up.
class AccountMenuGroup extends StatelessWidget {
  final List<AccountMenuItem> items;

  const AccountMenuGroup({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            items[i],
            if (i != items.length - 1)
              const Divider(height: 1, indent: 54, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

/// One row of an [AccountMenuGroup] — an icon, a label, an optional trailing
/// value (a balance, a code), and a chevron unless [isDestructive] marks it
/// as an end-of-the-line action (Log out, Delete Account) instead.
class AccountMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final bool isDestructive;
  final VoidCallback onTap;

  const AccountMenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? const Color(0xFFB4322F) : AppColors.textDark;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isDestructive ? color : AppColors.brandBlue,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandGreenDark,
                ),
              ),
            if (!isDestructive) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
