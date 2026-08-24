import 'package:cloud_firestore/cloud_firestore.dart';

/// One notification kind's slice of the read/open engagement window — counts and timings only,
/// mirroring the aggregation the `aggregateNotificationEngagement` Cloud Function computes.
class EngagementKindStat {
  final String kind;
  final int total;
  final int read;
  final double readRate;
  final double? avgMinutesToRead;

  const EngagementKindStat({
    required this.kind,
    required this.total,
    required this.read,
    required this.readRate,
    this.avgMinutesToRead,
  });

  factory EngagementKindStat.fromMap(Map<String, dynamic> map) {
    return EngagementKindStat(
      kind: map['kind'] ?? '',
      total: map['total'] ?? 0,
      read: map['read'] ?? 0,
      readRate: (map['readRate'] as num?)?.toDouble() ?? 0,
      avgMinutesToRead: (map['avgMinutesToRead'] as num?)?.toDouble(),
    );
  }
}

/// Developer/admin-only read/open engagement summary — `NotificationEngagementStats/latest`,
/// written daily by the `aggregateNotificationEngagement` Cloud Function. Deliberately
/// content-free (no titles/bodies/task details) to preserve the same per-user privacy boundary as
/// `NotificationDigests` itself.
class EngagementStats {
  final int windowDays;
  final int total;
  final int totalRead;
  final double readRate;
  final double? avgMinutesToRead;
  final List<EngagementKindStat> kindBreakdown;
  final DateTime? computedAt;

  const EngagementStats({
    required this.windowDays,
    required this.total,
    required this.totalRead,
    required this.readRate,
    this.avgMinutesToRead,
    required this.kindBreakdown,
    this.computedAt,
  });

  factory EngagementStats.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawBreakdown = data['kindBreakdown'] as List<dynamic>? ?? [];
    return EngagementStats(
      windowDays: data['windowDays'] ?? 30,
      total: data['total'] ?? 0,
      totalRead: data['totalRead'] ?? 0,
      readRate: (data['readRate'] as num?)?.toDouble() ?? 0,
      avgMinutesToRead: (data['avgMinutesToRead'] as num?)?.toDouble(),
      kindBreakdown: rawBreakdown.map((e) => EngagementKindStat.fromMap(Map<String, dynamic>.from(e))).toList(),
      computedAt: (data['computedAt'] as Timestamp?)?.toDate(),
    );
  }
}
