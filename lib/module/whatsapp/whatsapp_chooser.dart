import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart' show FaIcon, FontAwesomeIcons;

import '../../phone.dart';
import '../../theme/app_colors.dart';

/// One place a member can message on WhatsApp: a store or the admin desk.
class WhatsAppOption {
  final String name;
  final String number;

  const WhatsAppOption({required this.name, required this.number});
}

/// Opens a WhatsApp chat straight away when there is one [option], and asks
/// which to message when there are several — each shown with its name and
/// number, so a member who activated plans at two stores picks the right one.
///
/// With no options nothing opens; the caller only offers this when there is
/// at least one.
Future<void> openWhatsAppChooser(
  BuildContext context, {
  required String title,
  required List<WhatsAppOption> options,
}) async {
  if (options.isEmpty) {
    return;
  }
  if (options.length == 1) {
    await WhatsApp.open(context, options.first.number);
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            for (final option in options)
              ListTile(
                key: ValueKey('whatsapp-option-${option.number}'),
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: AppColors.brandGreenDeep,
                  child: FaIcon(FontAwesomeIcons.whatsapp, color: AppColors.white, size: 22),
                ),
                title: Text(
                  option.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                subtitle: Text(
                  option.number,
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  WhatsApp.open(context, option.number);
                },
              ),
          ],
        ),
      ),
    ),
  );
}
