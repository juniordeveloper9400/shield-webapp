import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';
import 'customer_reviews_service.dart';
import 'review_video_player_screen.dart';

/// Whether [url] is a video file the in-app player can stream: an `http(s)`
/// link — what the admin console's upload produces, a public Supabase Storage
/// URL. Anything else is a row from before uploads existed (a YouTube link, a
/// bundled asset path that no longer ships) and has nowhere to play.
bool isPlayableReviewVideo(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return false;
  }
  if (uri.host.isEmpty) return false;
  final host = uri.host.toLowerCase();
  final isYoutube =
      host.contains('youtube.com') ||
      host == 'youtu.be' ||
      host.endsWith('.youtu.be');
  return !isYoutube;
}

/// One clip in the reel — a video file the admin uploaded from the console's
/// Customer Videos page, stored in Supabase Storage.
///
/// [name] is what the card and the player header are labelled with. [subtitle]
/// is the line shown over the video in the player, and is null where there is
/// nothing to add.
class CustomerReviewItem {
  final String id;
  final String name;

  /// The public URL of the uploaded video file.
  final String video;

  /// Optional line shown over the video in the player.
  final String? subtitle;

  /// The poster on the card — a frame the console grabbed from the video when
  /// it was uploaded (or an image the admin chose): a `data:` URI or an
  /// `http(s)` URL. Null when there is none, and the card shows a plain tile.
  final String? thumbnail;

  const CustomerReviewItem({
    required this.id,
    required this.name,
    required this.video,
    this.subtitle,
    this.thumbnail,
  });

  /// Whether the player can stream [video] — see [isPlayableReviewVideo].
  bool get isPlayable => isPlayableReviewVideo(video);
}

/// "What our customers have to say" — the customer video reel under the offer
/// banner.
///
/// Backed by [CustomerReviewsService]: shows whatever clips the pharmacy
/// admin has uploaded and switched on. Tapping a card opens the clip in the
/// in-app player ([showReviewVideo]), which plays it straight from storage and
/// lets the viewer swipe on to the next. Renders nothing at all while there
/// are none — there is no bundled fallback reel, so an empty console list
/// means an empty (not placeholder) section.
class CustomerReviews extends StatefulWidget {
  const CustomerReviews({super.key});

  @override
  State<CustomerReviews> createState() => _CustomerReviewsState();
}

class _CustomerReviewsState extends State<CustomerReviews> {
  @override
  void initState() {
    super.initState();
    CustomerReviewsService.instance.ensureLoaded();
    CustomerReviewsService.instance.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    CustomerReviewsService.instance.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviews = CustomerReviewsService.instance.items;
    if (reviews.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.only(top: 14, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              'What our customers have to say',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
                letterSpacing: -0.3,
              ),
            ),
          ),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: reviews.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final review = reviews[index];
                return _ReviewThumbnailCard(
                  review: review,
                  onTap: () => showReviewVideo(
                    context,
                    reviews: reviews,
                    initialIndex: index,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One card in the reel: the clip's poster, with a play badge over it — a
/// still, standard "tap to watch" affordance. The poster is a stored image, so
/// drawing the reel never downloads a video.
class _ReviewThumbnailCard extends StatelessWidget {
  final CustomerReviewItem review;
  final VoidCallback onTap;

  const _ReviewThumbnailCard({required this.review, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final poster = review.thumbnail;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 142,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              poster != null && poster.isNotEmpty
                  ? AppImage(image: poster, fit: BoxFit.cover)
                  : const ColoredBox(color: AppColors.bannerTop),

              // Gradient overlay from top (dark for name) to bottom
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                    ],
                    stops: const [0.0, 0.40, 1.0],
                  ),
                ),
              ),

              // Play badge, centred — the one visual cue this opens a video.
              const Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  size: 42,
                  color: Colors.white,
                ),
              ),

              // Reviewer/store name, top left.
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Text(
                  review.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
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
