import 'package:flutter/material.dart';

import '../module/agent/agent_portal_card.dart';
import '../module/agent/agent_service.dart';
import '../module/auth/auth_service.dart';
import '../module/cart/cart_badge.dart';
import '../module/cart/cart_bar.dart';
import '../module/cart/cart_service.dart';
import '../theme/app_colors.dart';
import '../module/home/brand_quote.dart';
import '../module/home/category_section.dart';
import '../module/home/customer_reviews.dart';
import '../module/home/customer_testimonials.dart';
import '../module/home/earnings_section.dart';
import '../module/home/health_articles.dart';
import '../module/home/home_header.dart';
import '../module/home/home_hero_banner.dart';
import '../module/home/prescription_card.dart';
import '../module/catalogue/catalogue_service.dart';
import '../module/home/product_showcase.dart';
import '../module/home/refer_earn_card.dart';
import '../module/investor/investor_access_card.dart';
import '../module/investor/investor_service.dart';
import '../module/privilege/privilege_card.dart';
import '../module/search/search_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.pageTint,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                // Collapses on scroll down to the search field and the cart.
                const SliverPersistentHeader(
                  pinned: true,
                  delegate: _CollapsingTopChrome(),
                ),

                SliverList(
                  delegate: SliverChildListDelegate([
                    const HomeHeroBanner(),
                    const PrivilegeCard(),
                    // Directly under the privilege card, because half of what
                    // it totals is the bonus that card pays — and above Refer
                    // & Earn, which is where the other half comes from and the
                    // obvious next tap once the total has been read.
                    const EarningsSection(),
                    // Refer & Earn for a member; the Agent Portal in its place
                    // once a known agent number is signed in.
                    ValueListenableBuilder<AuthUser?>(
                      valueListenable: AuthService.instance.currentUser,
                      builder: (context, user, _) {
                        final agent = AgentService.instance.agentForPhone(
                          user?.phone,
                        );
                        return agent == null
                            ? const ReferEarnCard()
                            : AgentPortalCard(agent: agent);
                      },
                    ),
                    // Alongside whichever of those just showed, never in its
                    // place — an investor number is its own thing, not a
                    // stand-in for being a member or an agent. Not a general
                    // invitation to everyone else either: this section is
                    // only ever for the one recognised investor number.
                    ValueListenableBuilder<AuthUser?>(
                      valueListenable: AuthService.instance.currentUser,
                      builder: (context, user, _) {
                        final investor = InvestorService.instance
                            .investorForPhone(user?.phone);
                        return investor == null
                            ? const SizedBox.shrink()
                            : InvestorAccessCard(investor: investor);
                      },
                    ),

                    // Directly under Refer & Earn, with no banner between them.
                    Container(
                      color: AppColors.white,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.textDark.withValues(alpha: 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const PrescriptionCard(),
                      ),
                    ),
                    const CustomerReviews(),
                    const CategorySection(),
                    const _HomeProductRows(),
                    const HealthArticlesSection(),
                    const CustomerTestimonials(),
                    const BrandQuote(),
                    // Clears the floating cart bar so the sign-off stays
                    // readable once a basket has been started from the feed.
                    ListenableBuilder(
                      listenable: CartService.instance,
                      builder: (context, _) => SizedBox(
                        height: CartService.instance.itemCount > 0 ? 92 : 0,
                      ),
                    ),
                  ]),
                ),
              ],
            ),
            // Slides up from behind the bottom nav the moment the product
            // cart has anything in it, from the feed or anywhere else.
            const Positioned(left: 0, right: 0, bottom: 0, child: CartBar()),
          ],
        ),
      ),
    );
  }
}

/// The look of a live search field, but not one — tapping it (the box, the
/// icon, the hint, anywhere) opens [SearchScreen], where the actual query box
/// lives. `readOnly` keeps the keyboard from popping up over the feed for a
/// field that is about to be left anyway; `onTap` still fires on a read-only
/// field, so the tap is never lost.
class _SearchField extends StatelessWidget {
  const _SearchField();

  void _openSearch(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      readOnly: true,
      showCursor: false,
      onTap: () => _openSearch(context),
      decoration: InputDecoration(
        hintText: 'Search for medicine',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 16),
        // A plain icon, not a button: it is bare paint with no gesture
        // handling of its own, so a tap on it falls straight through to the
        // field's own `onTap` rather than being swallowed by a second control
        // — and the field keeps the exact size and position it always had.
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.brandBlue,
          size: 24,
        ),
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.searchBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.6),
        ),
      ),
    );
  }
}

/// Fully expanded height: header row, location line, and the search field.
const double _chromeMaxExtent = 158;

/// Collapsed height: the search field, with [_chromeTopPad] of clear space
/// above and below it.
const double _chromeMinExtent = 74;

/// Breathing room above the top row, in both states. The collapsed bar sits
/// this far down from the top edge rather than flush against it.
const double _chromeTopPad = 12;

const double _searchExpandedTop = 94;

/// Collapsed, the search sits this far down from the top edge.
const double _searchCollapsedTop = _chromeTopPad;

/// Gap between the collapsed search field and the cart beside it.
const double _cartGap = 10;

/// Names the cart that rides the collapsed search bar, so it can be told
/// apart from the header's own — both are a [CartBadge] on the same basket.
const Key pinnedCartKey = ValueKey('home-pinned-cart');

/// Pins the top chrome and collapses it as the feed scrolls.
///
/// The header and location fade away as the search field rises into the
/// pinned bar. The header carries the products cart, so a second one fades in
/// beside the search field as the first one goes — the cart a member is
/// filling from the feed never scrolls off the screen, and the two are never
/// drawn at once.
class _CollapsingTopChrome extends SliverPersistentHeaderDelegate {
  const _CollapsingTopChrome();

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);

    final searchTop =
        _searchExpandedTop + (_searchCollapsedTop - _searchExpandedTop) * t;
    return Material(
      color: AppColors.pageTint,
      elevation: overlapsContent ? 2 : 0,
      shadowColor: AppColors.textDark.withValues(alpha: 0.18),
      child: SizedBox.expand(
        child: ClipRect(
          child: Stack(
            children: [
              // Menu, wordmark, wallet and location: fade out on the way down.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: t > 0.5,
                  child: Opacity(
                    opacity: 1 - t,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(12, _chromeTopPad, 0, 0),
                      child: HomeHeader(),
                    ),
                  ),
                ),
              ),

              Positioned(
                top: searchTop,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    const Expanded(child: _SearchField()),
                    // Takes up no width at all while the header's own cart is
                    // still on screen, so the search field runs the full width
                    // expanded and gives the gap back as the cart arrives.
                    ClipRect(
                      child: Align(
                        alignment: Alignment.centerRight,
                        widthFactor: t,
                        child: IgnorePointer(
                          ignoring: t < 0.5,
                          child: Opacity(
                            opacity: t,
                            child: const Padding(
                              padding: EdgeInsets.only(left: _cartGap),
                              child: CartBadge(key: pinnedCartKey),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  double get maxExtent => _chromeMaxExtent;

  @override
  double get minExtent => _chromeMinExtent;

  @override
  bool shouldRebuild(covariant _CollapsingTopChrome oldDelegate) => false;
}

/// The three product rows on the feed — "Popular Items", "Deals You Love" and
/// "Wellness & Supplements" — built from the live catalogue ([CatalogueService])
/// rather than a fixed list. While the first load is in flight a light
/// placeholder holds the space; if the catalogue is empty or unreachable the
/// rows drop out of the feed entirely rather than showing a broken shelf.
class _HomeProductRows extends StatefulWidget {
  const _HomeProductRows();

  @override
  State<_HomeProductRows> createState() => _HomeProductRowsState();
}

class _HomeProductRowsState extends State<_HomeProductRows> {
  @override
  void initState() {
    super.initState();
    CatalogueService.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CatalogueService.instance,
      builder: (context, _) {
        final catalogue = CatalogueService.instance;

        if (!catalogue.hasProducts) {
          return catalogue.isLoading
              ? const _ProductRowsPlaceholder()
              : const SizedBox.shrink();
        }

        return Column(
          children: [
            if (catalogue.popularPicks.isNotEmpty)
              ProductShowcase(
                title: 'Popular Items',
                subtitle: 'Freshly added at the pharmacy',
                products: catalogue.popularPicks,
              ),
            if (catalogue.dealsYouLove.isNotEmpty)
              ProductShowcase(
                title: 'Deals You Love',
                subtitle: 'Big savings & special discounts',
                products: catalogue.dealsYouLove,
              ),
            if (catalogue.wellness.isNotEmpty)
              ProductShowcase(
                title: 'Wellness & Supplements',
                subtitle: 'Supplements and daily nutrition',
                products: catalogue.wellness,
              ),
          ],
        );
      },
    );
  }
}

/// A single greyed-out row that holds the feed's shape while the catalogue
/// loads, so the sections below it do not jump up and then back down.
class _ProductRowsPlaceholder extends StatelessWidget {
  const _ProductRowsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 160,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.pageTint,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) => Container(
                width: 162,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
