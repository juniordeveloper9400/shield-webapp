import '../../module/privilege/privilege_tier.dart';
import 'neon_http.dart';

/// A privilege card as it stands on Neon — what the app reads back to learn
/// whether a submitted plan has been approved yet.
class RemoteWalletCard {
  final String uuid;

  /// `PENDING` · `APPROVED` · `REJECTED` (the `app.approval_status` tokens).
  final String status;
  final PrivilegeCardKind tierKind;
  final int amount;
  final int bonus;
  final int rechargedExtra;
  final String? storeCode;
  final DateTime issuedOn;
  final DateTime expiresOn;
  final DateTime submittedAt;

  /// The Super Admin's reason, set only when [status] is `REJECTED`.
  final String reviewerNote;

  const RemoteWalletCard({
    required this.uuid,
    required this.status,
    required this.tierKind,
    required this.amount,
    required this.bonus,
    required this.rechargedExtra,
    required this.storeCode,
    required this.issuedOn,
    required this.expiresOn,
    required this.submittedAt,
    required this.reviewerNote,
  });

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';

  /// What lands on the balance once the card is approved: the load, its bonus
  /// and anything recharged onto it since.
  int get credited => amount + bonus + rechargedExtra;
}

/// Submits privilege-card activations to Neon and reads their approval state
/// back. Over [NeonHttp] (HTTPS) so it behaves the same in a `--release` build.
///
/// Every method is best-effort, the same contract as the other repositories:
/// no `DATABASE_URL` (tests, a build without `--dart-define-from-file=.env`) or
/// an unreachable endpoint → the call no-ops. Submitting a plan must never fail
/// because the database is down.
///
/// A submitted card lands as `PENDING` and credits nothing. The console
/// approves it — that is where the `ACTIVATION` / `BONUS` ledger lines and the
/// balance move — or rejects it with a note.
class WalletRepository {
  const WalletRepository._();

  static const WalletRepository instance = WalletRepository._();

  bool get isAvailable => NeonHttp.isConfigured;

  /// Files a privilege-card activation for review. Opens the member's wallet
  /// row (without stamping `opened_at` — that waits for the first approval),
  /// then inserts the `app.wallet_card` as `PENDING`.
  ///
  /// Returns the new card's `uuid`, or null when nothing was written.
  Future<String?> submitCardForApproval({
    required String memberPhone,
    required String memberName,
    required PrivilegeCardKind tierKind,
    required int amount,
    required int bonus,
    required String cardNumber,
    String? storeCode,
    String? receiptReference,
    String? receiptFileName,
    String? receiptImage,
  }) {
    return _run('submitCardForApproval', () async {
      final memberId = _rowId(
        await NeonHttp.instance.query(
          '''
            INSERT INTO app.users (phone, name)
            VALUES (\$1, \$2)
            ON CONFLICT (phone) DO UPDATE SET updated_at = now()
            RETURNING id
          ''',
          [memberPhone, memberName],
        ),
      );
      if (memberId == null) {
        return null;
      }

      final walletId = _rowId(
        await NeonHttp.instance.query(
          '''
            INSERT INTO app.wallet (member_id)
            VALUES (\$1)
            ON CONFLICT (member_id) DO UPDATE SET updated_at = now()
            RETURNING id
          ''',
          [memberId],
        ),
      );
      if (walletId == null) {
        return null;
      }

      final tierRows = await NeonHttp.instance.query(
        '''
          SELECT id, validity_months FROM app.membership_tier
          WHERE kind = \$1::app.privilege_card_kind
        ''',
        [tierKind.name.toUpperCase()],
      );
      if (tierRows.isEmpty) {
        return null; // reference data not seeded
      }
      final tierId = _int(tierRows.first['id']);
      final validityMonths = _int(tierRows.first['validity_months'], 12);

      final inserted = await NeonHttp.instance.query(
        '''
          INSERT INTO app.wallet_card (
            wallet_id, tier_id, amount, bonus, card_number, store_id,
            status, submitted_at, issued_on, recharged_on, expires_on,
            receipt_reference, receipt_file_name, receipt_image
          )
          VALUES (
            \$1, \$2, \$3, \$4, \$5,
            (SELECT id FROM app.shield_store WHERE code = \$6),
            'PENDING', now(), current_date, current_date,
            current_date + make_interval(months => \$7),
            \$8, \$9, \$10
          )
          RETURNING uuid
        ''',
        [
          walletId,
          tierId,
          amount,
          bonus,
          cardNumber,
          storeCode,
          validityMonths,
          receiptReference,
          receiptFileName,
          receiptImage,
        ],
      );
      return inserted.isEmpty ? null : inserted.first['uuid']?.toString();
    });
  }

  /// Every privilege card on the member's wallet, oldest first — pending,
  /// approved and rejected. The app merges this into [WalletService] to reflect
  /// what the console has decided. Returns null when nothing could be read.
  Future<List<RemoteWalletCard>?> fetchCards({required String memberPhone}) {
    return _run('fetchCards', () async {
      final rows = await NeonHttp.instance.query(
        '''
          SELECT wc.uuid, wc.status,
                 wc.amount, wc.bonus, wc.recharged_extra,
                 wc.issued_on, wc.expires_on, wc.submitted_at, wc.reviewer_note,
                 mt.kind AS tier_kind,
                 s.code  AS store_code
          FROM app.wallet_card wc
          JOIN app.wallet w           ON w.id  = wc.wallet_id
          JOIN app.users u            ON u.id  = w.member_id
          JOIN app.membership_tier mt ON mt.id = wc.tier_id
          LEFT JOIN app.shield_store s ON s.id = wc.store_id
          WHERE u.phone = \$1
          ORDER BY wc.submitted_at, wc.id
        ''',
        [memberPhone],
      );
      return [
        for (final r in rows)
          if (_kindFor(r['tier_kind']?.toString()) case final kind?)
            RemoteWalletCard(
              uuid: r['uuid'].toString(),
              status: (r['status'] ?? 'PENDING').toString(),
              tierKind: kind,
              amount: _int(r['amount']),
              bonus: _int(r['bonus']),
              rechargedExtra: _int(r['recharged_extra']),
              storeCode: r['store_code']?.toString(),
              issuedOn: _date(r['issued_on']) ?? DateTime.now(),
              expiresOn: _date(r['expires_on']) ?? DateTime.now(),
              submittedAt: _date(r['submitted_at']) ?? DateTime.now(),
              reviewerNote: (r['reviewer_note'] ?? '').toString(),
            ),
      ];
    });
  }

  static PrivilegeCardKind? _kindFor(String? token) => switch (token) {
        'SILVER' => PrivilegeCardKind.silver,
        'GOLD' => PrivilegeCardKind.gold,
        'PLATINUM' => PrivilegeCardKind.platinum,
        _ => null,
      };

  static int _int(Object? value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = num.tryParse(value?.toString() ?? '');
    return parsed?.toInt() ?? fallback;
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  static int? _rowId(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return null;
    final value = rows.first['id'] ?? rows.first.values.firstOrNull;
    if (value == null) return null;
    return value is int ? value : int.tryParse(value.toString());
  }

  Future<T?> _run<T>(String label, Future<T?> Function() action) async {
    if (!NeonHttp.isConfigured) {
      return null;
    }
    try {
      return await action();
    } catch (error) {
      NeonHttp.log('WalletRepository.$label failed', error: error);
      return null;
    }
  }
}
