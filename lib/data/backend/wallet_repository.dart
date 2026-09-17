import '../../module/privilege/privilege_tier.dart';
import 'backend_http.dart';

/// The wallet's own row — `GET /v1/member/wallet` (`wallet.service.ts`'s
/// `getOrCreateWallet`). The one authoritative figure for [balance]: the
/// column every debit and credit in `wallet_entry` is written against in the
/// same transaction, never derived client-side.
class RemoteWallet {
  final int balance;
  final int rewardPoints;

  const RemoteWallet({required this.balance, required this.rewardPoints});
}

/// One row of the real ledger behind [RemoteWallet.balance] —
/// `GET /v1/member/wallet/entries`. Credits positive, debits negative, same
/// convention as [WalletEntry].
class RemoteWalletEntry {
  final String label;
  final int amount;
  final DateTime occurredOn;

  const RemoteWalletEntry({
    required this.label,
    required this.amount,
    required this.occurredOn,
  });
}

/// A privilege card as it stands on the backend — what the app reads back to
/// learn whether a submitted plan has been approved yet.
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

/// Submits privilege-card activations to `backend/api` and reads their
/// approval state back — `POST /v1/member/wallet/cards` and
/// `GET /v1/member/wallet/cards` (see `wallet.service.ts`).
///
/// Every method is best-effort, the same contract as the other repositories
/// here: an unconfigured backend or an unreachable one → the call no-ops.
/// Submitting a plan must never fail because the backend is down.
///
/// A submitted card lands as `PENDING` and credits nothing. The console
/// approves it — that is where the `TOPUP` / `BONUS` ledger lines and the
/// balance move — or rejects it with a note.
class WalletRepository {
  WalletRepository._();

  static final WalletRepository instance = WalletRepository._();

  bool get isAvailable => BackendHttp.isConfigured;

  /// Set by [submitCardForApproval] right before it returns null for a real
  /// (not unconfigured/unreachable) failure — the backend's own reason,
  /// when it gave one, so the checkout screen can tell "you're being rate
  /// limited, wait an hour" apart from "check your connection and retry
  /// right now," which is actively wrong advice for the first case. Reset
  /// to null at the start of every call, so a stale reason from a previous
  /// attempt can never be read as this one's.
  String? lastSubmitCardError;

  /// The load amounts and bonus rate are already bundled client-side
  /// (`lib/module/privilege/privilege_tier.dart`) — this only needs to
  /// resolve [tierKind] to the numeric id `submitWalletCardSchema` requires,
  /// via the public membership-tiers list (cached — it's near-static).
  Map<PrivilegeCardKind, int>? _tierIdCache;

  /// Files a privilege-card activation for review.
  ///
  /// [agentCode] is the "Agent code (optional)" a member may type in at
  /// checkout — passed straight through as typed; the backend resolves it
  /// to a real agent (case-insensitively) and stores that on the card, so
  /// approving it later can credit that agent's own direct-sale commission
  /// (see `wallet.service.ts`'s `submitCard`/`approveCard`). An unknown or
  /// mistyped code is never a reason to fail this submission — the backend
  /// silently drops it rather than crediting nobody, so this call is
  /// resilient to that the same way.
  ///
  /// Returns the new card's id (as a string, standing in for the old row's
  /// uuid), or null when nothing was written.
  Future<String?> submitCardForApproval({
    required PrivilegeCardKind tierKind,
    required int amount,
    String? cardNumber,
    String? receiptReference,
    String? receiptFileName,
    String? receiptImage,
    String? agentCode,
  }) async {
    lastSubmitCardError = null;
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final tierId = await _tierIdFor(tierKind);
      if (tierId == null) {
        return null; // reference data not seeded
      }
      final created = await BackendHttp.instance.request(
        'POST',
        '/v1/member/wallet/cards',
        body: {
          'tierId': tierId,
          'amount': amount,
          if (cardNumber != null) 'cardNumber': cardNumber,
          if (receiptReference != null) 'receiptReference': receiptReference,
          if (receiptFileName != null) 'receiptFileName': receiptFileName,
          if (receiptImage != null && receiptImage.isNotEmpty) 'receiptImage': receiptImage,
          if (agentCode != null && agentCode.isNotEmpty) 'agentCode': agentCode,
        },
      ) as Map<String, dynamic>;
      return created['id']?.toString();
    } on BackendHttpException catch (error) {
      lastSubmitCardError = error.isTooManyRequests
          ? "You've submitted too many receipts recently — wait an hour "
              'and try again.'
          : null;
      BackendHttp.log('WalletRepository.submitCardForApproval failed', error: error);
      return null;
    } catch (error) {
      BackendHttp.log('WalletRepository.submitCardForApproval failed', error: error);
      return null;
    }
  }

  /// Every privilege card on the member's wallet, oldest first — pending,
  /// approved and rejected. The app merges this into `WalletService` to
  /// reflect what the console has decided. Returns null when nothing could
  /// be read. [memberPhone] is accepted for parity with the old direct-Neon
  /// signature but unused — the backend resolves identity from the session.
  Future<List<RemoteWalletCard>?> fetchCards({required String memberPhone}) async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final tierKindById = await _tierKindsById();
      final rows = await BackendHttp.instance.request('GET', '/v1/member/wallet/cards')
          as List<dynamic>;
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          if (tierKindById[(row['tierId'] as num).toInt()] case final kind?)
            RemoteWalletCard(
              uuid: row['id'].toString(),
              status: (row['status'] ?? 'PENDING').toString(),
              tierKind: kind,
              amount: _int(row['amount']),
              bonus: _int(row['bonus']),
              rechargedExtra: _int(row['rechargedExtra']),
              storeCode: null, // Not resolvable from this row alone; unused today.
              issuedOn: _date(row['issuedOn']) ?? DateTime.now(),
              expiresOn: _date(row['expiresOn']) ?? DateTime.now(),
              submittedAt: _date(row['submittedAt']) ?? DateTime.now(),
              reviewerNote: (row['reviewerNote'] ?? '').toString(),
            ),
      ];
    } catch (error) {
      BackendHttp.log('WalletRepository.fetchCards failed', error: error);
      return null;
    }
  }

  /// The wallet's real, server-held balance — the source of truth
  /// [WalletService.refreshFromDatabase] hydrates against, in place of the
  /// figure it would otherwise only ever compute from local activity. Null
  /// when the backend is unconfigured or unreachable, same contract as every
  /// other read here.
  Future<RemoteWallet?> fetchWallet() async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final row =
          await BackendHttp.instance.request('GET', '/v1/member/wallet')
              as Map<String, dynamic>;
      return RemoteWallet(
        balance: _int(row['balance']),
        rewardPoints: _int(row['rewardPoints']),
      );
    } catch (error) {
      BackendHttp.log('WalletRepository.fetchWallet failed', error: error);
      return null;
    }
  }

  /// The full ledger behind [fetchWallet]'s balance, newest first — every
  /// top-up, bonus, and spend the backend has ever posted for this member.
  Future<List<RemoteWalletEntry>?> fetchEntries() async {
    if (!BackendHttp.isConfigured) {
      return null;
    }
    try {
      final rows =
          await BackendHttp.instance.request('GET', '/v1/member/wallet/entries')
              as List<dynamic>;
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          RemoteWalletEntry(
            label: (row['label'] ?? '').toString(),
            amount: _int(row['amount']),
            occurredOn: _date(row['occurredOn']) ?? DateTime.now(),
          ),
      ];
    } catch (error) {
      BackendHttp.log('WalletRepository.fetchEntries failed', error: error);
      return null;
    }
  }

  Future<int?> _tierIdFor(PrivilegeCardKind kind) async {
    final cache = await _ensureTierIdCache();
    return cache[kind];
  }

  Future<Map<int, PrivilegeCardKind>> _tierKindsById() async {
    final byKind = await _ensureTierIdCache();
    return {for (final entry in byKind.entries) entry.value: entry.key};
  }

  Future<Map<PrivilegeCardKind, int>> _ensureTierIdCache() async {
    final cached = _tierIdCache;
    if (cached != null) {
      return cached;
    }
    final rows = await BackendHttp.instance.request(
      'GET',
      '/v1/public/catalogue/membership-tiers',
      auth: false,
    ) as List<dynamic>;
    final map = <PrivilegeCardKind, int>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final kind = _kindFor((row['kind'] ?? '').toString());
      final id = row['id'];
      if (kind != null && id != null) {
        map[kind] = (id as num).toInt();
      }
    }
    _tierIdCache = map;
    return map;
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
}
