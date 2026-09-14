import '../../module/patients/patient_book.dart';
import 'backend_http.dart';

/// Reads and writes the people on an account through `backend/api`'s
/// `/v1/member/patients` routes — see `identity.service.ts`.
///
/// Every method is best-effort: with an unconfigured backend (tests) or the
/// network down, writes no-op and reads return null. Adding a patient must
/// never fail because the backend is unreachable — [PatientBook] stays the
/// source of truth for the running app, and this is the durable copy read
/// back on the next launch.
///
/// [Patient.remoteId] now carries the backend's numeric patient id (as a
/// string) rather than a Neon row's uuid — it was always an opaque
/// pass-through identifier to every call site, so this is not a visible
/// change to anything outside this class.
class PatientRepository {
  const PatientRepository._();

  static const PatientRepository instance = PatientRepository._();

  /// Whether a write or read would actually reach the backend.
  bool get isAvailable => BackendHttp.isConfigured;

  /// Inserts a new patient, or updates the existing row when [id] is given
  /// (the value a previous call returned, held on [Patient.remoteId]).
  ///
  /// Returns the row's id (as a string) so the caller can pin it onto the
  /// in-memory record with [PatientBook.attachRemoteId]. Null when nothing
  /// was written.
  Future<String?> upsert({
    String? id,
    required String memberPhone,
    required String memberName,
    required String name,
    required String phone,
    required String address,
    required DateTime dob,
    required PatientGender gender,
    required PatientRelation relation,
    required String abhaId,
  }) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }

    final body = {
      'name': name.trim(),
      'phone': phone.trim(),
      'address': address.trim(),
      'dob': _isoDate(dob),
      'gender': gender.name.toUpperCase(),
      'relation': relation.name.toUpperCase(),
      'abhaId': abhaId.replaceAll(RegExp(r'\D'), ''),
    };

    try {
      if (id != null) {
        final updated = await BackendHttp.instance.request(
          'PATCH',
          '/v1/member/patients/$id',
          body: body,
        ) as Map<String, dynamic>;
        return updated['id']?.toString();
      }

      final created = await BackendHttp.instance.request(
        'POST',
        '/v1/member/patients',
        body: body,
      ) as Map<String, dynamic>;
      final newId = created['id']?.toString();
      BackendHttp.log('PatientRepository.upsert: saved ${body['name']} ($newId)');
      return newId;
    } on BackendHttpException catch (error) {
      if (error.isNotFound) {
        // The row is gone (a stale id from a prior run) — fall through to a
        // fresh insert rather than silently losing the patient.
        return upsert(
          memberPhone: memberPhone,
          memberName: memberName,
          name: name,
          phone: phone,
          address: address,
          dob: dob,
          gender: gender,
          relation: relation,
          abhaId: abhaId,
        );
      }
      BackendHttp.log('PatientRepository.upsert failed', error: error);
      return null;
    } catch (error) {
      BackendHttp.log('PatientRepository.upsert failed', error: error);
      return null;
    }
  }

  /// Soft-deletes a patient row. A no-op when [id] no longer exists or
  /// belongs to someone else — same best-effort contract as every write here.
  Future<void> softDelete(String id) async {
    if (!BackendHttp.isConfigured) {
      return;
    }
    try {
      await BackendHttp.instance.request('DELETE', '/v1/member/patients/$id');
    } catch (error) {
      BackendHttp.log('PatientRepository.softDelete failed', error: error);
    }
  }

  /// Every non-deleted patient for the signed-in member.
  ///
  /// Returns `null` (not an empty list) when the backend is off or
  /// unreachable, so the caller can tell "this account has no saved
  /// patients" from "could not load them" and avoid wiping the in-memory
  /// list on a transient failure. [memberPhone] is accepted for parity with
  /// the old direct-Neon signature but unused — the backend resolves
  /// identity from the session.
  Future<List<Patient>?> listForMember(String memberPhone) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows = await BackendHttp.instance.request('GET', '/v1/member/patients')
          as List<dynamic>;
      return rows.cast<Map<String, dynamic>>().map(_toPatient).toList();
    } catch (error) {
      BackendHttp.log('PatientRepository.listForMember failed', error: error);
      return null;
    }
  }

  /// One patient row → a [Patient]. The id is derived from the row's numeric
  /// id so a reload lands on the same in-memory record, and `remoteId` is set
  /// so [PatientBook] knows this one is already backed by the backend.
  static Patient _toPatient(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    return Patient(
      id: 'remote-$id',
      remoteId: id.isEmpty ? null : id,
      name: (row['name'] ?? '').toString(),
      phone: (row['phone'] ?? '').toString(),
      address: (row['address'] ?? '').toString(),
      dob: DateTime.tryParse((row['dob'] ?? '').toString()) ?? DateTime(2000),
      gender: _genderFrom(row['gender']?.toString()),
      relation: _relationFrom(row['relation']?.toString()),
      abhaId: (row['abhaId'] ?? '').toString(),
    );
  }

  static PatientGender _genderFrom(String? label) => PatientGender.values
      .firstWhere((g) => g.name.toUpperCase() == label,
          orElse: () => PatientGender.other);

  static PatientRelation _relationFrom(String? label) => PatientRelation.values
      .firstWhere((r) => r.name.toUpperCase() == label,
          orElse: () => PatientRelation.other);

  /// `1994-09-04` — an unambiguous value for the backend's `dob` field.
  static String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
