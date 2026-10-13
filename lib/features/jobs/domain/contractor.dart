import 'package:equatable/equatable.dart';

import '../../complaints/domain/complaint.dart';

enum ContractorStatus { pendingApproval, approved, rejected, suspended }

extension ContractorStatusInfo on ContractorStatus {
  String get label => switch (this) {
        ContractorStatus.pendingApproval => 'Pending approval',
        ContractorStatus.approved => 'Approved',
        ContractorStatus.rejected => 'Rejected',
        ContractorStatus.suspended => 'Suspended',
      };
}

class Contractor extends Equatable {
  const Contractor({
    required this.id,
    required this.name,
    required this.registrationNo,
    required this.specialties,
    required this.status,
    required this.joinedAt,
    this.ratingTotal = 0,
    this.ratingCount = 0,
    this.completedJobs = 0,
  });

  final String id;
  final String name;

  final String registrationNo;
  final Set<ComplaintCategory> specialties;
  final ContractorStatus status;
  final DateTime joinedAt;
  final int ratingTotal;
  final int ratingCount;
  final int completedJobs;

  double? get averageRating =>
      ratingCount == 0 ? null : ratingTotal / ratingCount;

  bool get canReceiveWork => status == ContractorStatus.approved;

  Contractor copyWith({
    ContractorStatus? status,
    int? ratingTotal,
    int? ratingCount,
    int? completedJobs,
  }) =>
      Contractor(
        id: id,
        name: name,
        registrationNo: registrationNo,
        specialties: specialties,
        status: status ?? this.status,
        joinedAt: joinedAt,
        ratingTotal: ratingTotal ?? this.ratingTotal,
        ratingCount: ratingCount ?? this.ratingCount,
        completedJobs: completedJobs ?? this.completedJobs,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        registrationNo,
        specialties,
        status,
        joinedAt,
        ratingTotal,
        ratingCount,
        completedJobs,
      ];
}
