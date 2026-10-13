import '../../features/complaints/domain/complaint.dart';
import '../../features/complaints/domain/services/category_classifier.dart';
import '../../features/complaints/domain/services/priority_engine.dart';
import '../../features/jobs/domain/contractor.dart';
import '../../features/jobs/domain/work_job.dart';
import '../../features/notifications/domain/app_notification.dart';
import '../models/app_role.dart';
import '../models/media_attachment.dart';
import '../utils/geo.dart';

/// Realistic, internally consistent demo records (complaints ↔ jobs ↔
/// contractors). Timestamps are relative to [now] so ages always look fresh.
class DemoSeed {
  DemoSeed({required this.now, required this.center});

  final DateTime now;
  final GeoPoint center;

  static const _classifier = KeywordCategoryClassifier();
  static const _engine = PriorityEngine();
  static const _officer = 'Ward 4 Officer';

  DateTime _ago({int days = 0, int hours = 0}) =>
      now.subtract(Duration(days: days, hours: hours));

  MediaAttachment _img(String id, String caption,
          [EvidenceStage stage = EvidenceStage.report]) =>
      MediaAttachment(
          id: id,
          storage: MediaStorage.seedIllustration,
          caption: caption,
          stage: stage);

  TimelineEvent _ev(ComplaintStatus s, DateTime at, String who, AppRole role,
          [String? note]) =>
      TimelineEvent(
          status: s, at: at, actorName: who, actorRole: role, note: note);

  Set<String> _supporters(int n) => {for (var i = 0; i < n; i++) 'cit-n$i'};

  Complaint _complaint({
    required String id,
    required String title,
    required String description,
    required ComplaintCategory category,
    required ComplaintStatus status,
    required String address,
    required GeoPoint location,
    required String reporterId,
    required String reporterName,
    required DateTime createdAt,
    required List<TimelineEvent> timeline,
    int supporters = 0,
    List<MediaAttachment> photos = const [],
    List<ComplaintComment> comments = const [],
    String? contractorId,
    String? jobId,
    CitizenFeedback? feedback,
    String? rejectionReason,
  }) {
    final supporterIds = _supporters(supporters);
    return Complaint(
      id: id,
      title: title,
      description: description,
      category: category,
      status: status,
      address: address,
      reporterId: reporterId,
      reporterName: reporterName,
      createdAt: createdAt,
      location: location,
      locationSource: LocationSource.manualPin,
      photos: photos,
      supporterIds: supporterIds,
      comments: comments,
      timeline: timeline,
      classification: _classifier.classify(title, description),
      department:
          status == ComplaintStatus.submitted || status == ComplaintStatus.draft
              ? null
              : category.department,
      contractorId: contractorId,
      jobId: jobId,
      feedback: feedback,
      rejectionReason: rejectionReason,
      priority: _engine.assess(
        category: category,
        title: title,
        description: description,
        supportCount: supporterIds.length,
        createdAt: createdAt,
        now: now,
        rules: PriorityRules.defaults,
      ),
    );
  }

  List<Contractor> contractors() => [
        Contractor(
          id: 'ctr-metro',
          name: 'Metro Roads & Works',
          registrationNo: 'MCR-2021-0417',
          specialties: const {
            ComplaintCategory.roadDamage,
            ComplaintCategory.drainage
          },
          status: ContractorStatus.approved,
          joinedAt: _ago(days: 640),
          ratingTotal: 23,
          ratingCount: 5,
          completedJobs: 5,
        ),
        Contractor(
          id: 'ctr-bright',
          name: 'BrightLine Electric',
          registrationNo: 'MCR-2022-1180',
          specialties: const {ComplaintCategory.streetlight},
          status: ContractorStatus.approved,
          joinedAt: _ago(days: 410),
          ratingTotal: 13,
          ratingCount: 3,
          completedJobs: 3,
        ),
        Contractor(
          id: 'ctr-green',
          name: 'GreenCycle Sanitation',
          registrationNo: 'MCR-2020-0093',
          specialties: const {
            ComplaintCategory.garbage,
            ComplaintCategory.drainage
          },
          status: ContractorStatus.approved,
          joinedAt: _ago(days: 900),
          ratingTotal: 18,
          ratingCount: 4,
          completedJobs: 4,
        ),
        Contractor(
          id: 'ctr-urban',
          name: 'UrbanFix Builders',
          registrationNo: 'MCR-2026-2231',
          specialties: const {
            ComplaintCategory.roadDamage,
            ComplaintCategory.other
          },
          status: ContractorStatus.pendingApproval,
          joinedAt: _ago(days: 2),
        ),
      ];

  List<Complaint> complaints() {
    final market = center;
    final station = center.offsetMeters(north: 600, east: -400);
    final park = center.offsetMeters(north: -500, east: 700);
    final playground = center.offsetMeters(north: 900, east: 900);
    final canal = center.offsetMeters(north: -800, east: -600);
    final clinic = center.offsetMeters(north: 200, east: 1200);
    final busStop = center.offsetMeters(north: -1200, east: 100);

    return [
      _complaint(
        id: 'CMP-1010',
        title: 'Water leaking from main pipe on Block 7 street',
        description:
            'Clean water has been leaking from a cracked pipe since morning. '
            'The street is getting muddy.',
        category: ComplaintCategory.drainage,
        status: ComplaintStatus.draft,
        address: 'Street 3, Block 7, Ward 4',
        location: center.offsetMeters(north: 300, east: 300),
        reporterId: Actor.demoCitizen.id,
        reporterName: Actor.demoCitizen.name,
        createdAt: _ago(hours: 3),
        timeline: const [],
      ),
      _complaint(
        id: 'CMP-1008',
        title: 'Broken road with big holes on Canal Road',
        description: 'Road is broken with many potholes near the canal '
            'service lane. Bikes are slipping at night.',
        category: ComplaintCategory.roadDamage,
        status: ComplaintStatus.submitted,
        address: 'Canal Road, near the footbridge',
        location: canal.offsetMeters(north: 60, east: 40),
        reporterId: 'cit-omar',
        reporterName: 'Omar Siddiqui',
        createdAt: _ago(hours: 6),
        supporters: 1,
        timeline: [
          _ev(ComplaintStatus.submitted, _ago(hours: 6), 'Omar Siddiqui',
              AppRole.citizen),
        ],
      ),
      _complaint(
        id: 'CMP-1007',
        title: 'Illegal garbage dumping behind bus stop',
        description: 'Trucks are dumping construction debris and household '
            'trash behind the Route 12 bus stop. Strong smell and mosquitoes.',
        category: ComplaintCategory.garbage,
        status: ComplaintStatus.submitted,
        address: 'Route 12 Bus Stop, University Road',
        location: busStop,
        reporterId: 'cit-fatima',
        reporterName: 'Fatima Noor',
        createdAt: _ago(days: 1, hours: 2),
        supporters: 3,
        photos: [_img('img-1007-a', 'Dumped debris behind the shelter')],
        timeline: [
          _ev(ComplaintStatus.submitted, _ago(days: 1, hours: 2), 'Fatima Noor',
              AppRole.citizen),
        ],
      ),
      _complaint(
        id: 'CMP-1006',
        title: 'Sewer overflowing outside Al-Shifa Clinic',
        description: 'Sewage water is overflowing from a blocked drain right '
            'at the clinic entrance. Patients have to walk through it.',
        category: ComplaintCategory.drainage,
        status: ComplaintStatus.verified,
        address: 'Clinic Lane, opposite Al-Shifa Clinic',
        location: clinic,
        reporterId: 'cit-daniel',
        reporterName: 'Daniel Mendes',
        createdAt: _ago(days: 2, hours: 4),
        supporters: 11,
        jobId: 'JOB-505',
        photos: [_img('img-1006-a', 'Overflow at clinic entrance')],
        timeline: [
          _ev(ComplaintStatus.submitted, _ago(days: 2, hours: 4),
              'Daniel Mendes', AppRole.citizen),
          _ev(
              ComplaintStatus.verified,
              _ago(days: 1, hours: 20),
              _officer,
              AppRole.municipalAdmin,
              'Verified by field inspector. Tender opened for desilting.'),
        ],
        comments: [
          ComplaintComment(
              id: 'c-1006-1',
              authorName: 'Fatima Noor',
              authorRole: AppRole.citizen,
              text: 'Same problem last monsoon. Please fix the drain properly.',
              at: _ago(days: 2)),
        ],
      ),
      _complaint(
        id: 'CMP-1005',
        title: 'Cluster of potholes on Canal Road service lane',
        description: 'Five deep potholes in a row on the service lane. Two '
            'motorcycle accidents reported this week.',
        category: ComplaintCategory.roadDamage,
        status: ComplaintStatus.assigned,
        address: 'Canal Road service lane, Ward 4',
        location: canal,
        reporterId: 'cit-imran',
        reporterName: 'Imran Qureshi',
        createdAt: _ago(days: 4, hours: 1),
        supporters: 6,
        contractorId: 'ctr-metro',
        jobId: 'JOB-504',
        photos: [_img('img-1005-a', 'Potholes along the service lane')],
        timeline: [
          _ev(ComplaintStatus.submitted, _ago(days: 4, hours: 1),
              'Imran Qureshi', AppRole.citizen),
          _ev(
              ComplaintStatus.verified,
              _ago(days: 3, hours: 18),
              _officer,
              AppRole.municipalAdmin,
              'Verified. Routed to Roads & Infrastructure.'),
          _ev(
              ComplaintStatus.assigned,
              _ago(days: 1, hours: 5),
              _officer,
              AppRole.municipalAdmin,
              'Awarded to Metro Roads & Works (best of 2 bids).'),
        ],
      ),
      _complaint(
        id: 'CMP-1003',
        title: 'Garbage overflowing at Community Park entrance',
        description: 'Waste bins at the park gate have not been collected for '
            'a week. Garbage is spilling onto the walkway where children play.',
        category: ComplaintCategory.garbage,
        status: ComplaintStatus.awaitingInspection,
        address: 'Community Park main gate, Ward 4',
        location: park,
        reporterId: Actor.demoCitizen.id,
        reporterName: Actor.demoCitizen.name,
        createdAt: _ago(days: 5, hours: 3),
        supporters: 21,
        contractorId: 'ctr-green',
        jobId: 'JOB-503',
        photos: [_img('img-1003-a', 'Overflowing bins at the gate')],
        timeline: [
          _ev(ComplaintStatus.submitted, _ago(days: 5, hours: 3),
              Actor.demoCitizen.name, AppRole.citizen),
          _ev(ComplaintStatus.verified, _ago(days: 5), _officer,
              AppRole.municipalAdmin, 'Verified. Routed to Sanitation.'),
          _ev(
              ComplaintStatus.assigned,
              _ago(days: 4, hours: 6),
              _officer,
              AppRole.municipalAdmin,
              'Directly assigned to GreenCycle Sanitation.'),
          _ev(
              ComplaintStatus.inProgress,
              _ago(days: 3),
              'GreenCycle Sanitation',
              AppRole.contractor,
              'Collection truck dispatched.'),
          _ev(
              ComplaintStatus.awaitingInspection,
              _ago(hours: 20),
              'GreenCycle Sanitation',
              AppRole.contractor,
              'Area cleared, two new 240L bins installed.'),
        ],
        comments: [
          ComplaintComment(
              id: 'c-1003-1',
              authorName: 'Sara Thomas',
              authorRole: AppRole.citizen,
              text: 'Walked past this morning — looks much cleaner!',
              at: _ago(hours: 10)),
        ],
      ),
      _complaint(
        id: 'CMP-1002',
        title: 'Six streetlights out along Station Road',
        description: 'The stretch from the railway crossing to the mosque is '
            'completely dark at night. Women and children feel unsafe walking.',
        category: ComplaintCategory.streetlight,
        status: ComplaintStatus.inProgress,
        address: 'Station Road, railway crossing to Masjid Chowk',
        location: station,
        reporterId: 'cit-bilal',
        reporterName: 'Bilal Ahmed',
        createdAt: _ago(days: 6, hours: 2),
        supporters: 9,
        contractorId: 'ctr-bright',
        jobId: 'JOB-502',
        photos: [_img('img-1002-a', 'Dark stretch of Station Road')],
        timeline: [
          _ev(ComplaintStatus.submitted, _ago(days: 6, hours: 2), 'Bilal Ahmed',
              AppRole.citizen),
          _ev(
              ComplaintStatus.verified,
              _ago(days: 5, hours: 12),
              _officer,
              AppRole.municipalAdmin,
              'Verified. Routed to Electrical Services.'),
          _ev(ComplaintStatus.assigned, _ago(days: 4), _officer,
              AppRole.municipalAdmin, 'Awarded to BrightLine Electric.'),
          _ev(ComplaintStatus.inProgress, _ago(days: 2), 'BrightLine Electric',
              AppRole.contractor, 'Faulty cable segment identified.'),
        ],
      ),
      _complaint(
        id: 'CMP-1001',
        title: 'Deep pothole outside Government Girls School gate',
        description: 'A deep pothole right at the school gate fills with water '
            'and children have to step into the road. A rickshaw tyre burst here.',
        category: ComplaintCategory.roadDamage,
        status: ComplaintStatus.resolved,
        address: 'Main Market Road, Govt. Girls School gate',
        location: market,
        reporterId: Actor.demoCitizen.id,
        reporterName: Actor.demoCitizen.name,
        createdAt: _ago(days: 12),
        supporters: 14,
        contractorId: 'ctr-metro',
        jobId: 'JOB-501',
        photos: [_img('img-1001-a', 'Pothole at the school gate')],
        timeline: [
          _ev(ComplaintStatus.submitted, _ago(days: 12), Actor.demoCitizen.name,
              AppRole.citizen),
          _ev(
              ComplaintStatus.verified,
              _ago(days: 11, hours: 20),
              _officer,
              AppRole.municipalAdmin,
              'Verified on site. Routed to Roads & Infrastructure.'),
          _ev(
              ComplaintStatus.assigned,
              _ago(days: 10),
              _officer,
              AppRole.municipalAdmin,
              'Awarded to Metro Roads & Works after 2 bids.'),
          _ev(ComplaintStatus.inProgress, _ago(days: 9), 'Metro Roads & Works',
              AppRole.contractor, 'Crew mobilised, area barricaded.'),
          _ev(
              ComplaintStatus.awaitingInspection,
              _ago(days: 8),
              'Metro Roads & Works',
              AppRole.contractor,
              'Pothole cut, filled and compacted. After photos attached.'),
          _ev(
              ComplaintStatus.resolved,
              _ago(days: 7),
              _officer,
              AppRole.municipalAdmin,
              'Inspection passed: surface level, drainage slope correct.'),
        ],
        comments: [
          ComplaintComment(
              id: 'c-1001-1',
              authorName: 'School Principal',
              authorRole: AppRole.citizen,
              text: 'Thank you, the gate area is safe again.',
              at: _ago(days: 6)),
        ],
      ),
      _complaint(
        id: 'CMP-1009',
        title: 'Damaged gate at housing society entrance',
        description: 'The sliding gate of our private society is broken.',
        category: ComplaintCategory.other,
        status: ComplaintStatus.rejected,
        address: 'Rose Villas private society',
        location: center.offsetMeters(north: 1500, east: -1500),
        reporterId: Actor.demoCitizen.id,
        reporterName: Actor.demoCitizen.name,
        createdAt: _ago(days: 9),
        rejectionReason:
            'Private property — outside municipal jurisdiction. Please '
            'contact your society management.',
        timeline: [
          _ev(ComplaintStatus.submitted, _ago(days: 9), Actor.demoCitizen.name,
              AppRole.citizen),
          _ev(
              ComplaintStatus.rejected,
              _ago(days: 8, hours: 20),
              _officer,
              AppRole.municipalAdmin,
              'Private property — outside municipal jurisdiction.'),
        ],
      ),
      _complaint(
        id: 'CMP-1004',
        title: 'Flickering streetlight near Gulshan playground',
        description: 'The lamp post beside the playground flickers and goes '
            'dark after 10pm.',
        category: ComplaintCategory.streetlight,
        status: ComplaintStatus.resolved,
        address: 'Gulshan Playground, west side',
        location: playground,
        reporterId: 'cit-sara',
        reporterName: 'Sara Thomas',
        createdAt: _ago(days: 20),
        supporters: 4,
        contractorId: 'ctr-bright',
        jobId: 'JOB-500',
        feedback: CitizenFeedback(
            rating: 4,
            comment: 'Fixed within a week. Thank you!',
            at: _ago(days: 13)),
        timeline: [
          _ev(ComplaintStatus.submitted, _ago(days: 20), 'Sara Thomas',
              AppRole.citizen),
          _ev(ComplaintStatus.verified, _ago(days: 19), _officer,
              AppRole.municipalAdmin),
          _ev(ComplaintStatus.assigned, _ago(days: 18), _officer,
              AppRole.municipalAdmin, 'Assigned to BrightLine Electric.'),
          _ev(ComplaintStatus.inProgress, _ago(days: 16), 'BrightLine Electric',
              AppRole.contractor),
          _ev(
              ComplaintStatus.awaitingInspection,
              _ago(days: 15),
              'BrightLine Electric',
              AppRole.contractor,
              'Replaced ballast and LED fitting.'),
          _ev(ComplaintStatus.resolved, _ago(days: 14), _officer,
              AppRole.municipalAdmin, 'Night inspection passed.'),
        ],
      ),
    ];
  }

  List<WorkJob> jobs() => [
        WorkJob(
          id: 'JOB-505',
          complaintId: 'CMP-1006',
          title: 'Desilt and repair blocked sewer at Clinic Lane',
          category: ComplaintCategory.drainage,
          department: ComplaintCategory.drainage.department,
          budgetEstimate: 150000,
          status: JobStatus.openForBids,
          createdAt: _ago(days: 1, hours: 20),
          bids: [
            Bid(
                id: 'bid-505-1',
                contractorId: 'ctr-green',
                contractorName: 'GreenCycle Sanitation',
                amount: 142000,
                days: 3,
                note: 'Jetting machine available immediately.',
                at: _ago(days: 1, hours: 4)),
          ],
        ),
        WorkJob(
          id: 'JOB-504',
          complaintId: 'CMP-1005',
          title: 'Patch potholes on Canal Road service lane',
          category: ComplaintCategory.roadDamage,
          department: ComplaintCategory.roadDamage.department,
          budgetEstimate: 130000,
          status: JobStatus.awarded,
          createdAt: _ago(days: 3, hours: 16),
          contractorId: 'ctr-metro',
          contractorName: 'Metro Roads & Works',
          awardedAmount: 118000,
          paymentStatus: PaymentStatus.heldSimulated,
          bids: [
            Bid(
                id: 'bid-504-1',
                contractorId: 'ctr-metro',
                contractorName: 'Metro Roads & Works',
                amount: 118000,
                days: 4,
                note: 'Hot-mix patching for all five potholes.',
                at: _ago(days: 3)),
            Bid(
                id: 'bid-504-2',
                contractorId: 'ctr-urban',
                contractorName: 'UrbanFix Builders',
                amount: 109000,
                days: 7,
                note: 'Cold-mix patching.',
                at: _ago(days: 2, hours: 20)),
          ],
        ),
        WorkJob(
          id: 'JOB-503',
          complaintId: 'CMP-1003',
          title: 'Clear waste and install bins at Community Park',
          category: ComplaintCategory.garbage,
          department: ComplaintCategory.garbage.department,
          budgetEstimate: 30000,
          status: JobStatus.completionSubmitted,
          createdAt: _ago(days: 4, hours: 6),
          contractorId: 'ctr-green',
          contractorName: 'GreenCycle Sanitation',
          awardedAmount: 26000,
          paymentStatus: PaymentStatus.heldSimulated,
          beforePhotos: [
            _img('img-503-b', 'Overflowing bins before clearing',
                EvidenceStage.before)
          ],
          afterPhotos: [
            _img('img-503-a', 'Cleared gate with new bins', EvidenceStage.after)
          ],
          progressLogs: [
            ProgressLog(
                id: 'log-503-1',
                note: 'Collected 1.2 tonnes of waste.',
                at: _ago(days: 3),
                authorName: 'GreenCycle Sanitation'),
            ProgressLog(
                id: 'log-503-2',
                note: 'Installed two 240L bins with lids.',
                at: _ago(hours: 21),
                authorName: 'GreenCycle Sanitation'),
          ],
        ),
        WorkJob(
          id: 'JOB-502',
          complaintId: 'CMP-1002',
          title: 'Restore six streetlights on Station Road',
          category: ComplaintCategory.streetlight,
          department: ComplaintCategory.streetlight.department,
          budgetEstimate: 45000,
          status: JobStatus.inProgress,
          createdAt: _ago(days: 5),
          contractorId: 'ctr-bright',
          contractorName: 'BrightLine Electric',
          awardedAmount: 42000,
          paymentStatus: PaymentStatus.heldSimulated,
          beforePhotos: [
            _img('img-502-b', 'Unlit poles at night', EvidenceStage.before)
          ],
          progressLogs: [
            ProgressLog(
                id: 'log-502-1',
                note: 'Fault traced to underground cable near pole 3.',
                at: _ago(days: 2),
                authorName: 'BrightLine Electric'),
            ProgressLog(
                id: 'log-502-2',
                note: 'Cable replaced; 4 of 6 lights restored.',
                at: _ago(hours: 18),
                authorName: 'BrightLine Electric'),
          ],
        ),
        WorkJob(
          id: 'JOB-501',
          complaintId: 'CMP-1001',
          title: 'Repair pothole at Govt. Girls School gate',
          category: ComplaintCategory.roadDamage,
          department: ComplaintCategory.roadDamage.department,
          budgetEstimate: 90000,
          status: JobStatus.completed,
          createdAt: _ago(days: 11),
          contractorId: 'ctr-metro',
          contractorName: 'Metro Roads & Works',
          awardedAmount: 85000,
          paymentStatus: PaymentStatus.releasedSimulated,
          completedAt: _ago(days: 7),
          inspectionNote:
              'Inspection passed: surface level, drainage slope correct.',
          bids: [
            Bid(
                id: 'bid-501-1',
                contractorId: 'ctr-metro',
                contractorName: 'Metro Roads & Works',
                amount: 85000,
                days: 2,
                note: 'Full-depth patch with compaction.',
                at: _ago(days: 10, hours: 20)),
            Bid(
                id: 'bid-501-2',
                contractorId: 'ctr-green',
                contractorName: 'GreenCycle Sanitation',
                amount: 92000,
                days: 3,
                note: 'Includes drain cover replacement.',
                at: _ago(days: 10, hours: 18)),
          ],
          beforePhotos: [
            _img('img-501-b', 'Pothole before repair', EvidenceStage.before)
          ],
          afterPhotos: [
            _img('img-501-a', 'Resurfaced gate area', EvidenceStage.after)
          ],
          progressLogs: [
            ProgressLog(
                id: 'log-501-1',
                note: 'Area barricaded; cutting damaged asphalt.',
                at: _ago(days: 9),
                authorName: 'Metro Roads & Works'),
          ],
        ),
        WorkJob(
          id: 'JOB-500',
          complaintId: 'CMP-1004',
          title: 'Fix flickering lamp at Gulshan playground',
          category: ComplaintCategory.streetlight,
          department: ComplaintCategory.streetlight.department,
          budgetEstimate: 20000,
          status: JobStatus.completed,
          createdAt: _ago(days: 18),
          contractorId: 'ctr-bright',
          contractorName: 'BrightLine Electric',
          awardedAmount: 18000,
          paymentStatus: PaymentStatus.releasedSimulated,
          completedAt: _ago(days: 14),
          beforePhotos: [
            _img('img-500-b', 'Flickering lamp', EvidenceStage.before)
          ],
          afterPhotos: [
            _img('img-500-a', 'New LED fitting', EvidenceStage.after)
          ],
        ),
      ];

  List<AppNotification> notifications() => [
        AppNotification(
          id: 'n-1',
          recipientId: Actor.demoCitizen.id,
          title: 'CMP-1003 is awaiting inspection',
          body: 'GreenCycle Sanitation reported the park entrance is cleared.',
          at: _ago(hours: 20),
          complaintId: 'CMP-1003',
        ),
        AppNotification(
          id: 'n-2',
          recipientId: Actor.demoCitizen.id,
          title: 'CMP-1001 resolved — rate the work',
          body: 'Your pothole report passed inspection. Tell us how we did.',
          at: _ago(days: 7),
          complaintId: 'CMP-1001',
        ),
        AppNotification(
          id: 'n-3',
          recipientId: Actor.demoContractor.id,
          title: 'JOB-504 awarded to you',
          body: 'Canal Road potholes — start work when your crew is ready.',
          at: _ago(days: 1, hours: 5),
          jobId: 'JOB-504',
        ),
      ];
}
