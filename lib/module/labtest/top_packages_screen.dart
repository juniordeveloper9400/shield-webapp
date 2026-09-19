import 'package:flutter/material.dart';

import '../../data/backend/care_repository.dart';
import '../../theme/app_colors.dart';
import 'lab_cart_badge.dart';
import 'lab_package.dart';
import 'package_card.dart';

/// Full-page list of diagnostic packages.
///
/// [onBack] is supplied when the screen is hosted as a lab sub-tab; without it
/// the screen falls back to popping the route.
class TopPackagesScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const TopPackagesScreen({super.key, this.onBack});

  @override
  State<TopPackagesScreen> createState() => _TopPackagesScreenState();
}

class _TopPackagesScreenState extends State<TopPackagesScreen> {
  List<LabPackage>? _packages;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final packages = await CareRepository.instance.fetchLabPackages();
    if (mounted) {
      // null means "unconfigured or unreachable", treated the same as
      // "nothing to show" — see LabTestScreen's identical fallback.
      setState(() => _packages = packages ?? const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packages = _packages;
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
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
      body: packages == null
          ? const Center(child: CircularProgressIndicator())
          : packages.isEmpty
          ? const _NoPackages()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              itemCount: packages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) =>
                  PackageCard(package: packages[index]),
            ),
    );
  }
}

class _NoPackages extends StatelessWidget {
  const _NoPackages();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.science_outlined,
              size: 40,
              color: AppColors.textMuted,
            ),
            SizedBox(height: 10),
            Text(
              'No packages available right now',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
