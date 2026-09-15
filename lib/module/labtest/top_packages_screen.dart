import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'lab_cart_badge.dart';
import 'lab_package.dart';
import 'package_card.dart';

/// Full-page list of diagnostic packages.
///
/// [onBack] is supplied when the screen is hosted as a lab sub-tab; without it
/// the screen falls back to popping the route.
class TopPackagesScreen extends StatelessWidget {
  final VoidCallback? onBack;

  const TopPackagesScreen({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.textDark,
          tooltip: 'Back',
        ),
        title: const Text(
          'All Packages',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search_rounded),
            color: AppColors.textDark,
            tooltip: 'Search packages',
          ),
          const Padding(
            padding: EdgeInsets.only(right: 10, left: 2),
            child: Center(child: LabCartBadge()),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        itemCount: LabCatalogue.packages.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) =>
            PackageCard(package: LabCatalogue.packages[index]),
      ),
    );
  }
}
