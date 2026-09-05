import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _openTarget(String target) async {
    final uri = Uri.tryParse(target.trim());
    if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
      // Not a link the app can open on its own (a bare route name, or blank)
      // — the banner is still worth showing, just not tappable.
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('HomeHeroBanner: could not open $target — $error');
    }
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
                      itemBuilder: (context, index) {
                        final banner = banners[index];
                        return GestureDetector(
                          onTap: banner.target.isEmpty
                              ? null
                              : () => _openTarget(banner.target),
                          child: _BannerSlide(banner: banner),
                        );
                      },
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

/// One slide: the admin's image, with their title / subtitle / CTA embossed
/// bottom-left over a scrim — the same corner every promo banner sets its
/// copy in, so it reads before the eye even reaches the image's subject.
///
/// The scrim is drawn whether or not there is copy: a slide with only an
/// image still gets the same bottom shading as the bundled default banner
/// (which paints it into the picture), so a plain photo doesn't look
/// undressed next to a slide that has text.
class _BannerSlide extends StatelessWidget {
  final HomeBannerModel banner;

  const _BannerSlide({required this.banner});

  @override
  Widget build(BuildContext context) {
    final hasTitle = banner.title.isNotEmpty;
    final hasSubtitle = banner.subtitle.isNotEmpty;
    final hasCta = banner.cta.isNotEmpty;
    final hasCopy = hasTitle || hasSubtitle || hasCta;

    return Stack(
      fit: StackFit.expand,
      children: [
        AppImage(
          image: banner.image,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
        // A bottom-weighted scrim, not a flat wash — it leaves the top of the
        // image clear and only darkens the strip the copy sits on, so a
        // bright product photo still reads clearly above the fold.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.35, 1.0],
                colors: [
                  Colors.black.withValues(alpha: 0),
                  Colors.black.withValues(alpha: hasCopy ? 0.62 : 0.32),
                ],
              ),
            ),
          ),
        ),
        if (hasCopy)
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasTitle)
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      shadows: [
                        Shadow(color: Colors.black45, blurRadius: 4),
                      ],
                    ),
                  ),
                if (hasSubtitle)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      banner.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                        shadows: [
                          Shadow(color: Colors.black45, blurRadius: 3),
                        ],
                      ),
                    ),
                  ),
                if (hasCta)
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            banner.cta,
                            style: const TextStyle(
                              color: AppColors.brandBlue,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: AppColors.brandBlue,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
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
