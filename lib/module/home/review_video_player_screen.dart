import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'customer_reviews.dart';

/// Opens the review clips as a full-screen viewer over the current page — the
/// home feed stays underneath and comes back on close, rather than the video
/// navigating to a page of its own. Starts on [reviews]`[initialIndex]`; the
/// viewer can move through the rest of the reel from there.
Future<void> showReviewVideo(
  BuildContext context, {
  required List<CustomerReviewItem> reviews,
  int initialIndex = 0,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    useSafeArea: false,
    builder: (_) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: ReviewVideoPlayerScreen(
        reviews: reviews,
        initialIndex: initialIndex,
      ),
    ),
  );
}

/// The full-screen viewer for the customer review reel.
///
/// Plays each clip straight from its storage URL with the platform's own
/// video player, so it works the same on Android, iOS and the web build:
///
///  * tap the left / right side of the video for the previous / next clip,
///    the middle to pause or resume; swipe sideways to move between clips and
///    down to close;
///  * a segment per clip along the top shows where the viewer is in the reel;
///  * a finished clip moves on to the next by itself, and the last one closes
///    the viewer;
///  * a clip that won't load says so and offers a retry, without taking the
///    rest of the reel down with it.
class ReviewVideoPlayerScreen extends StatefulWidget {
  final List<CustomerReviewItem> reviews;
  final int initialIndex;

  const ReviewVideoPlayerScreen({
    super.key,
    required this.reviews,
    this.initialIndex = 0,
  }) : assert(reviews.length > 0, 'nothing to play');

  @override
  State<ReviewVideoPlayerScreen> createState() =>
      _ReviewVideoPlayerScreenState();
}

class _ReviewVideoPlayerScreenState extends State<ReviewVideoPlayerScreen> {
  late int _index = widget.initialIndex.clamp(0, widget.reviews.length - 1);
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _muted = false;
  bool _paused = false;

  /// Bumped on every load so a slow `initialize()` that finishes after the
  /// viewer has already moved on (or closed) is thrown away, not shown.
  int _generation = 0;
  bool _finishing = false;

  CustomerReviewItem get _review => widget.reviews[_index];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _controller?.removeListener(_onTick);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final previous = _controller;
    previous?.removeListener(_onTick);
    if (mounted) {
      setState(() {
        _controller = null;
        _failed = false;
        _paused = false;
        _finishing = false;
      });
    }
    unawaited(previous?.dispose());

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(_review.video.trim()),
    );
    try {
      await controller.initialize();
    } catch (_) {
      unawaited(controller.dispose());
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
      }
      return;
    }
    if (!mounted || generation != _generation) {
      unawaited(controller.dispose());
      return;
    }
    await controller.setLooping(false);
    await controller.setVolume(_muted ? 0 : 1);
    controller.addListener(_onTick);
    setState(() => _controller = controller);
    await _play(controller);
  }

  Future<void> _play(VideoPlayerController controller) async {
    try {
      await controller.play();
    } catch (_) {
      // A browser can refuse to start a video with sound on its own; the clip
      // still plays, muted, and the viewer can turn the sound on.
      if (_muted) return;
      try {
        await controller.setVolume(0);
        if (mounted) setState(() => _muted = true);
        await controller.play();
      } catch (_) {
        if (mounted) setState(() => _failed = true);
      }
    }
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (value.hasError && !_failed) {
      setState(() => _failed = true);
      return;
    }
    if (value.isInitialized && value.isCompleted && !_finishing) {
      _finishing = true;
      _next();
    }
  }

  void _go(int index) {
    if (index >= widget.reviews.length) {
      Navigator.of(context).maybePop();
      return;
    }
    if (index < 0) {
      // Before the first clip: start it over rather than doing nothing.
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        unawaited(controller.seekTo(Duration.zero));
        unawaited(_play(controller));
        setState(() => _paused = false);
      }
      return;
    }
    if (index == _index) return;
    setState(() => _index = index);
    unawaited(_load());
  }

  void _next() => _go(_index + 1);

  void _previous() {
    // A few seconds in, "back" means "from the top"; only at the top does it
    // mean the clip before — the same convention as every story viewer.
    final controller = _controller;
    final position = controller?.value.position ?? Duration.zero;
    if (position > const Duration(seconds: 2)) {
      _go(-1);
    } else if (_index == 0) {
      _go(-1);
    } else {
      _go(_index - 1);
    }
  }

  void _togglePause() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
      setState(() => _paused = true);
    } else {
      unawaited(_play(controller));
      setState(() => _paused = false);
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    unawaited(_controller?.setVolume(_muted ? 0 : 1));
  }

  void _onTapUp(TapUpDetails details, double width) {
    final x = details.localPosition.dx;
    if (x < width / 3) {
      _previous();
    } else if (x > width * 2 / 3) {
      _next();
    } else {
      _togglePause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => _onTapUp(details, constraints.maxWidth),
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -300) _next();
          if (velocity > 300) _previous();
        },
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 400) {
            Navigator.of(context).maybePop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _buildVideo()),

            // Darkens the top and bottom so the text and controls stay
            // readable over any footage.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                    stops: const [0, 0.22, 0.65, 1],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  children: [
                    _SegmentBar(
                      count: widget.reviews.length,
                      current: _index,
                      controller: _controller,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            review.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _RoundButton(
                          icon: _muted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          tooltip: _muted ? 'Turn sound on' : 'Mute',
                          onTap: _toggleMute,
                        ),
                        const SizedBox(width: 8),
                        _RoundButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Close',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (review.subtitle != null &&
                        review.subtitle!.trim().isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          review.subtitle!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Shown while paused so a still frame reads as "paused", not "stuck".
            if (_paused)
              const IgnorePointer(
                child: Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    size: 72,
                    color: Colors.white70,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideo() {
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white70,
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                'This video couldn’t be played.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 4),
              const Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => unawaited(_load()),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (_, value, _) => value.isBuffering
              ? const CircularProgressIndicator(color: Colors.white)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// One segment per clip along the top: full for clips already watched, filling
/// for the one playing, empty for those still to come.
class _SegmentBar extends StatelessWidget {
  final int count;
  final int current;
  final VideoPlayerController? controller;

  const _SegmentBar({
    required this.count,
    required this.current,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 3,
                child: i == current && controller != null
                    ? ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: controller,
                        builder: (_, value, _) => _fill(_fraction(value)),
                      )
                    : _fill(i < current ? 1 : 0),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static double _fraction(VideoPlayerValue value) {
    final total = value.duration.inMilliseconds;
    if (!value.isInitialized || total <= 0) return 0;
    return (value.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  static Widget _fill(double fraction) => LinearProgressIndicator(
    value: fraction,
    minHeight: 3,
    backgroundColor: Colors.white30,
    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
  );
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}
