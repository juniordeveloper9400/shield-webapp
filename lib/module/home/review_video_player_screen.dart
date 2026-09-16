import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// Opens [ReviewVideoPlayerScreen] as an overlay on top of whatever screen
/// [context] belongs to — the home feed stays put and dimmed behind it,
/// rather than the video navigating to a page of its own.
Future<void> showReviewVideo(
  BuildContext context, {
  required String videoId,
  required String title,
  String? description,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => ReviewVideoPlayerScreen(
      videoId: videoId,
      title: title,
      description: description,
    ),
  );
}

/// A customer review clip, shown as a dialog over the current page rather
/// than a page of its own — every clip is a YouTube link (see
/// `customer_reviews.dart`), played through YouTube's own embedded player
/// (native controls, fullscreen, captions), with just a close button over the
/// video to dismiss it. Open with [showReviewVideo].
class ReviewVideoPlayerScreen extends StatefulWidget {
  final String videoId;
  final String title;
  final String? description;

  const ReviewVideoPlayerScreen({
    super.key,
    required this.videoId,
    required this.title,
    this.description,
  });

  @override
  State<ReviewVideoPlayerScreen> createState() =>
      _ReviewVideoPlayerScreenState();
}

class _ReviewVideoPlayerScreenState extends State<ReviewVideoPlayerScreen> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();

    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        enableCaption: true,
        strictRelatedVideos: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 48),
      backgroundColor: Colors.black,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A slim bar right against the video, not laid over its pixels —
          // the embedded player renders through its own native/web view,
          // which can swallow taps on anything stacked directly on top of
          // it. This is still no page: no title, no back arrow, just the one
          // way to dismiss, and it never leaves the screen it opened over.
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            alignment: Alignment.centerRight,
            child: _CloseButton(onTap: () => Navigator.of(context).pop()),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: YoutubePlayer(controller: _controller),
                  ),
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.description != null) ...[
                          const SizedBox(height: 6),
                          Text(widget.description!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
