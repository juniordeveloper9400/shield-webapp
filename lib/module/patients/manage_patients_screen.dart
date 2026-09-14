import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/backend/patient_repository.dart';
import '../../theme/app_colors.dart';
import 'patient_book.dart';
import 'patient_form_sheet.dart';

/// "Manage patients" from the account menu: everyone on the account, with add,
/// edit and remove.
class ManagePatientsScreen extends StatelessWidget {
  const ManagePatientsScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final saved = await PatientFormSheet.show(context);
    if (saved != null && context.mounted) {
      _confirm(context, '${saved.name} added');
    }
  }

  Future<void> _edit(BuildContext context, Patient patient) async {
    final saved = await PatientFormSheet.show(context, existing: patient);
    if (saved != null && context.mounted) {
      _confirm(context, '${saved.name} updated');
    }
  }

  Future<void> _remove(BuildContext context, Patient patient) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove patient?'),
        content: Text(
          '${patient.name} will no longer be offered when uploading a '
          'prescription.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final remoteId = patient.remoteId;
      if (remoteId != null) {
        unawaited(PatientRepository.instance.softDelete(remoteId));
      }
      PatientBook.instance.remove(patient.id);
    }
  }

  static void _confirm(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Manage patients',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: ListenableBuilder(
        listenable: PatientBook.instance,
        builder: (context, _) {
          final patients = PatientBook.instance.patients;
          if (patients.isEmpty) {
            return const _EmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: patients.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _PatientCard(
              patient: patients[index],
              onEdit: () => _edit(context, patients[index]),
              onRemove: () => _remove(context, patients[index]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        backgroundColor: AppColors.brandBlue,
        foregroundColor: AppColors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add patient'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 54, color: AppColors.textMuted),
            SizedBox(height: 14),
            Text(
              'No patients yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Add the people you order for, so a prescription can say who it '
              'is for.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textBody),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final Patient patient;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _PatientCard({
    required this.patient,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.offerTint,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  patient.name.isEmpty
                      ? '?'
                      : patient.name.characters.first.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandBlue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      patient.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                    // The number is worth showing: it is where this patient's
                    // reports and delivery updates go.
                    const SizedBox(height: 2),
                    Text(
                      patient.hasAbha
                          ? '+91 ${patient.phone} · ABHA ${patient.abhaLabel}'
                          : '+91 ${patient.phone}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (patient.address.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        patient.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                iconSize: 20,
                color: AppColors.textBody,
                tooltip: 'Edit ${patient.name}',
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
                iconSize: 20,
                color: AppColors.textMuted,
                tooltip: 'Remove ${patient.name}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
