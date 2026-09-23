import '../../module/agent/agent_directory.dart';
import '../../module/agent/agent_model.dart';
import 'backend_http.dart';

/// One of the caller's own submitted `app.agent_request` rows — see
/// [AgentRepository.fetchOwnRequests].
class OwnAgentRequest {
  final int id;

  /// `PENDING` · `APPROVED` · `REJECTED`.
  final String status;
  final AgentLevel level;
  final String area;
  final DateTime createdAt;

  /// The admin's reason, set only when [status] is `REJECTED`.
  final String reviewerNote;

  const OwnAgentRequest({
    required this.id,
    required this.status,
    required this.level,
    required this.area,
    required this.createdAt,
    required this.reviewerNote,
  });

  bool get isPending => status == 'PENDING';
  bool get isRejected => status == 'REJECTED';
}

/// What [AgentRepository.submitOwnAgentRequest] resolves to: the new
/// request's id on success, or the backend's own refusal message — see
/// that method's own doc for why this one write doesn't collapse a failure
/// down to a bare null the way every other repository call here does.
class AgentRequestOutcome {
  final int? id;
  final String? error;

  const AgentRequestOutcome.success(this.id) : error = null;
  const AgentRequestOutcome.failure(this.error) : id = null;

  bool get ok => error == null;
}

/// Reads and writes the agent roster through `backend/api`'s `/v1/agent/*`
/// routes — see `agent.service.ts`.
///
/// Every method is best-effort, the same contract [NeonHttp]-backed
/// repositories used: an unconfigured backend, a signed-out member, or a
/// network blip no-ops rather than throwing. Registering an agent must never
/// fail because the backend is unreachable — [AgentService]'s in-memory
/// roster is the source of truth the UI reads; this is the write-through.
///
/// `app.agent.id` is a database bigint, not the app's own string ids
/// (`nat-001`, `add-3`) — [AgentService] bridges the two by prefixing a
/// fetched row's id `db-<id>` when it builds an [Agent] from it.
class AgentRepository {
  const AgentRepository._();

  static const AgentRepository instance = AgentRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  Future<void> requestWithdrawal(int amount) async {
    await BackendHttp.instance.request(
      'POST',
      '/v1/agent/withdrawals',
      body: {'amount': amount},
    );
  }

  Future<List<WithdrawalRequest>> fetchWithdrawals() async {
    final rows =
        await BackendHttp.instance.request('GET', '/v1/agent/withdrawals')
            as List<dynamic>;
    return rows.map((value) {
      final row = value as Map<String, dynamic>;
      return WithdrawalRequest(
        amount: num.parse(row['amount'].toString()).toInt(),
        requestedOn: DateTime.parse(row['requestedOn'].toString()),
        status: switch (row['status']) {
          'PAID' => WithdrawalStatus.paid,
          'REJECTED' => WithdrawalStatus.rejected,
          _ => WithdrawalStatus.pending,
        },
      );
    }).toList();
  }

  /// The signed-in member's own agent row plus every descendant
  /// (`GET /v1/agent/team`), or null when unavailable, the member isn't
  /// signed in to the backend, or isn't an approved agent.
  ///
  /// Deliberately scoped to the caller's own subtree, not the whole
  /// company — the old direct-Neon version of this method fetched every row
  /// of `app.agent` company-wide (every agent's Aadhaar, PAN, address and
  /// earnings) into any signed-in member's app; this backend route never
  /// exposes more than the caller's own team. See decision-log.md's note on
  /// the two-live-national-agents bug this same migration also fixes.
  Future<List<Agent>?> fetchAll() => _run('fetchAll', () async {
    final body =
        await BackendHttp.instance.request('GET', '/v1/agent/team')
            as Map<String, dynamic>;
    final descendants = (body['descendants'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return [_toAgent(body), ...descendants.map(_toAgent)];
  });

  /// PENDING `app.agent_request` rows recruited directly under the caller's
  /// own agent id (`GET /v1/agent/team/pending`) — mapped to a pending
  /// [Agent] so the team tree can show it as a locked "Waiting for approval"
  /// card. Null when unavailable or the caller isn't an approved agent.
  Future<List<Agent>?> fetchPendingRequests() =>
      _run('fetchPendingRequests', () async {
        final rows =
            await BackendHttp.instance.request('GET', '/v1/agent/team/pending')
                as List<dynamic>;
        return rows.cast<Map<String, dynamic>>().map(_toRequestAgent).toList();
      });

  /// The caller's own submitted agent requests, newest first
  /// (`GET /v1/agent/requests`) — what "Become a Sahakar 360 Agent" reads to show
  /// "your application is under review" instead of the form again once one
  /// is already in, and what tells it a rejected one can be resubmitted.
  /// Null when unavailable.
  Future<List<OwnAgentRequest>?> fetchOwnRequests() =>
      _run('fetchOwnRequests', () async {
        final rows =
            await BackendHttp.instance.request('GET', '/v1/agent/requests')
                as List<dynamic>;
        return rows.cast<Map<String, dynamic>>().map(_toOwnRequest).toList();
      });

  static OwnAgentRequest _toOwnRequest(Map<String, dynamic> row) =>
      OwnAgentRequest(
        id: row['id'] as int,
        status: (row['status'] ?? 'PENDING').toString(),
        level:
            _levelByName[(row['requestedLevel'] ?? 'WARD').toString()] ??
            AgentLevel.ward,
        area: (row['requestedArea'] ?? '').toString(),
        createdAt:
            DateTime.tryParse((row['createdAt'] ?? '').toString()) ??
            DateTime.now(),
        reviewerNote: (row['reviewerNote'] ?? '').toString(),
      );

  /// Files a member's own request to become an agent — the same
  /// `POST /v1/agent/requests` [insertAgentRequest] uses for a recruiter
  /// adding someone else, but with the caller's identity resolved
  /// server-side from their own session (see `agent.service.ts`'s
  /// `submitRequest`) rather than a `parentAgentId` — there is no recruiter
  /// here to place them under, so the admin console assigns the real parent
  /// at approval time.
  ///
  /// Unlike every other write in this file, this does not swallow a failure
  /// into a bare `null`: "Become an Agent" is the one screen where silently
  /// saying "sent" for an application that never reached admin — a stale
  /// connection, a real refusal like an incomplete registration — would
  /// defeat the entire point of it existing. See [AgentRequestOutcome].
  Future<AgentRequestOutcome> submitOwnAgentRequest({
    required AgentLevel level,
    required String area,
    String? areaId,
    required String firstName,
    String middleName = '',
    required String lastName,
    required DateTime dob,
    required String aadhaar,
    required String pan,
    required String address,
    required String pincode,
    required String place,
    required String accountNumber,
  }) async {
    if (!BackendHttp.isConfigured) {
      return const AgentRequestOutcome.failure(
        'Not connected — check your connection and try again.',
      );
    }
    try {
      final body =
          await BackendHttp.instance.request(
                'POST',
                '/v1/agent/requests',
                body: {
                  'requestedLevel': level.name.toUpperCase(),
                  'requestedArea': area,
                  if (areaId != null) 'requestedAreaId': areaId,
                  'firstName': firstName,
                  'middleName': middleName,
                  'lastName': lastName,
                  'dob': _isoDate(dob),
                  'aadhaar': aadhaar,
                  'pan': pan,
                  'address': address,
                  'pincode': pincode,
                  'place': place,
                  'accountNumber': accountNumber,
                },
              )
              as Map<String, dynamic>;
      return AgentRequestOutcome.success(body['id'] as int?);
    } on BackendHttpException catch (error) {
      return AgentRequestOutcome.failure(error.message);
    } catch (error) {
      BackendHttp.log(
        'AgentRepository.submitOwnAgentRequest failed',
        error: error,
      );
      return const AgentRequestOutcome.failure(
        'Something went wrong. Please try again.',
      );
    }
  }

  /// Files an agent-registration request (`POST /v1/agent/requests`) for the
  /// admin console to approve. Returns the request row id, or null on
  /// failure — best-effort like every write here.
  Future<int?> insertAgentRequest({
    required int? parentDbId,
    required AgentLevel level,
    required String name,
    required String phone,
    required String area,
    String? areaId,
    required String firstName,
    String middleName = '',
    required String lastName,
    required DateTime dob,
    required String aadhaar,
    required String pan,
    required String address,
    required String pincode,
    required String place,
    required String accountNumber,
  }) => _run('insertAgentRequest', () async {
    final body =
        await BackendHttp.instance.request(
              'POST',
              '/v1/agent/requests',
              body: {
                if (parentDbId != null) 'parentAgentId': parentDbId,
                // The recruit's own, already OTP-verified phone. Without
                // this the backend has no way to tell this request apart
                // from a plain self "become an agent" one, and falls back
                // to the signed-in recruiter's own phone — see
                // agent.service.ts's submitRequest for the bug that caused.
                'phone': phone,
                'requestedLevel': level.name.toUpperCase(),
                'requestedArea': area,
                if (areaId != null) 'requestedAreaId': areaId,
                'firstName': firstName,
                'middleName': middleName,
                'lastName': lastName,
                'dob': _isoDate(dob),
                'aadhaar': aadhaar,
                'pan': pan,
                'address': address,
                'pincode': pincode,
                'place': place,
                'accountNumber': accountNumber,
              },
            )
            as Map<String, dynamic>;
    return body['id'] as int?;
  });

  // ---- mapping ------------------------------------------------------------

  static const _levelByName = {
    'NATIONAL': AgentLevel.national,
    'REGION': AgentLevel.region,
    'STATE': AgentLevel.state,
    'DISTRICT': AgentLevel.district,
    'ASSEMBLY': AgentLevel.assembly,
    'LSGD': AgentLevel.lsgd,
    'WARD': AgentLevel.ward,
  };

  static const _approvalByName = {
    'PENDING': AgentApprovalStatus.pending,
    'APPROVED': AgentApprovalStatus.approved,
    'REJECTED': AgentApprovalStatus.rejected,
  };

  /// One `app.agent` row (from `GET /v1/agent/team`) → an [Agent]. A null
  /// `parentId` is parented under the seed national persona rather than
  /// left null — see this class's own doc on the `db-<id>` scheme.
  static Agent _toAgent(Map<String, dynamic> row) {
    String str(Object? v) => (v ?? '').toString();
    int money(Object? v) => double.tryParse(str(v))?.round() ?? 0;

    final dbId = str(row['id']);
    final parentDbId = row['parentId'];
    final dob = DateTime.tryParse(str(row['dob']));

    return Agent(
      id: 'db-$dbId',
      name: str(row['name']),
      phone: str(row['phone']),
      agentCode: str(row['code']),
      level: _levelByName[str(row['level']).toUpperCase()] ?? AgentLevel.ward,
      active: row['active'] == true,
      parentId: parentDbId == null
          ? AgentDirectory.national.id
          : 'db-${str(parentDbId)}',
      area: str(row['area']),
      areaId: str(row['areaId']).isEmpty ? null : str(row['areaId']),
      earned: money(row['earned']),
      redeemed: money(row['redeemed']),
      personalSales: money(row['personalSales']),
      plansSold: int.tryParse(str(row['plansSold'])) ?? 0,
      firstName: str(row['firstName']),
      middleName: str(row['middleName']),
      lastName: str(row['lastName']),
      dob: dob,
      aadhaar: str(row['aadhaar']),
      pan: str(row['pan']),
      address: str(row['address']),
      pincode: str(row['pincode']),
      place: str(row['place']),
      accountNumber: str(row['accountNumber']),
      approvalStatus:
          _approvalByName[str(row['approvalStatus']).toUpperCase()] ??
          AgentApprovalStatus.approved,
    );
  }

  /// One PENDING `app.agent_request` row (from `GET /v1/agent/team/pending`)
  /// → a pending [Agent]. The id is `req-<id>` (distinct from a real agent's
  /// `db-<id>`), the figures are zero, and [Agent.approvalStatus] is
  /// [AgentApprovalStatus.pending] so the tree draws a locked card rather
  /// than a working agent.
  static Agent _toRequestAgent(Map<String, dynamic> row) {
    String str(Object? v) => (v ?? '').toString();
    final parentDbId = row['parentAgentId'];
    final level =
        _levelByName[str(row['requestedLevel']).toUpperCase()] ??
        AgentLevel.ward;
    return Agent(
      id: 'req-${str(row['id'])}',
      name: str(row['name']),
      phone: str(row['phone']),
      agentCode: 'SHD-${level.code}-R${str(row['id'])}',
      level: level,
      active: false,
      parentId: (parentDbId == null || str(parentDbId).isEmpty)
          ? AgentDirectory.national.id
          : 'db-${str(parentDbId)}',
      area: str(row['requestedArea']),
      areaId: str(row['requestedAreaId']).isEmpty
          ? null
          : str(row['requestedAreaId']),
      firstName: str(row['firstName']),
      middleName: str(row['middleName']),
      lastName: str(row['lastName']),
      dob: DateTime.tryParse(str(row['dob'])),
      aadhaar: str(row['aadhaar']),
      pan: str(row['pan']),
      address: str(row['address']),
      pincode: str(row['pincode']),
      place: str(row['place']),
      accountNumber: str(row['accountNumber']),
      approvalStatus: AgentApprovalStatus.pending,
    );
  }

  /// `2026-08-31` — an unambiguous value for the backend's `dob` field.
  static String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// Runs [action], swallowing everything: an unconfigured backend, not
  /// signed in, a 403/404 (not an approved agent / no data yet), a network
  /// error. Returns null on any of them.
  Future<T?> _run<T>(String label, Future<T?> Function() action) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      return await action();
    } on BackendHttpException catch (error) {
      if (!error.isForbidden && !error.isNotFound) {
        BackendHttp.log('AgentRepository.$label failed', error: error);
      }
      return null;
    } catch (error) {
      BackendHttp.log('AgentRepository.$label failed', error: error);
      return null;
    }
  }
}
