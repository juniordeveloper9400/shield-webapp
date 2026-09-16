import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';
import 'customer_reviews_service.dart';
import 'review_video_player_screen.dart';

/// The video id out of a YouTube URL — `watch?v=`, `youtu.be/`, `/embed/`,
/// `/shorts/` and `/live/` links, with or without extra query params — or
/// null when [url] is not a YouTube link at all.
String? _youtubeVideoId(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase();

  if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  }
  if (!host.contains('youtube.com')) {
    return null;
  }

  final fromQuery = uri.queryParameters['v'];
  if (fromQuery != null && fromQuery.isNotEmpty) {
    return fromQuery;
  }
  final segments = uri.pathSegments;
  for (final marker in ['embed', 'shorts', 'live']) {
    final index = segments.indexOf(marker);
    if (index != -1 && index + 1 < segments.length) {
      return segments[index + 1];
    }
  }
  return null;
}

/// One clip in the reel — always a YouTube link, added from the admin
/// console's Customer Videos page.
///
/// [name] is what the card and the player header are labelled with. [subtitle]
/// is the line shown under the title on the player page, and is null where
/// there is nothing to add.
class CustomerReviewItem {
  final String id;
  final String name;

  /// A YouTube URL (watch/youtu.be/embed/shorts/live link). Anything that
  /// does not parse as one has nowhere to play — see [youtubeId].
  final String video;

  /// Optional line shown under the title on the player page.
  final String? subtitle;

  /// An admin-supplied poster image for the thumbnail card, or null to use
  /// YouTube's own poster for the clip.
  final String? thumbnail;

  const CustomerReviewItem({
    required this.id,
    required this.name,
    required this.video,
    this.subtitle,
    this.thumbnail,
  });

  /// The YouTube video id [video] points to, or null when it does not parse
  /// as a YouTube link at all (nothing plays for a card like this).
  String? get youtubeId => _youtubeVideoId(video);

  /// What the thumbnail card shows: the admin-supplied [thumbnail] where
  /// there is one, otherwise YouTube's own poster — YouTube serves that at a
  /// fixed URL for every video, so there is never a reason to ask the admin
  /// to upload one by hand. Null only when [video] is not a YouTube link.
  String? get displayThumbnail {
    final custom = thumbnail;
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final id = youtubeId;
    return id == null ? null : 'https://img.youtube.com/vi/$id/hqdefault.jpg';
  }
}

/// "What our customers have to say" — the customer video reel under the offer
/// banner.
///
/// Backed by [CustomerReviewsService]: shows whatever YouTube clips the
/// pharmacy admin has added and switched on. Renders nothing at all while
/// there are none — there is no bundled fallback reel, so an empty console
/// list means an empty (not placeholder) section.
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

  /// Opens the tapped clip as an overlay on this same page, in YouTube's own
  /// embedded player — see [showReviewVideo]. A card with no
  /// [CustomerReviewItem.youtubeId] (a malformed or pre-YouTube leftover row)
  /// has nowhere to go, so the tap is simply a no-op rather than a crash.
  void _openReview(BuildContext context, CustomerReviewItem review) {
    final youtubeId = review.youtubeId;
    if (youtubeId == null) {
      return;
    }
    showReviewVideo(
      context,
      videoId: youtubeId,
      title: review.name,
      description: review.subtitle,
    );
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
                  onTap: () => _openReview(context, review),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One card in the reel: the clip's YouTube poster, with a play badge over
/// it — a still, standard "tap to watch" affordance, since a tap always
/// opens YouTube's own player rather than an in-app swipe reel.
class _ReviewThumbnailCard extends StatelessWidget {
  final CustomerReviewItem review;
  final VoidCallback onTap;

  const _ReviewThumbnailCard({required this.review, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final poster = review.displayThumbnail;
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
