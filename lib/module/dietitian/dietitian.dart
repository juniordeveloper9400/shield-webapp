import 'package:flutter/foundation.dart';

/// A dietitian a member can book a consultation with — read from
/// `app.dietitian` (see `CareRepository.fetchDietitians`), never hardcoded
/// here.
@immutable
class Dietitian {
  final String id;
  final String name;
  final String qualification;

  /// What they are consulted for. Drawn as chips on the card.
  final List<String> focus;

  final int experienceYears;
  final List<String> languages;

  /// Whole rupees for one consultation.
  final int fee;

  /// Plain words rather than a timestamp: a slot the app cannot actually book
  /// should not pretend to be a calendar entry. Blank when the admin hasn't
  /// set one.
  final String nextSlot;

  final String initials;

  const Dietitian({
    required this.id,
    required this.name,
    required this.qualification,
    required this.focus,
    required this.experienceYears,
    required this.languages,
    required this.fee,
    required this.nextSlot,
    required this.initials,
  });

  /// "8 yrs · Malayalam, English"
  String get summary => '$experienceYears yrs · ${languages.join(', ')}';
}

/// Search helper over a fetched panel — the panel itself is
/// `CareRepository.fetchDietitians()`'s result, not a static list.
class DietitianDirectory {
  const DietitianDirectory._();

  /// What every consultation includes, whoever it is with. Stated once above
  /// the list rather than repeated on each card.
  static const List<String> included = [
    'A diet plan written for your condition and your kitchen',
    'A follow-up call after two weeks, at no extra cost',
    'Notes shared with the pharmacist filling your prescription',
  ];

  /// Everyone in [all] whose name, focus or qualification matches [query]. An
  /// empty query returns [all] unfiltered.
  static List<Dietitian> search(List<Dietitian> all, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return all;
    }
    return all
        .where(
          (dietitian) =>
              dietitian.name.toLowerCase().contains(needle) ||
              dietitian.qualification.toLowerCase().contains(needle) ||
              dietitian.focus.any(
                (area) => area.toLowerCase().contains(needle),
              ),
        )
        .toList();
  }
}
