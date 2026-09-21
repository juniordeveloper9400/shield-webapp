import 'package:flutter/material.dart';

import '../../data/backend/care_repository.dart';
import '../../theme/app_colors.dart';
import 'lab_cart_badge.dart';
import 'lab_package.dart';
import 'profile_tile.dart';

/// Every single test and group test on offer ("View all 10 tests ›" on the Lab
/// landing screen) — the full "Top Profiles and Tests" list.
class TopProfilesScreen extends StatefulWidget {
  const TopProfilesScreen({super.key});

  @override
  State<TopProfilesScreen> createState() => _TopProfilesScreenState();
}

class _TopProfilesScreenState extends State<TopProfilesScreen> {
  List<LabPackage>? _profiles;
  Map<String, String> _images = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      CareRepository.instance.fetchLabPackages(),
      CareRepository.instance.fetchLabCategories(),
    ]);
    if (!mounted) return;
    final packages = results[0] as List<LabPackage>? ?? const [];
    final categories = results[1] as List<LabCategory>? ?? const [];
    setState(() {
      _profiles = [
        for (final p in packages)
          if (p.isProfile) p,
      ];
      _images = {for (final c in categories) c.id: c.image};
    });
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    return Scaffold(
      backgroundColor: AppColors.pageTint,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppColors.textDark,
          tooltip: 'Back',
        ),
        title: const Text(
          'Top Profiles and Tests',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 10, left: 2),
            child: Center(child: LabCartBadge()),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: profiles == null
          ? const Center(child: CircularProgressIndicator())
          : profiles.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No tests available right now',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [LabProfileList(profiles: profiles, images: _images)],
            ),
    );
  }
}
