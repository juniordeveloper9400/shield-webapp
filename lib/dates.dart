const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `04 Sep 1994` — the one date format the app writes.
///
/// Shared: registration and the patient book both take a date of birth from a
/// picker and both have to print it back. Two copies would drift.
String formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  return '$day ${_months[date.month - 1]} ${date.year}';
}

/// `10 Sep` — a date with the year left off.
///
/// For dates inside the year they are read in, where printing 2026 on every
/// one of them is four characters of noise on a panel that has none to spare.
/// Anything that could be in another year uses [formatDate].
String formatDayMonth(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  return '$day ${_months[date.month - 1]}';
}

/// `16 Aug 2026, 05:24 PM` — date with time in 12-hour AM/PM format.
String formatDateTime12h(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final monthStr = _months[date.month - 1];
  final year = date.year;
  final hour12 = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
  final hourStr = hour12.toString().padLeft(2, '0');
  final minuteStr = date.minute.toString().padLeft(2, '0');
  final ampm = date.hour >= 12 ? 'PM' : 'AM';
  return '$day $monthStr $year, $hourStr:$minuteStr $ampm';
}

/// Reads back a date [formatDate] wrote — `16 Aug 2026` — or null if the text
/// is not in that shape.
DateTime? parseDate(String text) {
  final trimmed = text.trim();
  final iso = DateTime.tryParse(trimmed);
  if (iso != null) return iso;

  final cleanText = trimmed.split(',').first.trim();
  final parts = cleanText.split(RegExp(r'\s+'));
  if (parts.length != 3) {
    return null;
  }
  final day = int.tryParse(parts[0]);
  final month = _months.indexOf(parts[1]) + 1;
  final year = int.tryParse(parts[2]);
  if (day == null || month < 1 || year == null) {
    return null;
  }
  return DateTime(year, month, day);
}

/// Whole years between [dob] and [asOf], defaulting to today.
///
/// Counts the birthday, not the year difference: someone born in December is
/// still the younger age until December comes round.
int ageInYears(DateTime dob, {DateTime? asOf}) {
  final now = asOf ?? DateTime.now();
  var years = now.year - dob.year;
  final hadBirthday =
      now.month > dob.month || (now.month == dob.month && now.day >= dob.day);
  if (!hadBirthday) {
    years--;
  }
  return years < 0 ? 0 : years;
}

/// `31 yrs` — how an age derived from a date of birth is printed.
///
/// Shared so the patient row, the patient form and the registration form all
/// say the same thing; `1 yr` rather than `1 yrs` because an infant is the one
/// case where the plural is read closely.
String ageLabel(DateTime dob, {DateTime? asOf}) {
  final years = ageInYears(dob, asOf: asOf);
  return '$years ${years == 1 ? 'yr' : 'yrs'}';
}
