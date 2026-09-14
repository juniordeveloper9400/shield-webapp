import 'package:flutter/foundation.dart';

import 'backend_http.dart';

/// One row of the home hero carousel, exactly as the admin console left it
/// (device image upload, base64 in [image]) — from
/// `GET /v1/public/catalogue/banners` (`catalogue.service.ts`'s
/// `listBanners`).
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
      sort: row['sort'] is int ? row['sort'] as int : int.tryParse(str(row['sort'])) ?? 0,
    );
  }
}

/// Reads the home-screen hero banner from `backend/api`'s public catalogue
/// route, maintained from the admin console (`shieldweb`).
///
/// Read-only and best-effort like the other backend repositories: an
/// unconfigured backend or a network failure returns an empty list rather
/// than throwing, so [HomeHeroBanner] falls back to the bundled default
/// banner instead of showing an error where a promotion belongs.
class HomeBannerRepository {
  const HomeBannerRepository._();

  static const HomeBannerRepository instance = HomeBannerRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  /// Every banner the admin has switched on, in display order. Rows with no
  /// image (should not happen — the console requires one) are dropped rather
  /// than shown as a blank slide.
  Future<List<HomeBannerModel>> listActive() async {
    if (!BackendHttp.isConfigured) {
      return const [];
    }
    try {
      final rows = await BackendHttp.instance.request(
        'GET',
        '/v1/public/catalogue/banners',
        auth: false,
      ) as List<dynamic>;
      return rows
          .cast<Map<String, dynamic>>()
          .map(HomeBannerModel.fromRow)
          .where((banner) => banner.image.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      BackendHttp.log('HomeBannerRepository.listActive failed', error: error);
      return const [];
    }
  }
}
