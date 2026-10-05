import 'package:flutter/material.dart';

import '../../data/backend/contact_repository.dart';
import '../../phone.dart';
import '../../theme/app_colors.dart';
import '../prescription/upload_prescription_screen.dart';
import '../wallet/wallet_service.dart';
import '../whatsapp/whatsapp_chooser.dart';

/// Single home card carrying both the prescription upload action and the
/// call-to-order number. Tapping anywhere opens the upload flow.
class PrescriptionCard extends StatelessWidget {
  const PrescriptionCard({super.key});

  /// The order line.
  static const String orderPhone = '8594000970';

  /// The alternative to uploading, spelled out: not everyone has a photo of a
  /// prescription to hand, and both other routes end at the same counter.
  static const String orderCopy =
      'You may place your order through our nearest store, or call us to '
      'order on ';

  /// Who a member can message: each store their active plans were bought at,
  /// with its own number. With none, the admin desk (or the order line if that
  /// is not set yet). Two or more opens the chooser, with names and numbers.
  Future<List<WhatsAppOption>> _whatsAppOptions() async {
    final options = <WhatsAppOption>[];
    final seen = <String>{};
    for (final card in WalletService.instance.cards) {
      final store = card.store;
      if (store == null || store.phone.trim().isEmpty || !seen.add(store.id)) {
        continue;
      }
      options.add(WhatsAppOption(name: store.name, number: store.phone));
    }
    if (options.isEmpty) {
      final admin = await ContactRepository.instance.adminWhatsapp();
      options.add(
        WhatsAppOption(name: 'Sahakar 360 desk', number: admin ?? orderPhone),
      );
    }
    return options;
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final options = await _whatsAppOptions();
    if (!context.mounted) {
      return;
    }
    await openWhatsAppChooser(
      context,
      title: 'Message on WhatsApp',
      options: options,
    );
  }

  void _openUpload(BuildContext context) {
    UploadPrescriptionScreen.open(context);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _openUpload(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            // Hugs its two rows. Under loose constraints a Column defaults to
            // MainAxisSize.max and stretches to whatever it is given.
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF3D9BC)),
                    ),
                    child: const Icon(
                      Icons.assignment_outlined,
                      size: 24,
                      color: Color(0xFFE07B39),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add a prescription',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Upload your prescription here',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Ignored by the pointer so the whole card stays one tap
                  // target while still reading as an explicit action.
                  const IgnorePointer(child: _UploadChip()),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 4),
              // Its own tap target inside the card's: the copy names a phone
              // number, so tapping the copy has to dial it. The nested InkWell
              // takes the hit here and the card still opens upload everywhere
              // else.
              Material(
                color: AppColors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () => Dialer.call(context, orderPhone),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: orderCopy,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.4,
                                    color: AppColors.textBody,
                                  ),
                                ),
                                TextSpan(
                                  text: orderPhone,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.4,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.brandBlue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Ignored by the pointer because the row around it is
                        // already the button; a second target would only make
                        // the edges of the chip behave differently.
                        const IgnorePointer(child: _CallChip()),
                        const SizedBox(width: 8),
                        // Its own tap target, so it opens WhatsApp rather than
                        // the card's call row it sits inside.
                        _WhatsAppChip(
                          onTap: () => _openWhatsApp(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadChip extends StatelessWidget {
  const _UploadChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.brandBlue),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.file_upload_outlined,
            size: 19,
            color: AppColors.brandBlue,
          ),
          SizedBox(width: 6),
          Text(
            'Upload',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.brandBlue,
            ),
          ),
        ],
      ),
    );
  }
}

/// The WhatsApp counterpart to [_CallChip]: same size and shape, green, with
/// its own tap target. Material has no WhatsApp mark, so a chat bubble stands
/// in for it, labelled for screen readers.
class _WhatsAppChip extends StatelessWidget {
  final VoidCallback onTap;

  const _WhatsAppChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Message on WhatsApp to order',
      child: Material(
        color: AppColors.brandGreenDeep,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: const SizedBox(
            width: 46,
            height: 42,
            child: Icon(
              Icons.chat_rounded,
              size: 21,
              color: AppColors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _CallChip extends StatelessWidget {
  const _CallChip();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Call to order',
      child: Container(
        width: 46,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.brandBlue,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.phone_in_talk_rounded,
          size: 21,
          color: AppColors.white,
        ),
      ),
    );
  }
}
