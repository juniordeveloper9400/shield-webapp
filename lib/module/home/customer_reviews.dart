import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_image.dart';
import 'customer_reviews_service.dart';

/// A `VideoPlayerController` for [video] — network for an admin-hosted link
/// (every clip added from the console is a hosted URL; see
/// `CustomerReviewRepository`), a bundled asset otherwise (every clip that
/// ships with the app).
VideoPlayerController _controllerFor(String video) {
  return AppImage.isNetwork(video)
      ? VideoPlayerController.networkUrl(Uri.parse(video))
      : VideoPlayerController.asset(video);
}

/// One clip in the reel.
///
/// [name] is what the card and the player header are labelled with; it is
/// taken from what the clip is of, because that is all this file can honestly
/// know about it. [subtitle] is the line set over the video in the player and
/// is null where there is nothing to add — a clip of a shop does not need a
/// caption telling the viewer it is a shop.
class CustomerReviewItem {
  final String id;
  final String name;

  /// The clip itself: an asset video, drawn on the card and played full
  /// screen.
  final String video;

  /// Optional line over the video in the story player.
  final String? subtitle;

  /// An admin-supplied poster image for the thumbnail card, or null to decode
  /// one from the clip itself — which is all every bundled clip has.
  final String? thumbnail;

  /// How long the story runs when the video will not play.
  ///
  /// The real length comes from the file. This is only what the progress bar
  /// falls back to when there is no video to read a length off — a broken
  /// asset, or a test with no platform to decode it.
  final Duration duration;

  const CustomerReviewItem({
    required this.id,
    required this.name,
    required this.video,
    this.subtitle,
    this.thumbnail,
    this.duration = const Duration(seconds: 8),
  });
}

/// "What our customers have to say" — the customer video reel under the offer
/// banner, and the full-screen story player it opens into.
///
/// Backed by [CustomerReviewsService]: shows whatever clips the pharmacy
/// admin has added and switched on, falling back to [reviews] — the clips
/// bundled with the app — whenever the admin hasn't added one yet or the
/// database can't be reached, so the reel is never blank.
class CustomerReviews extends StatefulWidget {
  const CustomerReviews({super.key});

  /// The clips bundled with the app, in the order they run.
  ///
  /// Plain lowercase filenames with no spaces, because an asset path is a
  /// URI. Both batches of clips have arrived with spaces in their names and
  /// both times nothing played until they were renamed; keep any new clip to
  /// this shape.
  ///
  /// The names below are taken from the filenames, which is the only thing
  /// this file knows about what is in each clip. Anything more — who is
  /// speaking, what they say — has to come from whoever shot them.
  /// The clips, in the order they run: the shops first, then what goes on
  /// inside them.
  ///
  /// Plain lowercase filenames with no spaces, because an asset path is a
  /// URI. Every batch of clips has arrived with spaces in their names and
  /// every time nothing played until they were renamed; keep any new clip to
  /// this shape.
  ///
  /// The names below are taken from the filenames, which is the only thing
  /// this file knows about what is in each clip. Anything more — who is
  /// speaking, what they say — has to come from whoever shot them.
  static const List<CustomerReviewItem> reviews = [
    CustomerReviewItem(
      id: 'melattur',
      name: 'Melattur',
      video: 'assets/reviews/melattur_store.mp4',
    ),
    CustomerReviewItem(
      id: 'makkaraparamba',
      name: 'Makkaraparamba',
      video: 'assets/reviews/makkaraparamba_store.mp4',
    ),
    CustomerReviewItem(
      id: 'tirur',
      name: 'Tirur',
      video: 'assets/reviews/tirur_store.mp4',
    ),
    CustomerReviewItem(
      id: 'tirurangadi',
      name: 'Tirurangadi',
      video: 'assets/reviews/tirurangadi_store.mp4',
    ),
    CustomerReviewItem(
      id: 'heart',
      name: 'From the heart',
      video: 'assets/reviews/customer_review_from_heart.mp4',
    ),
    CustomerReviewItem(
      id: 'smart_clinic',
      name: 'Smart clinic',
      video: 'assets/reviews/smart_clinic.mp4',
    ),
    CustomerReviewItem(
      id: 'preventive',
      name: 'Preventive health',
      video: 'assets/reviews/preventive_health.mp4',
    ),
    CustomerReviewItem(
      id: 'serum',
      name: 'The serum secret',
      video: 'assets/reviews/the_serum_secret.mp4',
    ),
  ];

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

  void _openStoryViewer(
    BuildContext context,
    List<CustomerReviewItem> reviews,
    int initialIndex,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: CustomerStoryPlayerModal(
              reviews: reviews,
              initialIndex: initialIndex,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reviews = CustomerReviewsService.instance.items;
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
            height: 242,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: reviews.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final review = reviews[index];
                return _VideoReviewThumbnailCard(
                  review: review,
                  onTap: () => _openStoryViewer(context, reviews, index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One card in the reel: a still frame lifted out of the clip.
///
/// The row reads as a row of photographs and plays nothing. Eleven clips all
/// running at once is a wall of movement nobody asked for and eleven decoders
/// on the home feed; the story player is where these actually play, and it
/// opens because someone chose to open it.
///
/// The still comes out of the clip rather than out of a poster image because
/// there are no poster images — the frame is decoded once, held, and the
/// player is left paused on it.
class _VideoReviewThumbnailCard extends StatefulWidget {
  final CustomerReviewItem review;
  final VoidCallback onTap;

  const _VideoReviewThumbnailCard({required this.review, required this.onTap});

  @override
  State<_VideoReviewThumbnailCard> createState() =>
      _VideoReviewThumbnailCardState();
}

class _VideoReviewThumbnailCardState extends State<_VideoReviewThumbnailCard> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// How far into a clip the still is taken from.
  ///
  /// Not the very first frame: clips routinely open on black or on a fade,
  /// and a row of black rectangles is a worse thumbnail than no thumbnail.
  /// A moment in, there is a face.
  static const Duration _posterFrame = Duration(milliseconds: 600);

  /// Built and torn down with the card, which the horizontal list does as
  /// cards scroll in and out — so only the clips on screen hold a decoder,
  /// and each holds it only long enough to paint one frame.
  Future<void> _load() async {
    if ((widget.review.thumbnail ?? '').isNotEmpty) {
      // The admin gave this clip a poster of its own — decoding a frame
      // (over the network, for a hosted clip) would be slower and no
      // better than what they chose.
      return;
    }
    final controller = _controllerFor(widget.review.video);
    try {
      await controller.initialize();
      await controller.setVolume(0);
      // Seeking is what forces a frame to be decoded and shown. Left paused
      // there, the card is a photograph.
      final length = controller.value.duration;
      await controller.seekTo(
        length > _posterFrame ? _posterFrame : Duration.zero,
      );
    } catch (error) {
      // A clip that will not decode leaves the card on its placeholder rather
      // than taking the feed down with it — but it says so on the console,
      // because a reel that silently shows placeholders gives nobody anything
      // to go on.
      debugPrint('SHIELD: review clip failed — ${widget.review.video}: $error');
      await controller.dispose();
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
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
              _ReviewVideoSurface(
                controller: _controller,
                thumbnail: widget.review.thumbnail,
              ),

              // Gradient overlay from top (dark for name) to bottom
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.20),
                    ],
                    stops: const [0.0, 0.40, 1.0],
                  ),
                ),
              ),

              // Reviewer first name, top left.
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Text(
                  widget.review.name,
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

/// A clip drawn to fill its box, or the placeholder that stands in until it
/// can be.
///
/// Cover rather than contain: these are portrait clips in a portrait card and
/// letterboxing them would leave bars down a row that is meant to read as one
/// continuous strip of faces.
class _ReviewVideoSurface extends StatelessWidget {
  final VideoPlayerController? controller;

  /// An admin-supplied poster, shown until (or instead of) the clip.
  final String? thumbnail;

  /// What fills the box until the clip can, when there is no [thumbnail]
  /// either. A flat colour and nothing else: a camcorder icon that shows for
  /// a moment and then vanishes announces the wait instead of covering it,
  /// and in the player — which opens black and fades the clip up — there is
  /// nothing to cover in the first place.
  final Color placeholder;

  const _ReviewVideoSurface({
    required this.controller,
    this.thumbnail,
    this.placeholder = AppColors.bannerTop,
  });

  @override
  Widget build(BuildContext context) {
    final player = controller;
    if (player == null || !player.value.isInitialized) {
      final poster = thumbnail;
      if (poster != null && poster.isNotEmpty) {
        return AppImage(image: poster, fit: BoxFit.cover);
      }
      return ColoredBox(color: placeholder);
    }

    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: player.value.size.width,
        height: player.value.size.height,
        child: VideoPlayer(player),
      ),
    );
  }
}

/// The full-screen story player: one review at a time, with sound.
///
/// Progress, the scrubber and the clock all read the clip's own position when
/// there is a clip playing. When there is not — an asset that will not decode,
/// or a widget test with no platform behind it — an animation of the review's
/// stated [CustomerReviewItem.duration] drives them instead, so the story
/// still advances and the controls still mean something.
class CustomerStoryPlayerModal extends StatefulWidget {
  final List<CustomerReviewItem> reviews;
  final int initialIndex;

  const CustomerStoryPlayerModal({
    super.key,
    required this.reviews,
    this.initialIndex = 0,
  });

  @override
  State<CustomerStoryPlayerModal> createState() =>
      _CustomerStoryPlayerModalState();
}

class _CustomerStoryPlayerModalState extends State<CustomerStoryPlayerModal>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  late AnimationController _animController;
  bool _isPlaying = true;
  bool _isMuted = false;

  VideoPlayerController? _video;

  /// Bumped every time a story starts, so a clip that finishes loading after
  /// the customer has already tapped past it knows it is no longer wanted.
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _animController = AnimationController(
      vsync: this,
      duration: widget.reviews[_currentIndex].duration,
    );

    _animController.addStatusListener((status) {
      // Only the fallback finishes this way; a clip finishes on its own
      // position, and running both would skip a story.
      if (status == AnimationStatus.completed && !_hasVideo) {
        _onStoryFinished();
      }
    });

    _animController.addListener(() {
      if (!_hasVideo) {
        setState(() {});
      }
    });

    _startCurrentStory();
  }

  bool get _hasVideo => _video?.value.isInitialized ?? false;

  /// How far through the story is, 0 to 1 — from the clip where there is one.
  double get _progress {
    final player = _video;
    if (player != null && player.value.isInitialized) {
      final total = player.value.duration.inMilliseconds;
      if (total > 0) {
        return (player.value.position.inMilliseconds / total).clamp(0.0, 1.0);
      }
    }
    return _animController.value.clamp(0.0, 1.0);
  }

  Duration get _position {
    final player = _video;
    if (player != null && player.value.isInitialized) {
      return player.value.position;
    }
    return widget.reviews[_currentIndex].duration * _animController.value;
  }

  Future<void> _startCurrentStory() async {
    final token = ++_loadToken;

    final previous = _video;
    _video = null;
    previous?.removeListener(_onVideoTick);
    unawaited(previous?.dispose());

    // The fallback runs from the first frame, and is stopped below if the
    // clip turns out to be playable.
    _animController.duration = widget.reviews[_currentIndex].duration;
    _animController.reset();
    if (_isPlaying) {
      _animController.forward();
    }
    if (mounted) {
      setState(() {});
    }

    final controller = _controllerFor(widget.reviews[_currentIndex].video);
    try {
      await controller.initialize();
    } catch (error) {
      debugPrint(
        'SHIELD: review clip failed — '
        '${widget.reviews[_currentIndex].video}: $error',
      );
      await controller.dispose();
      return;
    }

    if (!mounted || token != _loadToken) {
      await controller.dispose();
      return;
    }

    _animController.stop();
    await controller.setVolume(_isMuted ? 0 : 1);
    controller.addListener(_onVideoTick);
    if (_isPlaying) {
      await _playOrFallBackToMuted(controller);
    }

    if (!mounted || token != _loadToken) {
      controller.removeListener(_onVideoTick);
      await controller.dispose();
      return;
    }
    setState(() => _video = controller);
  }

  /// Starts [controller], dropping to silent playback if sound is refused.
  ///
  /// A browser will not let a page start an unmuted video unless it is sure a
  /// person asked for it, and the tap that opened this player is a moment
  /// behind us by the time the clip has finished loading. Refused, the review
  /// would sit frozen on its first frame — so it plays silently instead, and
  /// the mute button, which is a tap of its own, turns the sound on.
  Future<void> _playOrFallBackToMuted(VideoPlayerController controller) async {
    try {
      await controller.play();
      return;
    } catch (_) {
      // Fall through and try again without sound.
    }

    try {
      await controller.setVolume(0);
      await controller.play();
      if (mounted) {
        setState(() => _isMuted = true);
      }
    } catch (_) {
      // Nothing more to try: the controls are still live, and the fallback
      // progress bar keeps the story moving.
    }
  }

  void _onVideoTick() {
    final player = _video;
    if (player == null || !mounted) {
      return;
    }
    final value = player.value;
    if (value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration) {
      _onStoryFinished();
      return;
    }
    setState(() {});
  }

  void _onStoryFinished() {
    if (_currentIndex < widget.reviews.length - 1) {
      setState(() => _currentIndex++);
      _startCurrentStory();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _goToPrevious() {
    // A quarter of the way in, the tap means "start this one again" rather
    // than "go back", which is how every story player behaves.
    if (_progress > 0.25 || _currentIndex == 0) {
      _startCurrentStory();
    } else {
      setState(() => _currentIndex--);
      _startCurrentStory();
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.reviews.length - 1) {
      setState(() => _currentIndex++);
      _startCurrentStory();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _resume();
      } else {
        _pause();
      }
    });
  }

  void _pause() {
    _animController.stop();
    unawaited(_video?.pause());
  }

  void _resume() {
    final player = _video;
    if (player != null && player.value.isInitialized) {
      unawaited(_playOrFallBackToMuted(player));
    } else {
      _animController.forward();
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      unawaited(_video?.setVolume(_isMuted ? 0 : 1));
    });
  }

  void _seekTo(double value) {
    final fraction = value.clamp(0.0, 1.0);
    setState(() {
      _animController.value = fraction;
      final player = _video;
      if (player != null && player.value.isInitialized) {
        unawaited(player.seekTo(player.value.duration * fraction));
      }
    });
  }

  @override
  void dispose() {
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    _animController.dispose();
    super.dispose();
  }

  String _formatTime(Duration position) {
    final seconds = position.inSeconds;
    final mins = seconds ~/ 60;
    final remSecs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${remSecs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final currentReview = widget.reviews[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 300) {
              Navigator.of(context).pop();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The clip itself.
              Center(
                child: _ReviewVideoSurface(
                  controller: _video,
                  thumbnail: currentReview.thumbnail,
                  placeholder: Colors.black,
                ),
              ),

              // Gradient overlays for crisp contrast on text and controls
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.70),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.0, 0.30, 1.0],
                    ),
                  ),
                ),
              ),

              // Tap zones: left to go back, right to go next, hold to pause
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _goToPrevious,
                        onLongPressStart: (_) {
                          if (_isPlaying) _pause();
                        },
                        onLongPressEnd: (_) {
                          if (_isPlaying) _resume();
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _goToNext,
                        onLongPressStart: (_) {
                          if (_isPlaying) _pause();
                        },
                        onLongPressEnd: (_) {
                          if (_isPlaying) _resume();
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),

              // Subtitles / captions, centre-bottom.
              if (currentReview.subtitle != null)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 96,
                  child: IgnorePointer(
                    child: Text(
                      currentReview.subtitle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Top Section: Story Progress Indicators & Header Row
              Positioned(
                top: 10,
                left: 12,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Segmented Progress Bars
                    Row(
                      children: List.generate(widget.reviews.length, (index) {
                        return Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                double fillFraction = 0.0;
                                if (index < _currentIndex) {
                                  fillFraction = 1.0;
                                } else if (index == _currentIndex) {
                                  fillFraction = _progress;
                                }
                                return Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    width: constraints.maxWidth * fillFraction,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),

                    // Header Row: Reviewer name on left, Close icon on right
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            currentReview.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Bottom control bar: play/pause, scrubber, clock, mute.
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        onPressed: _togglePlayPause,
                      ),

                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white30,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: _progress,
                            onChanged: (val) {
                              _pause();
                              _seekTo(val);
                            },
                            onChangeEnd: (val) {
                              if (_isPlaying) {
                                _resume();
                              }
                            },
                          ),
                        ),
                      ),

                      Text(
                        _formatTime(_position),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),

                      IconButton(
                        icon: Icon(
                          _isMuted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: _toggleMute,
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
