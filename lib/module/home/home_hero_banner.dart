import 'package:flutter/material.dart';

import '../../data/neon/home_banner_repository.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';

/// Top hero promotional banner displayed immediately below the search bar.
///
/// Reads `app.home_banner` (maintained from the admin console) and shows
/// whatever the admin has switched on, one slide at a time in a swipeable
/// carousel when there is more than one. Falls back to the bundled default
/// banner when nothing is configured yet, the database is unreachable, or a
/// slide's image fails to decode — the strip never comes up blank.
class HomeHeroBanner extends StatefulWidget {
  const HomeHeroBanner({super.key});

  static const String assetPath = 'assets/banners/hero_banner.jpg';

  @override
  State<HomeHeroBanner> createState() => _HomeHeroBannerState();
}

class _HomeHeroBannerState extends State<HomeHeroBanner> {
  late Future<List<HomeBannerModel>> _future;
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _future = HomeBannerRepository.instance.listActive();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandNavy.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: FutureBuilder<List<HomeBannerModel>>(
              future: _future,
              builder: (context, snapshot) {
                final banners = snapshot.data ?? const [];
                if (banners.isEmpty) {
                  return _DefaultBanner();
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _controller,
                      itemCount: banners.length,
                      onPageChanged: (index) => setState(() => _page = index),
                      itemBuilder: (context, index) => AppImage(
                        image: banners[index].image,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                    if (banners.length > 1)
                      Positioned(
                        bottom: 10,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < banners.length; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: i == _page ? 16 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: AppColors.white.withValues(
                                    alpha: i == _page ? 0.95 : 0.55,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DefaultBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      HomeHeroBanner.assetPath,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: AppColors.offerTint,
          alignment: Alignment.center,
          child: const Icon(
            Icons.image_not_supported_outlined,
            color: AppColors.brandBlue,
            size: 36,
          ),
        );
      },
    );
  }
}
