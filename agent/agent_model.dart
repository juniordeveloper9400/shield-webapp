import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../dates.dart';
import '../../theme/app_colors.dart';

/// The rungs of the field sales hierarchy, widest first.
///
/// An agent heads one geographic tier and every agent below them in the tree
/// sits one or more levels down: a national agent's downline runs
/// region → state → district → assembly → lsgd → ward. The order here is the
/// order of authority, so [depth] doubles as the tree indent.
enum AgentLevel {
  national('National', AppColors.brandNavy, Color(0xFFE4E9F3)),
  region('Region', AppColors.levelStarter, AppColors.levelStarterTint),
  state('State', AppColors.levelRiser, AppColors.levelRiserTint),
  // Reuses the Silver tier's colours rather than adding a new pair — Silver
  // is not otherwise spoken for anywhere in the agent hierarchy, and every
  // other rung here already borrows its colour from somewhere else in the
  // app (the referral ladder) rather than owning one of its own.
  district('District', AppColors.silverAccent, AppColors.silverTint),
  assembly('Assembly', AppColors.levelAchiever, AppColors.levelAchieverTint),
  lsgd('LSGD', AppColors.levelChampion, AppColors.levelChampionTint),
  ward('Ward', AppColors.levelLegend, AppColors.levelLegendTint);

  const AgentLevel(this.label, this.accent, this.tint);

  /// Shown on chips and badges.
  final String label;

  /// Carries white text on itself and reads on [tint].
  final Color accent;

  /// A pale wash of [accent] for panels behind the accent.
  final Color tint;

  /// 0 for national, rising down the tree — also the indent step in the team
  /// tree view.
  int get depth => index;

  /// The tier one step down, or null at [ward].
  AgentLevel? get child =>
      index + 1 < AgentLevel.values.length
      ? AgentLevel.values[index + 1]
      : null;

  /// The tier one step up, or null at [national]. The tier an open position
  /// at this level is waiting on — nobody can be registered into a district
  /// slot until the state slot directly above it is filled first.
  AgentLevel? get parent => index > 0 ? AgentLevel.values[index - 1] : null;

  /// How many positions one agent at this level opens up at [child] — every
  /// tier down to lsgd doubles, so the tree's fixed shape is 1 national → 2
  /// region → 4 state → 8 district → 16 assembly → 32 lsgd → 64 ward. A ward
  /// heads nobody, so this is 0 there.
  int get childCapacity => child == null ? 0 : 2;

  /// A short tag for the square badge, e.g. `NAT`, `WRD`.
  String get code => switch (this) {
    AgentLevel.national => 'NAT',
    AgentLevel.region => 'REG',
    AgentLevel.state => 'STE',
    AgentLevel.district => 'DIS',
    AgentLevel.assembly => 'ASM',
    AgentLevel.lsgd => 'LSG',
    AgentLevel.ward => 'WRD',
  };
}

/// Whether the agent who recruited this one has signed off on them yet.
///
/// Separate from [Agent.active]: [active] is whether a working agent is
/// currently on the job, which says nothing about whether they were ever let
/// in. Every seed agent starts [approved] — they are the established org —
/// and only an agent registered from the portal starts [pending], since that
/// is the one path that adds somebody nobody above them has seen yet.
enum AgentApprovalStatus {
  pending('Pending approval', AppColors.goldAccent, AppColors.goldTint),
  approved('Approved', AppColors.brandGreenDark, AppColors.greenTint),
  rejected('Rejected', AppColors.danger, AppColors.dangerTint);

  const AgentApprovalStatus(this.label, this.accent, this.tint);

  final String label;
  final Color accent;
  final Color tint;
}

/// One agent in the hierarchy.
///
/// In-memory demo data: [AgentDirectory] builds a fixed tree of these and a
/// backend would replace it wholesale. Money figures are whole rupees.
@immutable
class Agent {
  final String id;
  final String name;
  final String phone;

  /// The printed member code, e.g. `SHD-NAT-001`.
  final String agentCode;

  final AgentLevel level;

  /// Whether the agent is currently working. Inactive agents still hold their
  /// place in the tree and their past sales still count for the team total.
  final bool active;

  /// The id of the agent one level up, or null for the national agent.
  final String? parentId;

  /// The place this agent heads — a region name, a ward number, and so on.
  final String area;

  /// Lifetime commission credited to this agent.
  final int earned;

  /// How much of [earned] has already been paid out.
  final int redeemed;

  /// Sales this agent closed themselves, before anything their downline did.
  final int personalSales;

  // ---- Registration (KYC) ----
  // Blank on the seed agents; filled in for anyone added through the agent
  // registration flow. [isRegistered] is the "has this been filled in" flag.

  final String firstName;
  final String middleName;
  final String lastName;

  /// Date of birth, or null for a seed agent.
  final DateTime? dob;

  /// 12-digit Aadhaar number, stored as digits only.
  final String aadhaar;

  /// 10-character PAN, stored uppercase.
  final String pan;

  final String address;
  final String pincode;

  /// Town / village given at registration. For an added agent this is also
  /// what [area] carries.
  final String place;

  /// Bank account the commission is paid into, digits only.
  final String accountNumber;

  /// The photo added from the agent's detail screen, or null before one has
  /// been added — the tree and the header fall back to [initials] until then.
  /// In memory only, the same as everything else on this record.
  final Uint8List? photoBytes;

  /// Whether the agent who recruited this one has approved them. Defaults to
  /// [AgentApprovalStatus.approved] so every seed literal is the established
  /// org without having to say so; [AgentService.registerAgent] is what sets
  /// [AgentApprovalStatus.pending] on the one path that needs it.
  final AgentApprovalStatus approvalStatus;

  const Agent({
    required this.id,
    required this.name,
    required this.phone,
    required this.agentCode,
    required this.level,
    required this.active,
    required this.parentId,
    required this.area,
    this.earned = 0,
    this.redeemed = 0,
    this.personalSales = 0,
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.dob,
    this.aadhaar = '',
    this.pan = '',
    this.address = '',
    this.pincode = '',
    this.place = '',
    this.accountNumber = '',
    this.photoBytes,
    this.approvalStatus = AgentApprovalStatus.approved,
  });

  /// A copy of this agent carrying [bytes] as their photo — the one field on
  /// this record anything ever changes after it is created.
  Agent withPhoto(Uint8List bytes) => _copyWith(photoBytes: bytes);

  /// A copy of this agent carrying [status] — how their parent has answered
  /// on them.
  Agent withApprovalStatus(AgentApprovalStatus status) =>
      _copyWith(approvalStatus: status);

  Agent _copyWith({Uint8List? photoBytes, AgentApprovalStatus? approvalStatus}) =>
      Agent(
        id: id,
        name: name,
        phone: phone,
        agentCode: agentCode,
        level: level,
        active: active,
        parentId: parentId,
        area: area,
        earned: earned,
        redeemed: redeemed,
        personalSales: personalSales,
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
        dob: dob,
        aadhaar: aadhaar,
        pan: pan,
        address: address,
        pincode: pincode,
        place: place,
        accountNumber: accountNumber,
        photoBytes: photoBytes ?? this.photoBytes,
        approvalStatus: approvalStatus ?? this.approvalStatus,
      );

  /// True once the agent has been through registration — i.e. has a date of
  /// birth and the KYC fields behind it.
  bool get isRegistered => dob != null;

  bool get isPending => approvalStatus == AgentApprovalStatus.pending;

  bool get isApproved => approvalStatus == AgentApprovalStatus.approved;

  /// What this agent is credited with — zero while [isApproved] is false, the
  /// same way a recruit nobody has signed off on has nothing to show yet.
  /// [AgentService] reads through this rather than [earned] directly whenever
  /// a figure is about to be displayed.
  int get displayEarned => isApproved ? earned : 0;

  int get displayRedeemed => isApproved ? redeemed : 0;

  int get displayPersonalSales => isApproved ? personalSales : 0;

  /// `04 Sep 1994`, or a dash when there is no date on file.
  String get dobLabel => dob == null ? '—' : formatDate(dob!);

  /// `•••• •••• 1234` — only the last four Aadhaar digits are ever shown.
  String get maskedAadhaar {
    if (aadhaar.length < 4) {
      return aadhaar.isEmpty ? '—' : aadhaar;
    }
    return '•••• •••• ${aadhaar.substring(aadhaar.length - 4)}';
  }

  /// `••••3456` — only the last four account digits are ever shown.
  String get maskedAccount {
    if (accountNumber.length < 4) {
      return accountNumber.isEmpty ? '—' : accountNumber;
    }
    return '••••${accountNumber.substring(accountNumber.length - 4)}';
  }

  /// One or two letters for the avatar circle.
  String get initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return '?';
    }
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }

  /// `+91 95398 •••••` — the tree and detail screens never show a downline
  /// agent's full number.
  String get maskedPhone {
    if (phone.length < 5) {
      return '+91 $phone';
    }
    return '+91 ${phone.substring(0, 5)} •••••';
  }
}

/// Why a withdrawal request is where it is.
///
/// The demo only ever creates [pending] requests; the other two are here so a
/// seeded history can show a settled and a bounced one.
enum WithdrawalStatus {
  pending('Pending'),
  paid('Paid'),
  rejected('Rejected');

  const WithdrawalStatus(this.label);

  final String label;
}

/// A single ask to move commission out of the wallet.
@immutable
class WithdrawalRequest {
  final int amount;
  final DateTime requestedOn;
  final WithdrawalStatus status;

  const WithdrawalRequest({
    required this.amount,
    required this.requestedOn,
    this.status = WithdrawalStatus.pending,
  });
}
