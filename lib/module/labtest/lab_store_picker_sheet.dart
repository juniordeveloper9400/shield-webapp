import 'package:flutter/material.dart';

import '../../data/backend/care_repository.dart';
import '../../theme/app_colors.dart';
import 'lab_store.dart';

/// A bottom sheet for picking the branch a lab booking collects from.
///
/// Fetches live from `GET /v1/public/care/lab-stores` every time it opens
/// (see [CareRepository.fetchLabStores]) rather than reading this app's own
/// bundled `StoreDirectory` — that list is static and cannot reflect which
/// branches currently take lab bookings, so it is not used here at all.
class LabStorePickerSheet extends StatefulWidget {
  /// The branch currently in effect (`app.shield_store.id`), marked as
  /// selected once the list has loaded.
  final int? selectedId;

  const LabStorePickerSheet({super.key, this.selectedId});

  /// Opens the sheet and resolves to the branch chosen, or null when the
  /// member dismissed it without choosing.
  static Future<LabStore?> show(BuildContext context, {int? selectedId}) {
    return showModalBottomSheet<LabStore>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => LabStorePickerSheet(selectedId: selectedId),
    );
  }

  @override
  State<LabStorePickerSheet> createState() => _LabStorePickerSheetState();
}

class _LabStorePickerSheetState extends State<LabStorePickerSheet> {
  /// Null while loading, empty on a failed or empty read.
  List<LabStore>? _stores;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stores = await CareRepository.instance.fetchLabStores();
    if (mounted) {
      setState(() => _stores = stores ?? const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stores = _stores;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 10, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose a branch',
                      style: TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textMuted,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Who collects your samples for this booking.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: stores == null
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.brandBlue,
                      ),
                    )
                  : stores.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No branch is currently open for lab bookings. '
                          'Check your connection and try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: stores.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppColors.border),
                      itemBuilder: (context, index) {
                        final store = stores[index];
                        final isSelected = store.id == widget.selectedId;
                        return ListTile(
                          onTap: () => Navigator.of(context).pop(store),
                          title: Text(
                            store.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isSelected
                                  ? AppColors.brandBlue
                                  : AppColors.textDark,
                            ),
                          ),
                          subtitle: Text(
                            store.addressLine,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 20,
                                  color: AppColors.brandBlue,
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
