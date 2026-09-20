import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:shield/module/home/customer_reviews.dart';
import 'package:shield/module/home/customer_reviews_service.dart';
import 'package:shield/module/home/review_video_player_screen.dart';

/// A stand-in for the platform video player, so the review viewer's
/// `VideoPlayerController` can run under `flutter_test` (which has no real
/// video backend) — and so a test can see exactly which clip URLs were opened,
/// what was played, and push playback events in.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform
    with MockPlatformInterfaceMixin {
  final Map<int, StreamController<VideoEvent>> streams = {};
  final Map<int, String> urls = {};

  /// URLs in the order they were opened.
  final List<String> opened = [];
  final List<int> disposed = [];
  final List<String> calls = [];

  /// URLs that should fail to load instead of initializing.
  final Set<String> failing = {};
  int _nextId = 1;

  int idFor(String url) =>
      urls.entries.lastWhere((entry) => entry.value == url).key;

  void emit(String url, VideoEvent event) => streams[idFor(url)]!.add(event);

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    await streams.remove(playerId)?.close();
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextId++;
    final url = options.dataSource.uri ?? '';
    final controller = StreamController<VideoEvent>();
    streams[id] = controller;
    urls[id] = url;
    opened.add(url);
    if (failing.contains(url)) {
      controller.addError(
        PlatformException(
          code: 'load-failed',
          message: 'Could not load the video',
        ),
      );
    } else {
      controller.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          size: const Size(720, 1280),
          duration: const Duration(seconds: 10),
        ),
      );
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async => calls.add('play:$playerId');

  @override
  Future<void> pause(int playerId) async => calls.add('pause:$playerId');

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      calls.add('volume:$playerId:$volume');

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      calls.add('seek:$playerId:${position.inMilliseconds}');

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      SizedBox(key: ValueKey('fake-video-${options.playerId}'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const clipA = CustomerReviewItem(
    id: 'a',
    name: 'Melattur',
    video: 'https://media.example.com/review-videos/a.mp4',
    subtitle: 'Loved the service',
  );
  const clipB = CustomerReviewItem(
    id: 'b',
    name: 'Tirur',
    video: 'https://media.example.com/review-videos/b.mp4',
  );
  const clipC = CustomerReviewItem(
    id: 'c',
    name: 'Vengara',
    video: 'https://media.example.com/review-videos/c.webm',
  );

  late _FakeVideoPlayerPlatform video;

  setUp(() {
    video = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = video;
    CustomerReviewsService.instance.debugReset();
  });
  tearDown(() => CustomerReviewsService.instance.debugReset());

  Future<void> pumpReviews(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: CustomerReviews())),
      ),
    );
    await tester.pumpAndSettle();
    // Whatever a test leaves open must not leave the fake player's periodic
    // position timer running past the end of the test.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  /// Lets the viewer's async work — creating the player, initializing it,
  /// starting playback — run to completion. Not `pumpAndSettle`: a playing
  /// video keeps a periodic timer going, which never "settles".
  Future<void> pumpViewer(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The controller releases its native player asynchronously, after the
  /// widget that owned it is gone — give that a moment to land.
  Future<void> letPlayersRelease(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }

  Future<void> openFirst(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pump(); // start the dialog route
    await pumpViewer(tester);
  }

  group('isPlayableReviewVideo', () {
    test('accepts a hosted http(s) video, whatever its extension', () {
      for (final url in [
        'https://media.example.com/review-videos/a.mp4',
        'https://pub-abc123.r2.dev/review-videos/b.webm',
        'http://cdn.example.com/c.mov',
        '  https://media.example.com/review-videos/a.mp4  ',
      ]) {
        expect(isPlayableReviewVideo(url), isTrue, reason: url);
      }
    });

    test('rejects YouTube links, bundled asset paths and junk', () {
      for (final url in [
        'https://www.youtube.com/shorts/dvLRFi4zBWk?feature=share',
        'https://youtu.be/aqz-KE-bpKQ',
        'https://m.youtube.com/watch?v=aqz-KE-bpKQ',
        'assets/reviews/tirur_store.mp4',
        'file:///sdcard/clip.mp4',
        'not a url at all',
        '',
      ]) {
        expect(isPlayableReviewVideo(url), isFalse, reason: url);
      }
    });
  });

  group('CustomerReviewsService', () {
    test('only exposes clips the player can stream', () {
      const youtube = CustomerReviewItem(
        id: 'yt',
        name: 'Old row',
        video: 'https://www.youtube.com/shorts/dvLRFi4zBWk',
      );
      const bundled = CustomerReviewItem(
        id: 'asset',
        name: 'Bundled',
        video: 'assets/reviews/tirur_store.mp4',
      );
      CustomerReviewsService.instance.debugSeed([
        youtube,
        clipA,
        bundled,
        clipB,
      ]);

      expect(CustomerReviewsService.instance.items.map((c) => c.id), [
        'a',
        'b',
      ]);
      expect(
        CustomerReviewsService.instance.status,
        CustomerReviewsStatus.ready,
      );
    });

    test('is empty, not ready, when every row is an old unplayable one', () {
      CustomerReviewsService.instance.debugSeed(const [
        CustomerReviewItem(
          id: 'yt',
          name: 'Old row',
          video: 'https://youtu.be/aqz-KE-bpKQ',
        ),
      ]);
      expect(CustomerReviewsService.instance.items, isEmpty);
      expect(
        CustomerReviewsService.instance.status,
        CustomerReviewsStatus.empty,
      );
    });
  });

  group('the reel', () {
    testWidgets('renders nothing while the admin has added no clips', (
      tester,
    ) async {
      CustomerReviewsService.instance.debugSeed(const []);
      await pumpReviews(tester);

      expect(find.text('What our customers have to say'), findsNothing);
      expect(find.byType(CustomerReviews), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a card per uploaded clip, and none for an old one', (
      tester,
    ) async {
      CustomerReviewsService.instance.debugSeed(const [
        clipA,
        clipB,
        CustomerReviewItem(
          id: 'yt',
          name: 'YouTube leftover',
          video: 'https://www.youtube.com/shorts/dvLRFi4zBWk',
        ),
      ]);
      await pumpReviews(tester);

      expect(find.text('What our customers have to say'), findsOneWidget);
      expect(find.text(clipA.name), findsOneWidget);
      expect(find.text(clipB.name), findsOneWidget);
      expect(find.text('YouTube leftover'), findsNothing);
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsNWidgets(2));
    });

    testWidgets('drawing the reel never opens a video', (tester) async {
      CustomerReviewsService.instance.debugSeed(const [clipA, clipB]);
      await pumpReviews(tester);

      // Posters are stored images — the app must not download a video per card.
      expect(video.opened, isEmpty);
    });
  });

  group('the viewer', () {
    testWidgets('tapping a card streams that clip from its URL and plays it', (
      tester,
    ) async {
      CustomerReviewsService.instance.debugSeed(const [clipA, clipB]);
      await pumpReviews(tester);

      await openFirst(tester, clipA.name);

      expect(find.byType(ReviewVideoPlayerScreen), findsOneWidget);
      expect(video.opened, [clipA.video]);
      expect(video.calls, contains('play:${video.idFor(clipA.video)}'));
      // The title and caption show over the video.
      expect(find.text(clipA.name), findsWidgets);
      expect(find.text('Loved the service'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens on the tapped card, not the first one', (tester) async {
      CustomerReviewsService.instance.debugSeed(const [clipA, clipB, clipC]);
      await pumpReviews(tester);

      await tester.tap(find.text(clipB.name));
      await tester.pump();
      await pumpViewer(tester);

      expect(video.opened, [clipB.video]);
    });

    testWidgets('is an overlay — the feed stays under it, and close dismisses '
        'it and releases the player', (tester) async {
      CustomerReviewsService.instance.debugSeed(const [clipA]);
      await pumpReviews(tester);
      await openFirst(tester, clipA.name);

      expect(find.byType(CustomerReviews), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      final playerId = video.idFor(clipA.video);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await letPlayersRelease(tester);

      expect(find.byType(ReviewVideoPlayerScreen), findsNothing);
      expect(find.byType(CustomerReviews), findsOneWidget);
      expect(video.disposed, contains(playerId));
    });

    testWidgets('tapping the right side moves to the next clip and releases '
        'the one it left', (tester) async {
      CustomerReviewsService.instance.debugSeed(const [clipA, clipB]);
      await pumpReviews(tester);
      await openFirst(tester, clipA.name);
      final first = video.idFor(clipA.video);

      final size = tester.view.physicalSize;
      await tester.tapAt(Offset(size.width * 0.9, size.height * 0.5));
      await pumpViewer(tester);

      await letPlayersRelease(tester);
      expect(video.opened, [clipA.video, clipB.video]);
      expect(video.disposed, contains(first));
      expect(find.text(clipB.name), findsWidgets);
    });

    testWidgets('tapping the middle pauses, and again resumes', (tester) async {
      CustomerReviewsService.instance.debugSeed(const [clipA]);
      await pumpReviews(tester);
      await openFirst(tester, clipA.name);
      final id = video.idFor(clipA.video);

      final size = tester.view.physicalSize;
      final middle = Offset(size.width * 0.5, size.height * 0.5);
      await tester.tapAt(middle);
      await pumpViewer(tester);
      expect(video.calls, contains('pause:$id'));

      video.calls.clear();
      await tester.tapAt(middle);
      await pumpViewer(tester);
      expect(video.calls, contains('play:$id'));
    });

    testWidgets('the mute button turns the sound off and on', (tester) async {
      CustomerReviewsService.instance.debugSeed(const [clipA]);
      await pumpReviews(tester);
      await openFirst(tester, clipA.name);
      final id = video.idFor(clipA.video);

      await tester.tap(find.byIcon(Icons.volume_up_rounded));
      await pumpViewer(tester);
      expect(video.calls, contains('volume:$id:0.0'));
      expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.volume_off_rounded));
      await pumpViewer(tester);
      expect(video.calls.last, 'volume:$id:1.0');
    });

    testWidgets('a finished clip moves on by itself, and the last one closes '
        'the viewer', (tester) async {
      CustomerReviewsService.instance.debugSeed(const [clipA, clipB]);
      await pumpReviews(tester);
      await openFirst(tester, clipA.name);

      video.emit(clipA.video, VideoEvent(eventType: VideoEventType.completed));
      await pumpViewer(tester);
      expect(video.opened, [clipA.video, clipB.video]);
      expect(find.byType(ReviewVideoPlayerScreen), findsOneWidget);

      video.emit(clipB.video, VideoEvent(eventType: VideoEventType.completed));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewVideoPlayerScreen), findsNothing);
    });

    testWidgets('a clip that will not load says so and can be retried, without '
        'losing the rest of the reel', (tester) async {
      video.failing.add(clipA.video);
      CustomerReviewsService.instance.debugSeed(const [clipA, clipB]);
      await pumpReviews(tester);
      await openFirst(tester, clipA.name);

      expect(find.text('This video couldn’t be played.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      // The connection comes back; retrying streams it.
      video.failing.clear();
      await tester.tap(find.text('Try again'));
      await pumpViewer(tester);
      expect(find.text('This video couldn’t be played.'), findsNothing);
      expect(video.opened, [clipA.video, clipA.video]);
      expect(video.calls, contains('play:${video.idFor(clipA.video)}'));
    });
  });
}
