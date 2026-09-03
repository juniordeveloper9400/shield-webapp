import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../dates.dart' as dates;
import '../rewards/rewards_service.dart';
import 'member_repository.dart';
import 'shield_store.dart';

/// How a member describes themselves. Kept short and with an opt-out, because
/// the field exists to personalise care advice, not to sort people.
enum Gender {
  female('Female'),
  male('Male'),
  other('Other');

  final String label;

  const Gender(this.label);
}

/// A completed registration: the profile behind a signed-in session.
///
/// Signing in only ever establishes a name and a verified number. Everything
/// an order actually needs — where to deliver, which branch packs it, who to
/// bill — is this.
@immutable
class Registration {
  final String name;
  final String phone;
  final String email;
  final Gender gender;
  final DateTime dob;
  final String address;
  final String place;
  final String pincode;
  final String state;

  /// The assigned branch, held by [ShieldStore.id] rather than by object so a
  /// change to the directory cannot leave a stale copy behind.
  final String storeId;

  const Registration({
    required this.name,
    required this.phone,
    required this.email,
    required this.gender,
    required this.dob,
    required this.address,
    required this.place,
    required this.pincode,
    required this.state,
    required this.storeId,
  });

  ShieldStore? get store => StoreDirectory.byId(storeId);

  /// `04 Sep 1994` — the form's display format, and the one the picker fills.
  String get dobLabel => dates.formatDate(dob);

  /// Whole years today, derived rather than stored — an age written down once
  /// is wrong from the next birthday onwards.
  int get age => dates.ageInYears(dob);

  /// `31 yrs` — what the form's date field prints beside the date.
  String get ageLabel => dates.ageLabel(dob);

  /// Full postal line, in the order an envelope reads.
  String get addressLine => '$address, $place, $state - $pincode';

  /// Kept as an entry point on the model because the form reaches for it
  /// through `Registration`; the formatting itself lives in `lib/dates.dart`,
  /// shared with the patient book.
  static String formatDate(DateTime date) => dates.formatDate(date);

  Registration copyWith({
    String? name,
    String? email,
    Gender? gender,
    DateTime? dob,
    String? address,
    String? place,
    String? pincode,
    String? state,
    String? storeId,
  }) {
    return Registration(
      name: name ?? this.name,
      phone: phone,
      email: email ?? this.email,
      gender: gender ?? this.gender,
      dob: dob ?? this.dob,
      address: address ?? this.address,
      place: place ?? this.place,
      pincode: pincode ?? this.pincode,
      state: state ?? this.state,
      storeId: storeId ?? this.storeId,
    );
  }
}

/// The registration profile, the reward it earns, and whether the member has
/// waved the prompt away.
///
/// Registration is deliberately not a gate: the form carries a close and a
/// skip, and every surface that offers it — home, account, checkout — has to
/// keep working for someone who never fills it in.
///
/// In memory only; a backend would replace this class wholesale.
class RegistrationService extends ChangeNotifier {
  RegistrationService._();

  static final RegistrationService instance = RegistrationService._();

  /// Credited once, on the first completed registration — the figure the
  /// registration screens quote. The real credit is a ledger row written by
  /// [RewardsService.awardRegistrationBonus]; this constant is only the copy.
  static const int rewardPoints = RewardsService.registrationBonus;

  /// The states and union territories the address form offers.
  static const List<String> states = [
    'Andhra Pradesh',
    'Arunachal Pradesh',
    'Assam',
    'Bihar',
    'Chhattisgarh',
    'Goa',
    'Gujarat',
    'Haryana',
    'Himachal Pradesh',
    'Jharkhand',
    'Karnataka',
    'Kerala',
    'Madhya Pradesh',
    'Maharashtra',
    'Manipur',
    'Meghalaya',
    'Mizoram',
    'Nagaland',
    'Odisha',
    'Punjab',
    'Rajasthan',
    'Sikkim',
    'Tamil Nadu',
    'Telangana',
    'Tripura',
    'Uttar Pradesh',
    'Uttarakhand',
    'West Bengal',
    'Andaman & Nicobar Islands',
    'Chandigarh',
    'Dadra & Nagar Haveli and Daman & Diu',
    'Delhi',
    'Jammu & Kashmir',
    'Ladakh',
    'Lakshadweep',
    'Puducherry',
  ];

  Registration? _profile;
  bool _promptDismissed = false;

  Registration? get profile => _profile;

  bool get isRegistered => _profile != null;

  /// True once the member has closed or skipped the form. Hides the home
  /// prompt for the session; the account entry stays, so it is never lost.
  bool get isPromptDismissed => _promptDismissed;

  /// Whether the home and checkout prompts should still be offered.
  bool get shouldPrompt => !isRegistered && !_promptDismissed;

  /// Saves the profile and, the first time only, credits the registration
  /// bonus — a later edit is not a second reward.
  ///
  /// The profile update is synchronous so the UI reacts at once; the write to
  /// `app.users` and the reward-points ledger row both go in the background.
  /// A failed or unconfigured database write is logged, never thrown —
  /// registration is an offer, not a gate, and must not break here. The
  /// [RewardsService] credit is guarded server-side, so re-saving cannot
  /// double it.
  void save(Registration registration) {
    final isFirst = _profile == null;
    _profile = registration;
    _promptDismissed = false;
    notifyListeners();
    unawaited(_persist(registration));
    if (isFirst) {
      unawaited(
        RewardsService.instance.awardRegistrationBonus(
          phone: registration.phone,
          name: registration.name,
        ),
      );
    }
  }

  /// Write-through to Neon (`app.users`). Best-effort: see [save].
  Future<void> _persist(Registration registration) async {
    if (!MemberRepository.instance.isAvailable) {
      return;
    }
    try {
      await MemberRepository.instance.upsertRegistration(registration);
    } catch (error, stack) {
      debugPrint('registration: could not save profile to database — $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  /// The member closed or skipped the form.
  void dismissPrompt() {
    if (_promptDismissed) {
      return;
    }
    _promptDismissed = true;
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _profile = null;
    _promptDismissed = false;
    notifyListeners();
  }
}
