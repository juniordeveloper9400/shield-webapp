import 'package:flutter/material.dart';

import '../module/account/account_screen.dart';
import '../module/appointment/clinics_screen.dart';
import '../data/neon/patient_repository.dart';
import '../module/auth/auth_service.dart';
import '../module/health/health_section.dart';
import '../module/menu/menu_drawer.dart';
import '../module/orders/orders_screen.dart';
import '../module/patients/patient_book.dart';
import '../module/registration/register_bar.dart';
import '../widgets/app_messenger.dart';
import '../widgets/bottom_nav.dart';
import 'app_tabs.dart';
import 'home_screen.dart';

/// Holds the five primary destinations and the persistent chrome that sits
/// below them (the registration strip + bottom navigation).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Opens on Home, which now leads the bar.
  int _index = AppTab.home.index;
  HealthSubTab _healthSubTab = HealthSubTab.labsTests;

  @override
  void initState() {
    super.initState();
    // A fresh sign-in (not a session restored at launch) gets a one-time
    // greeting once the shell is on screen.
    final signedIn = AuthService.instance.consumeFreshSignIn();
    if (signedIn != null) {
      final firstName = signedIn.name.trim().split(RegExp(r'\s+')).first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showAppSnackBar(
          firstName.isEmpty ? 'Signed in' : 'Welcome, $firstName 👋',
          celebratory: true,
          icon: Icons.check_circle_outline,
        );
      });
    }

    // Pull the account's saved patients from `app.patient` — this runs on both
    // a fresh sign-in and a session restored at launch, so a reinstall or a
    // second device shows the people already on the account. A transient
    // failure returns null and leaves whatever is in memory untouched.
    final phone = AuthService.instance.currentUser.value?.phone;
    if (phone != null && phone.isNotEmpty) {
      PatientRepository.instance.listForMember(phone).then((remote) {
        if (remote != null && mounted) {
          PatientBook.instance.replaceRemote(remote);
        }
      });
    }
  }

  bool get _inHealthSection => _index == AppTab.lab.index;

  /// Switches destination, and — when the caller names a sub-tab — lands on a
  /// specific page inside the health section rather than its default one.
  void _selectTab(int index, {HealthSubTab? subTab}) {
    setState(() {
      _index = index;
      if (subTab != null) {
        _healthSubTab = subTab;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: MenuDrawer(
        onSelectTab: _selectTab,
      ),
      // IndexedStack keeps each tab's scroll position alive across switches.
      // Order must match AppTab.values.
      body: IndexedStack(
        index: _index,
        children: [
          const HomeScreen(),
          HealthSection(
            active: _healthSubTab,
            onSelectSubTab: (tab) => setState(() => _healthSubTab = tab),
          ),
          const ClinicsScreen(),
          const OrdersScreen(),
          const AccountScreen(),
        ],
      ),
      // The health section takes over the bottom bar with its own
      // sub-navigation.
      bottomNavigationBar: _inHealthSection
          ? HealthBottomBar(
              active: _healthSubTab,
              onSelectSubTab: (tab) => setState(() => _healthSubTab = tab),
              onExitToHome: () => setState(() {
                _index = AppTab.home.index;
                // Reset so re-entering the section starts at its landing page.
                _healthSubTab = HealthSubTab.labsTests;
              }),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Owns its own visibility through RegistrationService, so
                // dismissing it here and anywhere else is the one decision.
                const RegisterBar(),
                ShieldBottomNav(
                  currentIndex: _index,
                  onTap: (index) => setState(() => _index = index),
                ),
              ],
            ),
    );
  }
}
