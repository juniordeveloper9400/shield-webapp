import '../../module/agent/agent_directory.dart';
import '../../module/agent/agent_model.dart';
import 'neon_http.dart';

/// Reads and writes the agent roster on `app.agent`.
///
/// Every method is best-effort, the same contract as [MemberRepository] and
/// the other Neon repositories: a missing `DATABASE_URL` or a network blip
/// no-ops rather than throwing. Registering an agent must never fail because
/// the database is unreachable — [AgentService]'s in-memory roster is the
/// source of truth the UI reads; this is the write-through.
///
/// `app.agent.id` is a database bigint, not the app's own string ids
/// (`nat-001`, `add-3`) — [AgentService] bridges the two by prefixing a
/// fetched row's id `db-<id>` when it builds an [Agent] from it.
class AgentRepository {
  const AgentRepository._();

  static const AgentRepository instance = AgentRepository._();

  bool get isAvailable => NeonHttp.isConfigured;

  /// Every row in `app.agent`, oldest first, or null when the database is
  /// unavailable. [AgentService.ensureLoaded] folds these into the roster
  /// below the seed national persona, skipping any row that already matches
  /// its phone (that would be the seed root's own database row, added the
  /// first time a registration needed one to parent under).
  Future<List<Agent>?> fetchAll() => _run('fetchAll', () async {
        final rows = await NeonHttp.instance.query(r'''
          SELECT id::text, code, name, phone, level::text, parent_id::text,
                 active, area, area_id::text, first_name, middle_name, last_name,
                 dob::text, aadhaar, pan, address, pincode, place, account_number,
                 approval_status::text, earned, redeemed, personal_sales
          FROM app.agent
          ORDER BY id
        ''');
        return rows.map(_toAgent).toList();
      });

  /// Every PENDING `app.agent_request` — an agent recruited in the app and
  /// awaiting an admin's approval — mapped to a pending [Agent] so the team
  /// tree can show it as a locked "Waiting for approval" card. Null when the
  /// database is unavailable.
  Future<List<Agent>?> fetchPendingRequests() => _run('fetchPendingRequests',
      () async {
        final rows = await NeonHttp.instance.query(r'''
          SELECT r.id::text, r.name, r.phone, r.requested_level::text AS level,
                 r.parent_agent_id::text AS parent_id, r.requested_area AS area,
                 r.requested_area_id::text AS area_id,
                 r.first_name, r.middle_name, r.last_name, r.dob::text,
                 r.aadhaar, r.pan, r.address, r.pincode, r.place,
                 r.account_number, r.status::text
          FROM app.agent_request r
          WHERE r.status = 'PENDING'
          ORDER BY r.created_at
        ''');
        return rows.map(_toRequestAgent).toList();
      });

  /// Files an agent-registration request (`app.agent_request`, status PENDING)
  /// for the admin console to approve. Returns the request row id, or null on
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
  }) =>
      _run('insertAgentRequest', () async {
        final rows = await NeonHttp.instance.query(
          r'''
            INSERT INTO app.agent_request (
              parent_agent_id, requested_level, requested_area, requested_area_id,
              name, phone, first_name, middle_name, last_name, dob,
              aadhaar, pan, address, pincode, place, account_number
            )
            VALUES (
              $1, $2::app.agent_level, $3, $4::uuid,
              $5, $6, $7, $8, $9, $10::date,
              $11, $12, $13, $14, $15, $16
            )
            RETURNING id::text
          ''',
          [
            parentDbId,
            level.name.toUpperCase(),
            area,
            areaId,
            name,
            phone,
            firstName,
            middleName,
            lastName,
            _isoDate(dob),
            aadhaar,
            pan,
            address,
            pincode,
            place,
            accountNumber,
          ],
        );
        return rows.isEmpty ? null : int.tryParse(rows.first['id'].toString());
      });

  /// Inserts a new agent under [parentDbId] — the database id of the parent
  /// row, resolved by the caller ([AgentService]) since the parent might
  /// itself be the seed national persona (no row of its own yet) or an
  /// agent registered earlier this session (whose own insert might still be
  /// in flight). Returns the new row's database id, or null on failure.
  ///
  /// Used by the admin-approval path only — the app's own registration flow
  /// files an [insertAgentRequest] instead and lets the console approve it.
  Future<int?> insertAgent({
    required int parentDbId,
    required AgentLevel level,
    required String code,
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
  }) =>
      _run('insertAgent', () async {
        final rows = await NeonHttp.instance.query(
          r'''
            INSERT INTO app.agent (
              code, name, phone, level, parent_id, area, area_id,
              first_name, middle_name, last_name, dob, aadhaar, pan,
              address, pincode, place, account_number, approval_status
            )
            VALUES (
              $1, $2, $3, $4::app.agent_level, $5, $6, $7::uuid,
              $8, $9, $10, $11::date, $12, $13,
              $14, $15, $16, $17, 'APPROVED'
            )
            RETURNING id::text
          ''',
          [
            code,
            name,
            phone,
            level.name.toUpperCase(),
            parentDbId,
            area,
            areaId,
            firstName,
            middleName,
            lastName,
            _isoDate(dob),
            aadhaar,
            pan,
            address,
            pincode,
            place,
            accountNumber,
          ],
        );
        return rows.isEmpty ? null : int.tryParse(rows.first['id'].toString());
      });

  /// The database row id for the national seed agent — [phone]'s existing
  /// row if one is already there (from an earlier session, or written by
  /// something else entirely — the admin console, say), else a freshly
  /// inserted one. The seed persona ([AgentDirectory.national]) has no row
  /// of its own by default; the first registration under it needs this so
  /// the new row's `parent_id` points at something real.
  Future<int?> ensureNationalRow({
    required String phone,
    required String name,
    required String code,
  }) =>
      _run('ensureNationalRow', () async {
        final existing = await NeonHttp.instance.query(
          'SELECT id::text FROM app.agent WHERE phone = \$1 LIMIT 1',
          [phone],
        );
        if (existing.isNotEmpty) {
          return int.tryParse(existing.first['id'].toString());
        }
        final inserted = await NeonHttp.instance.query(
          r'''
            INSERT INTO app.agent (code, name, phone, level, parent_id, approval_status)
            VALUES ($1, $2, $3, 'NATIONAL', NULL, 'APPROVED')
            ON CONFLICT (code) DO UPDATE SET updated_at = now()
            RETURNING id::text
          ''',
          [code, name, phone],
        );
        return inserted.isEmpty
            ? null
            : int.tryParse(inserted.first['id'].toString());
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

  /// One `app.agent` row → an [Agent]. Neon's `/sql` endpoint returns every
  /// value as text, so the numeric, date and enum columns are parsed back
  /// out here rather than trusted to arrive typed. The database id becomes
  /// `db-<id>` — see this class's own doc — and a null `parent_id` is
  /// parented under the seed national persona rather than left null: only
  /// the national agent itself is ever meant to have no parent, and a row
  /// with nothing above it recorded (written before this app's own
  /// registration flow existed, say) still needs somewhere real to hang
  /// from so it is reachable in the tree at all.
  static Agent _toAgent(Map<String, dynamic> row) {
    String str(Object? v) => (v ?? '').toString();
    int money(Object? v) => double.tryParse(str(v))?.round() ?? 0;

    final dbId = str(row['id']);
    final parentDbId = row['parent_id'];
    final dob = DateTime.tryParse(str(row['dob']));

    return Agent(
      id: 'db-$dbId',
      name: str(row['name']),
      phone: str(row['phone']),
      agentCode: str(row['code']),
      level: _levelByName[str(row['level']).toUpperCase()] ?? AgentLevel.ward,
      active: row['active'] == true || row['active'] == 'true',
      parentId: parentDbId == null
          ? AgentDirectory.national.id
          : 'db-${str(parentDbId)}',
      area: str(row['area']),
      areaId: str(row['area_id']).isEmpty ? null : str(row['area_id']),
      earned: money(row['earned']),
      redeemed: money(row['redeemed']),
      personalSales: money(row['personal_sales']),
      firstName: str(row['first_name']),
      middleName: str(row['middle_name']),
      lastName: str(row['last_name']),
      dob: dob,
      aadhaar: str(row['aadhaar']),
      pan: str(row['pan']),
      address: str(row['address']),
      pincode: str(row['pincode']),
      place: str(row['place']),
      accountNumber: str(row['account_number']),
      approvalStatus: _approvalByName[str(row['approval_status']).toUpperCase()] ??
          AgentApprovalStatus.approved,
    );
  }

  /// One PENDING `app.agent_request` row → a pending [Agent]. The id is
  /// `req-<id>` (distinct from a real agent's `db-<id>`), the figures are zero,
  /// and [Agent.approvalStatus] is [AgentApprovalStatus.pending] so the tree
  /// draws a locked card rather than a working agent. [Agent.agentCode] is a
  /// reference number (`SHD-DIS-R7`) — the real code is minted by the console
  /// on approval.
  static Agent _toRequestAgent(Map<String, dynamic> row) {
    String str(Object? v) => (v ?? '').toString();
    final parentDbId = row['parent_id'];
    final level =
        _levelByName[str(row['level']).toUpperCase()] ?? AgentLevel.ward;
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
      area: str(row['area']),
      areaId: str(row['area_id']).isEmpty ? null : str(row['area_id']),
      firstName: str(row['first_name']),
      middleName: str(row['middle_name']),
      lastName: str(row['last_name']),
      dob: DateTime.tryParse(str(row['dob'])),
      aadhaar: str(row['aadhaar']),
      pan: str(row['pan']),
      address: str(row['address']),
      pincode: str(row['pincode']),
      place: str(row['place']),
      accountNumber: str(row['account_number']),
      approvalStatus: AgentApprovalStatus.pending,
    );
  }

  /// `2026-08-31` — an unambiguous value for a `date` column.
  static String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// Runs [action], swallowing everything: a missing `DATABASE_URL`, a
  /// network error, a SQL error. Returns null on any of them.
  Future<T?> _run<T>(String label, Future<T?> Function() action) async {
    if (!NeonHttp.isConfigured) {
      return null;
    }
    try {
      return await action();
    } catch (error) {
      NeonHttp.log('AgentRepository.$label failed', error: error);
      return null;
    }
  }
}
