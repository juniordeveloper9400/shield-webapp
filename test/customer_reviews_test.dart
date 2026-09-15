import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:shield/module/home/customer_reviews.dart';
import 'package:shield/module/home/customer_reviews_service.dart';
import 'package:shield/module/home/review_video_player_screen.dart';

/// A no-op `webview_flutter` platform, registered below so
/// `YoutubePlayerController`/`YoutubePlayer` can build under `flutter_test`
/// — which has no real WebView — instead of throwing on
/// `WebViewPlatform.instance == null`.
class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _FakeWebViewController(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _FakeNavigationDelegate(params);
}

/// Every method a no-op success rather than the base class's default
/// `UnimplementedError`, since `YoutubePlayerController` calls a handful of
/// these synchronously while it sets itself up.
class _FakeWebViewController extends PlatformWebViewController {
  _FakeWebViewController(super.params) : super.implementation();

  @override
  Future<void> loadFile(String absoluteFilePath) async {}
  @override
  Future<void> loadFileWithParams(LoadFileParams params) async {}
  @override
  Future<void> loadFlutterAsset(String key) async {}
  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {}
  @override
  Future<String?> currentUrl() async => null;
  @override
  Future<bool> canGoBack() async => false;
  @override
  Future<bool> canGoForward() async => false;
  @override
  Future<void> goBack() async {}
  @override
  Future<void> goForward() async {}
  @override
  Future<void> reload() async {}
  @override
  Future<void> clearCache() async {}
  @override
  Future<void> clearLocalStorage() async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    covariant PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> runJavaScript(String javaScript) async {}
  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async => '';
  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    // Real YouTube posts a `{"playerId": ..., "Ready": ...}` message back
    // over this channel once the iframe loads, which is what lets
    // `YoutubePlayerController` complete its internal "ready" wait. With no
    // real page here to post it, echo one back immediately — otherwise that
    // wait times out after 30 (fake-clock) seconds, via a `Timer` that's
    // still pending — and fails `flutter_test`'s teardown check — for every
    // test in this file, not just the one that triggered it.
    javaScriptChannelParams.onMessageReceived(
      JavaScriptMessage(
        message: jsonEncode({'playerId': javaScriptChannelParams.name, 'Ready': true}),
      ),
    );
  }
  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {}
  @override
  Future<String?> getTitle() async => null;
  @override
  Future<void> scrollTo(int x, int y) async {}
  @override
  Future<void> scrollBy(int x, int y) async {}
  @override
  Future<void> setVerticalScrollBarEnabled(bool enabled) async {}
  @override
  Future<void> setHorizontalScrollBarEnabled(bool enabled) async {}
  @override
  Future<void> enableZoom(bool enabled) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}
  @override
  Future<void> setUserAgent(String? userAgent) async {}
  @override
  Future<String?> getUserAgent() async => null;
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}
  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {}
  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}
  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}
  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}
  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WebViewPlatform.instance = _FakeWebViewPlatform();

  const youtubeReview = CustomerReviewItem(
    id: 'yt-1',
    name: 'Melattur',
    video: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
    subtitle: 'Loved the service',
  );
  const secondReview = CustomerReviewItem(
    id: 'yt-2',
    name: 'Tirur',
    video: 'https://youtu.be/dQw4w9WgXcQ',
  );

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
  }

  setUp(() => CustomerReviewsService.instance.debugReset());
  tearDown(() => CustomerReviewsService.instance.debugReset());

  group('youtubeId', () {
    test('reads every URL shape the admin might paste', () {
      const cases = {
        'https://www.youtube.com/watch?v=aqz-KE-bpKQ': 'aqz-KE-bpKQ',
        'https://youtube.com/watch?v=aqz-KE-bpKQ&t=42s': 'aqz-KE-bpKQ',
        'https://m.youtube.com/watch?v=aqz-KE-bpKQ': 'aqz-KE-bpKQ',
        'https://youtu.be/aqz-KE-bpKQ': 'aqz-KE-bpKQ',
        'https://youtu.be/aqz-KE-bpKQ?t=5': 'aqz-KE-bpKQ',
        'https://www.youtube.com/embed/aqz-KE-bpKQ': 'aqz-KE-bpKQ',
        'https://www.youtube.com/shorts/aqz-KE-bpKQ': 'aqz-KE-bpKQ',
      };
      cases.forEach((url, id) {
        final review = CustomerReviewItem(id: 't', name: 't', video: url);
        expect(review.youtubeId, id, reason: url);
      });
    });

    test('is null for anything that is not a YouTube link', () {
      const notYoutube = [
        'https://cdn.example.com/reviews/clip.mp4',
        'https://firebasestorage.googleapis.com/v0/b/x/o/clip.mp4',
        'not a url at all',
      ];
      for (final video in notYoutube) {
        final review = CustomerReviewItem(id: 't', name: 't', video: video);
        expect(review.youtubeId, isNull, reason: video);
      }
    });
  });

  group('displayThumbnail', () {
    test('falls back to YouTube\'s own poster', () {
      const withoutCustom = CustomerReviewItem(
        id: 't',
        name: 't',
        video: 'https://youtu.be/aqz-KE-bpKQ',
      );
      expect(
        withoutCustom.displayThumbnail,
        'https://img.youtube.com/vi/aqz-KE-bpKQ/hqdefault.jpg',
      );
    });

    test('an admin thumbnail wins over the YouTube one', () {
      const withCustom = CustomerReviewItem(
        id: 't',
        name: 't',
        video: 'https://youtu.be/aqz-KE-bpKQ',
        thumbnail: 'https://example.com/custom.jpg',
      );
      expect(withCustom.displayThumbnail, 'https://example.com/custom.jpg');
    });

    test('is null for a link with no YouTube id', () {
      const notYoutube = CustomerReviewItem(
        id: 't',
        name: 't',
        video: 'https://cdn.example.com/clip.mp4',
      );
      expect(notYoutube.displayThumbnail, isNull);
    });
  });

  testWidgets('renders nothing while the admin has added no clips', (
    tester,
  ) async {
    CustomerReviewsService.instance.debugSeed(const []);
    await pumpReviews(tester);

    expect(find.text('What our customers have to say'), findsNothing);
    expect(find.byType(CustomerReviews), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a card per admin-added clip', (tester) async {
    CustomerReviewsService.instance.debugSeed([youtubeReview, secondReview]);
    await pumpReviews(tester);

    expect(find.text('What our customers have to say'), findsOneWidget);
    expect(find.text(youtubeReview.name), findsOneWidget);
    expect(find.text(secondReview.name), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsNWidgets(2));
  });

  testWidgets('tapping a card opens the YouTube player screen', (
    tester,
  ) async {
    CustomerReviewsService.instance.debugSeed([youtubeReview]);
    await pumpReviews(tester);

    await tester.tap(find.text(youtubeReview.name));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewVideoPlayerScreen), findsOneWidget);
    final screen = tester.widget<ReviewVideoPlayerScreen>(
      find.byType(ReviewVideoPlayerScreen),
    );
    expect(screen.videoId, 'aqz-KE-bpKQ');
    expect(screen.title, youtubeReview.name);
    expect(screen.description, youtubeReview.subtitle);
  });

  testWidgets('a card with no YouTube id does nothing when tapped', (
    tester,
  ) async {
    const badRow = CustomerReviewItem(
      id: 'bad',
      name: 'Old row',
      video: 'https://cdn.example.com/clip.mp4',
    );
    CustomerReviewsService.instance.debugSeed([badRow]);
    await pumpReviews(tester);

    await tester.tap(find.text(badRow.name));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewVideoPlayerScreen), findsNothing);
    expect(find.byType(CustomerReviews), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
