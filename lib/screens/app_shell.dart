import 'package:flutter/material.dart';

import '../module/account/account_screen.dart';
import '../module/appointment/clinics_screen.dart';
import '../data/backend/patient_repository.dart';
import '../module/auth/auth_service.dart';
import '../module/menu/menu_drawer.dart';
import '../module/orders/orders_screen.dart';
import '../module/patients/patient_book.dart';
import '../module/registration/register_bar.dart';
import '../module/registration/registration_service.dart';
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

      // Same idea for a completed registration: read it back from
      // `app.users` so the register bar shows the member's saved details
      // straight away, rather than nagging someone who already registered
      // just because this app process started with nothing in memory (a
      // fresh launch, or a log-in after another account signed out on this
      // device). See [RegistrationService.loadForSignedInMember].
      RegistrationService.instance.loadForSignedInMember(phone);
    }
  }

  void _selectTab(int index) {
    setState(() {
      _index = index;
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
          const ClinicsScreen(),
          const OrdersScreen(),
          const AccountScreen(),
        ],
      ),
      bottomNavigationBar: Column(
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
