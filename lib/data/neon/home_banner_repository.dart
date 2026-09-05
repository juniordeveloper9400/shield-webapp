import 'package:flutter/foundation.dart';

import 'neon_http.dart';

/// One row of `app.home_banner` — a slide of the home hero carousel, exactly
/// as the admin console left it (device image upload, base64 in [image]).
@immutable
class HomeBannerModel {
  final String id;
  final String title;
  final String subtitle;
  final String image;
  final String cta;
  final String target;
  final int sort;

  const HomeBannerModel({
    required this.id,
    required this.image,
    this.title = '',
    this.subtitle = '',
    this.cta = '',
    this.target = '',
    this.sort = 0,
  });

  factory HomeBannerModel.fromRow(Map<String, dynamic> row) {
    String str(Object? v) => (v ?? '').toString().trim();
    return HomeBannerModel(
      id: str(row['id']),
      title: str(row['title']),
      subtitle: str(row['subtitle']),
      image: str(row['image']),
      cta: str(row['cta']),
      target: str(row['target']),
      sort: int.tryParse(str(row['sort'])) ?? 0,
    );
  }
}

/// Reads the home-screen hero banner — `app.home_banner`, maintained from the
/// admin console (`shieldweb`) — from Neon over the HTTP SQL endpoint.
///
/// Read-only and best-effort like the other Neon repositories: a missing
/// `DATABASE_URL` or a network failure returns an empty list rather than
/// throwing, so [HomeHeroBanner] falls back to the bundled default banner
/// instead of showing an error where a promotion belongs.
class HomeBannerRepository {
  const HomeBannerRepository._();

  static const HomeBannerRepository instance = HomeBannerRepository._();

  bool get isAvailable => NeonHttp.isConfigured;

  /// Every banner the admin has switched on, in display order. Rows with no
  /// image (should not happen — the console requires one) are dropped rather
  /// than shown as a blank slide.
  Future<List<HomeBannerModel>> listActive() async {
    if (!NeonHttp.isConfigured) {
      return const [];
    }
    try {
      final rows = await NeonHttp.instance.query(r'''
        SELECT id, title, subtitle, image, cta, target, sort
        FROM app.home_banner
        WHERE is_active
        ORDER BY sort, id
      ''');
      return rows
          .map(HomeBannerModel.fromRow)
          .where((banner) => banner.image.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      NeonHttp.log('HomeBannerRepository.listActive failed', error: error);
      return const [];
    }
  }
}
