import 'package:cloud_firestore/cloud_firestore.dart';

class Request {
  final String id;
  final String requestId;
  final String title;
  final String description;
  final String status;
  final String priority;
  final DateTime? createdAt;
  final String createdBy;
  final String? createdByEmail;
  final String? createdByUsername;
  final String facilityId;
  final List<Map<String, String>> attachments;
  final List<Map<String, dynamic>> comments;
  final List<String> workOrderIds;
  final String clientStatus;

  // Equipment this job is about (facilities/{facilityId}/equipment/{equipmentId}). Optional; the
  // name is copied so lists can show it without an extra read, and spaceId places it on a floor/room.
  final String? equipmentId;
  final String? equipmentName;
  final String? spaceId;

  Request({
    required this.id,
    required this.requestId,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    this.createdAt,
    required this.createdBy,
    this.createdByEmail,
    this.createdByUsername,
    required this.facilityId,
    required this.attachments,
    required this.comments,
    required this.workOrderIds,
    required this.clientStatus,
    this.equipmentId,
    this.equipmentName,
    this.spaceId,
  });

  factory Request.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Request.fromMap(data, doc.id);
  }

  factory Request.fromMap(Map<String, dynamic> data, String id) {
    return Request(
      id: id,
      requestId: data['requestId'] ?? id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      status: data['status'] ?? 'Open',
      priority: data['priority'] ?? 'Medium',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] ?? '',
      createdByEmail: data['createdByEmail'],
      createdByUsername: data['createdByUsername'],
      facilityId: data['facilityId'] ?? '',
      attachments: (data['attachments'] as List<dynamic>?)
          ?.map((item) => Map<String, String>.from(item as Map))
          .toList() ?? [],
      comments: (data['comments'] as List<dynamic>?)
          ?.map((item) => Map<String, dynamic>.from(item as Map))
          .toList() ?? [],
      workOrderIds: (data['workOrderIds'] as List<dynamic>?)
          ?.map((item) => item.toString())
          .toList() ?? [],
      clientStatus: data['clientStatus'] ?? 'Pending',
      equipmentId: data['equipmentId'] as String?,
      equipmentName: data['equipmentName'] as String?,
      spaceId: data['spaceId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'title': title,
      'description': description,
      'status': status,
      'priority': priority,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'createdBy': createdBy,
      'createdByEmail': createdByEmail,
      'createdByUsername': createdByUsername,
      'facilityId': facilityId,
      'attachments': attachments,
      'comments': comments,
      'workOrderIds': workOrderIds,
      'clientStatus': clientStatus,
      if (equipmentId != null) 'equipmentId': equipmentId,
      if (equipmentName != null) 'equipmentName': equipmentName,
      if (spaceId != null) 'spaceId': spaceId,
    };
  }
}