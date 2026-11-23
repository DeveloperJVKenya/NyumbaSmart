import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/models/user_model.dart';
import 'package:cmms/models/work_order.dart';
import 'package:cmms/notifications/providers/notification_providers.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/widgets/equipment_picker_field.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:cmms/utils/file_download_helper.dart';

class WorkOrderScreen extends ConsumerStatefulWidget {
  final String facilityId;

  /// When set (e.g. "New work order" from an equipment card or the 3D viewer), the create form
  /// opens straight away with this equipment already chosen.
  final EquipmentRef? initialEquipment;

  const WorkOrderScreen({super.key, required this.facilityId, this.initialEquipment});

  @override
  ConsumerState<WorkOrderScreen> createState() => _WorkOrderScreenState();
}

class _WorkOrderScreenState extends ConsumerState<WorkOrderScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();
  final Logger _logger = Logger(printer: PrettyPrinter());
  final ImagePicker _imagePicker = ImagePicker();
    
  String _priority = 'Medium';
  String _statusFilter = 'All';
  String _priorityFilter = 'All';
  String _workOrderStatusFilter = 'All';
  bool _isClientStatusFilterMode = true;
  bool _isInApprovedSubView = false; // Track if we're in the approved sub-view
  String? _selectedRequestId;
  String? _selectedTechnicianId;
  String? _selectedTechnicianEmail;
  EquipmentRef? _selectedEquipment;
  final List<Map<String, String>> _attachmentUrls = [];
  bool _showForm = false;
  String _currentRole = 'User';
  String _organization = '-';
  bool _isJVAlmacisUser = false;
  bool _isAdminClient = false;
  String? _createdByEmail;
  String? _createdByUsername;
  final Map<String, String> _usernameCache = {};
  double? _uploadProgress;
  late TabController _tabController;
  bool _isSubmitting = false;

  // Client status counts (removed declined)
  int _allCount = 0;
  int _approvedCount = 0;
  int _toBeReviewedCount = 0;

  // Priority counts
  int _allPriorityCount = 0;
  int _highPriorityCount = 0;
  int _mediumPriorityCount = 0;
  int _lowPriorityCount = 0;

  // Work order status counts (for approved sub-view)
  int _approvedAllCount = 0;
  int _approvedOpenCount = 0;
  int _approvedInProgressCount = 0;
  int _approvedCompletedCount = 0;

  // Cache for all work orders to avoid repeated queries
  List<QueryDocumentSnapshot> _allWorkOrders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadCreatedBy();
    if (widget.initialEquipment != null) {
      _selectedEquipment = widget.initialEquipment;
      _showForm = true;
    }
    _logger.i('WorkOrderScreen initialized: facilityId=${widget.facilityId}');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCreatedBy() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final uid = user.uid;
      String? username;
      for (final col in ['Admins', 'Developers', 'Technicians', 'Users']) {
        final doc = await FirebaseFirestore.instance.collection(col).doc(uid).get();
        if (doc.exists) {
          final d = doc.data()!;
          username = d['username'] as String? ?? d['name'] as String? ?? d['displayName'] as String?;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _createdByEmail = user.email;
          _createdByUsername = username;
        });
      }
    } catch (e) {
      _logger.e('Error loading user display name: $e');
    }
  }

  Future<String> _getUsernameFromCollection(String userId) async {
    if (_usernameCache.containsKey(userId)) return _usernameCache[userId]!;
    try {
      String? found;
      for (final col in ['Users', 'Admins', 'Technicians', 'Developers']) {
        final doc = await FirebaseFirestore.instance.collection(col).doc(userId).get();
        if (doc.exists) {
          final d = doc.data()!;
          final u = (d['username'] ?? d['name'] ?? d['displayName']) as String?;
          if (u != null && u.isNotEmpty) { found = u; break; }
        }
      }
      if (found == null) {
        final authUser = await FirebaseAuth.instance.userChanges().first;
        if (authUser != null && authUser.uid == userId) found = authUser.email;
      }
      final result = found ?? 'Unknown User';
      _usernameCache[userId] = result;
      return result;
    } catch (e) {
      _logger.e('Error fetching username for user $userId: $e');
      return 'Unknown User';
    }
  }

  // Modified method to fetch request title without ID
  Future<String> _getRequestTitleFromId(String requestId) async {
    try {
      final requestDoc = await FirebaseFirestore.instance
          .collection('Work_Requests')
          .doc(requestId)
          .get();
          
      if (requestDoc.exists) {
        final requestData = requestDoc.data()!;
        final title = requestData['title'] ?? 'Untitled Request';
        return title; // Removed ID from display
      }
          
      return 'Untitled Request';
    } catch (e) {
      _logger.e('Error fetching request title for $requestId: $e');
      return 'Untitled Request';
    }
  }

  Future<void> _addWorkOrder() async {
    if (_formKey.currentState!.validate()) {
      if (_isSubmitting) return;
          
      setState(() {
        _isSubmitting = true;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isSubmitting = false;
        });
        if (mounted) _showSnackBar('Please log in to add work orders');
        return;
      }

      try {
        final workOrderId = const Uuid().v4();
        _logger.i('Adding work order: workOrderId=$workOrderId, title=${_titleController.text}');

        final workOrder = WorkOrder(
          id: workOrderId,
          workOrderId: workOrderId,
          requestId: _selectedRequestId,
          title: _titleController.text,
          description: _descriptionController.text,
          status: 'Open',
          priority: _priority,
          assignedTo: _selectedTechnicianId ?? '',
          assignedToEmail: _selectedTechnicianEmail ?? '',
          createdAt: DateTime.now(),
          createdBy: user.uid,
          createdByEmail: _createdByEmail ?? '',
          facilityId: widget.facilityId,
          attachments: List<Map<String, String>>.from(_attachmentUrls),
          history: [
            {
              'action': 'Work Order Created',
              'timestamp': Timestamp.now(),
              'notes': _notesController.text,
              'userId': user.uid,
              'userEmail': _createdByEmail,
              'username': _createdByUsername ?? _createdByEmail ?? 'Unknown User',
            }
          ],
          clientStatus: 'To be Reviewed',
          clientNotes: '',
          equipmentId: _selectedEquipment?.id,
          equipmentName: _selectedEquipment?.name,
          spaceId: _selectedEquipment?.spaceId,
        );

        await FirebaseFirestore.instance
            .collection('Work_Orders')
            .doc(workOrderId)
            .set(workOrder.toMap());

        if (_selectedEquipment != null) {
          await appendEquipmentHistory(
            facilityId: widget.facilityId,
            equipmentId: _selectedEquipment!.id,
            action: 'Work order opened: ${_titleController.text}',
            notes: _descriptionController.text,
            userId: user.uid,
          );
        }

        // Update the related request if selected
        if (_selectedRequestId != null) {
          await FirebaseFirestore.instance
              .collection('Work_Requests')
              .doc(_selectedRequestId)
              .update({
            'workOrderIds': FieldValue.arrayUnion([workOrderId]),
            'status': 'In Progress',
          });
        }

        // Notify assigned technician (in-app) and JV Almacis team (custom notification)
        final capturedTitle = _titleController.text.trim();
        final capturedPriority = _priority;
        final capturedTechId = _selectedTechnicianId;
        final notifService = ref.read(notificationServiceProvider);
        try {
          if (capturedTechId != null && capturedTechId.isNotEmpty) {
            await notifService.sendInAppNotification(
              targetUserId: capturedTechId,
              title: 'Work Order Assigned: $capturedTitle',
              body: 'You have been assigned a new work order. Priority: $capturedPriority.',
              priority: capturedPriority == 'High' ? 'urgent' : 'normal',
            );
          }
          await notifService.createCustomNotification(
            facilityId: widget.facilityId,
            title: 'Work Order Created: $capturedTitle',
            body: 'A new work order has been created. Priority: $capturedPriority.',
            priority: capturedPriority == 'High' ? 'urgent' : 'normal',
          );
        } catch (e) {
          _logger.w('Notification after WO creation failed (non-fatal): $e');
        }

        if (mounted) {
          setState(() {
            _attachmentUrls.clear();
            _selectedRequestId = null;
            _selectedTechnicianId = null;
            _selectedTechnicianEmail = null;
            _selectedEquipment = null;
            _showForm = false;
            _isSubmitting = false;
          });
          _titleController.clear();
          _descriptionController.clear();
          _notesController.clear();
          _showSnackBar('Work Order created successfully');
        }
      } catch (e) {
        _logger.e('Error adding work order: $e');
        setState(() {
          _isSubmitting = false;
        });
        if (mounted) _showSnackBar('Error: $e');
      }
    } else {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _uploadImageAttachment() async {
    try {
      _logger.i('Picking image attachment');
          
      XFile? pickedFile;
      if (kIsWeb) {
        pickedFile = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );
      } else {
        final ImageSource? source = await showDialog<ImageSource>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Select Image Source', style: GoogleFonts.poppins()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: Text('Camera', style: GoogleFonts.poppins()),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: Text('Gallery', style: GoogleFonts.poppins()),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
                
        if (source != null) {
          pickedFile = await _imagePicker.pickImage(
            source: source,
            maxWidth: 1920,
            maxHeight: 1080,
            imageQuality: 85,
          );
        }
      }

      if (pickedFile == null) {
        _logger.w('No image selected');
        return;
      }

      await _processAndUploadFile(pickedFile.name, await pickedFile.readAsBytes());
    } catch (e) {
      _logger.e('Error picking image: $e');
      if (mounted) _showSnackBar('Error selecting image: $e');
    }
  }

  Future<void> _uploadDocumentAttachment() async {
    try {
      _logger.i('Picking document attachment');
      final platformFile = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'doc', 'txt'],
      );

      if (platformFile == null) {
        _logger.w('No document selected');
        return;
      }

      final fileBytes = await platformFile.readAsBytes();

      await _processAndUploadFile(platformFile.name, fileBytes);
    } catch (e) {
      _logger.e('Error picking document: $e');
      if (mounted) _showSnackBar('Error selecting document: $e');
    }
  }

  Future<void> _processAndUploadFile(String fileName, Uint8List fileBytes) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) _showSnackBar('Please sign in to upload attachments');
      return;
    }

    if (!mounted) return;

    final bool? confirmUpload = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Upload', style: GoogleFonts.poppins()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getFileIcon(fileName),
              size: 48,
              color: _getFileIconColor(fileName),
            ),
            const SizedBox(height: 16),
            Text(
              'Upload: $fileName?',
              style: GoogleFonts.poppins(),
              textAlign: TextAlign.center,
            ),
            Text(
              'Size: ${(fileBytes.length / 1024 / 1024).toStringAsFixed(2)} MB',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Upload', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );

    if (confirmUpload != true) return;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Uploading $fileName', style: GoogleFonts.poppins()),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: _uploadProgress,
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueGrey),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _uploadProgress != null
                        ? '${(_uploadProgress! * 100).toStringAsFixed(0)}%'
                        : 'Starting upload...',
                    style: GoogleFonts.poppins(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('facilities/${widget.facilityId}/work_orders/${timestamp}_$fileName');

      final metadata = SettableMetadata(
        contentType: _getContentType(fileName),
        customMetadata: {
          'uploadedBy': user.uid,
          'originalName': fileName,
          'platform': kIsWeb ? 'web' : Platform.operatingSystem,
          'facilityId': widget.facilityId,
        },
      );

      final uploadTask = storageRef.putData(fileBytes, metadata);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (mounted) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      }, onError: (e) {
        _logger.e('Upload progress error: $e');
      });

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();

      if (mounted) {
        setState(() {
          _attachmentUrls.add({'name': fileName, 'url': downloadUrl});
          _uploadProgress = null;
        });
        Navigator.pop(context);
        _showSnackBar('Attachment uploaded successfully');
      }

      _logger.i('Attachment uploaded: $fileName, URL: $downloadUrl');
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadProgress = null;
        });
        Navigator.pop(context);
        _showSnackBar('Error uploading attachment: $e');
      }
      _logger.e('Error uploading attachment: $e');
    }
  }

  String _getContentType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'doc':
        return 'application/msword';
      case 'txt':
        return 'text/plain';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _viewAttachment(String url, String fileName) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading file...', style: GoogleFonts.poppins()),
          ],
        ),
      ),
    );

    try {
      if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        Navigator.pop(context);
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not open file in browser';
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        final extension = fileName.toLowerCase().split('.').last;
        if (['jpg', 'jpeg', 'png'].contains(extension)) {
          Navigator.pop(context);
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ImageViewerScreen(
                  imageUrl: url,
                  fileName: fileName,
                ),
              ),
            );
          }
        } else {
          Navigator.pop(context);
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            throw 'Could not open file';
          }
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error viewing file: $e');
      }
      _logger.e('Error viewing file: $e');
    }
  }

  // UPDATED: Use the new FileDownloadHelper instead of direct MANAGE_EXTERNAL_STORAGE
  Future<void> _downloadAttachment(String url, String fileName) async {
    await FileDownloadHelper.downloadFile(
      context: context,
      url: url,
      fileName: fileName,
      showSnackBar: _showSnackBar,
    );
  }

  Future<void> _updateClientStatus(String docId, String newStatus, String notes) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      _logger.i('Updating client status: docId=$docId, newStatus=$newStatus');
          
      // Create history entry with more detailed information
      final historyEntry = {
        'action': 'Client Status: $newStatus',
        'timestamp': Timestamp.now(),
        'notes': notes.isNotEmpty ? notes : 'No additional comments',
        'userId': user.uid,
        'userEmail': _createdByEmail,
        'username': _createdByUsername ?? _createdByEmail ?? 'Unknown User',
        'previousStatus': null, // Will be filled by getting current status first
      };

      // Get current status for history tracking
      final currentDoc = await FirebaseFirestore.instance
          .collection('Work_Orders')
          .doc(docId)
          .get();
          
      if (currentDoc.exists) {
        final currentData = currentDoc.data() as Map<String, dynamic>;
        historyEntry['previousStatus'] = currentData['clientStatus'] ?? 'Unknown';
      }

      await FirebaseFirestore.instance
          .collection('Work_Orders')
          .doc(docId)
          .update({
        'clientStatus': newStatus,
        'clientNotes': notes,
        'clientActionDate': Timestamp.now(),
        'history': FieldValue.arrayUnion([historyEntry]),
      });

      // Notify the original requester of the approval/decline decision
      if (currentDoc.exists && (newStatus == 'Approved' || newStatus == 'Declined')) {
        final data = currentDoc.data() as Map<String, dynamic>;
        final requesterId = data['createdBy'] as String?;
        final title = data['title'] as String? ?? 'Work Order';
        if (requesterId != null && requesterId.isNotEmpty) {
          try {
            await ref.read(notificationServiceProvider).sendInAppNotification(
              targetUserId: requesterId,
              title: 'Work Order $newStatus: $title',
              body: notes.isNotEmpty
                  ? 'Your work order was $newStatus. Note: $notes'
                  : 'Your work order has been $newStatus.',
              priority: newStatus == 'Declined' ? 'urgent' : 'normal',
            );
          } catch (e) {
            _logger.w('Notification to requester failed (non-fatal): $e');
          }
        }
      }

      if (mounted) {
        _showSnackBar(
          newStatus == 'To be Reviewed'
           ? 'Work order sent for review'
          : 'Work order $newStatus successfully'
        );
      }
    } catch (e) {
      _logger.e('Error updating client status: $e');
      if (mounted) _showSnackBar('Error updating status: $e');
    }
  }

  Future<void> _updateStatus(String docId, String newStatus, String notes) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      _logger.i('Updating status: docId=$docId, newStatus=$newStatus');

      final workOrderRef = FirebaseFirestore.instance.collection('Work_Orders').doc(docId);
      await workOrderRef.update({
        'status': newStatus,
        'history': FieldValue.arrayUnion([
          {
            'action': 'Status changed to $newStatus',
            'timestamp': Timestamp.now(),
            'notes': notes,
            'userId': user.uid,
            'userEmail': _createdByEmail,
            'username': _createdByUsername ?? _createdByEmail ?? 'Unknown User',
          }
        ]),
      });

      // Record progress on the linked equipment so its history shows the work done on it.
      final snap = await workOrderRef.get();
      final woData = snap.data();
      if (newStatus == 'Completed' || newStatus == 'In Progress') {
        final equipmentId = woData?['equipmentId'] as String?;
        if (equipmentId != null) {
          await appendEquipmentHistory(
            facilityId: widget.facilityId,
            equipmentId: equipmentId,
            action: 'Work order ${newStatus == 'Completed' ? 'completed' : 'started'}: ${woData?['title'] ?? ''}',
            notes: notes,
            userId: user.uid,
          );
        }
      }

      // Notify the original requester of the status change
      final requesterId = woData?['createdBy'] as String?;
      final woTitle = woData?['title'] as String? ?? 'Work Order';
      if (requesterId != null && requesterId.isNotEmpty && requesterId != user.uid) {
        try {
          await ref.read(notificationServiceProvider).sendInAppNotification(
            targetUserId: requesterId,
            title: 'Work Order Update: $woTitle',
            body: 'Status changed to $newStatus.${notes.isNotEmpty ? ' Note: $notes' : ''}',
            priority: newStatus == 'Completed' ? 'normal' : 'normal',
          );
        } catch (e) {
          _logger.w('Status-change notification failed (non-fatal): $e');
        }
      }

      if (mounted) _showSnackBar('Status updated to $newStatus');
    } catch (e) {
      _logger.e('Error updating status: $e');
      if (mounted) _showSnackBar('Error updating status: $e');
    }
  }

  // Update client status counts from all work orders (removed declined)
  void _updateClientStatusCounts(List<QueryDocumentSnapshot> allDocs) {
    final newAllCount = allDocs.length;
    int newApprovedCount = 0;
    int newToBeReviewedCount = 0;

    for (var doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final clientStatus = data['clientStatus'] ?? 'To be Reviewed';
      switch (clientStatus) {
        case 'Approved':
          newApprovedCount++;
          break;
        case 'To be Reviewed':
          newToBeReviewedCount++;
          break;
        // Handle legacy "Declined" status by treating as "To be Reviewed"
        case 'Declined':
          newToBeReviewedCount++;
          break;
      }
    }

    // Only update if counts actually changed
    if (_allCount != newAllCount ||
        _approvedCount != newApprovedCount ||
        _toBeReviewedCount != newToBeReviewedCount) {
          
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _allCount = newAllCount;
            _approvedCount = newApprovedCount;
            _toBeReviewedCount = newToBeReviewedCount;
          });
        }
      });
    }
  }

  // Update priority counts from all work orders
  void _updatePriorityCounts(List<QueryDocumentSnapshot> allDocs) {
    final newAllPriorityCount = allDocs.length;
    int newHighPriorityCount = 0;
    int newMediumPriorityCount = 0;
    int newLowPriorityCount = 0;

    for (var doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final priority = data['priority'] ?? 'Medium';
      switch (priority) {
        case 'High':
          newHighPriorityCount++;
          break;
        case 'Medium':
          newMediumPriorityCount++;
          break;
        case 'Low':
          newLowPriorityCount++;
          break;
      }
    }

    // Only update if counts actually changed
    if (_allPriorityCount != newAllPriorityCount ||
        _highPriorityCount != newHighPriorityCount ||
        _mediumPriorityCount != newMediumPriorityCount ||
        _lowPriorityCount != newLowPriorityCount) {
          
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _allPriorityCount = newAllPriorityCount;
            _highPriorityCount = newHighPriorityCount;
            _mediumPriorityCount = newMediumPriorityCount;
            _lowPriorityCount = newLowPriorityCount;
          });
        }
      });
    }
  }

  // Update work order status counts for approved items
  void _updateWorkOrderStatusCounts(List<QueryDocumentSnapshot> approvedDocs) {
    final newApprovedAllCount = approvedDocs.length;
    int newApprovedOpenCount = 0;
    int newApprovedInProgressCount = 0;
    int newApprovedCompletedCount = 0;

    for (var doc in approvedDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] ?? 'Open';
      switch (status) {
        case 'Open':
          newApprovedOpenCount++;
          break;
        case 'In Progress':
          newApprovedInProgressCount++;
          break;
        case 'Completed':
          newApprovedCompletedCount++;
          break;
      }
    }

    // Only update if counts actually changed
    if (_approvedAllCount != newApprovedAllCount ||
        _approvedOpenCount != newApprovedOpenCount ||
        _approvedInProgressCount != newApprovedInProgressCount ||
        _approvedCompletedCount != newApprovedCompletedCount) {
          
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _approvedAllCount = newApprovedAllCount;
            _approvedOpenCount = newApprovedOpenCount;
            _approvedInProgressCount = newApprovedInProgressCount;
            _approvedCompletedCount = newApprovedCompletedCount;
          });
        }
      });
    }
  }

  // Get filtered work orders from cached data
  List<QueryDocumentSnapshot> _getFilteredWorkOrders() {
    if (_isInApprovedSubView) {
      // Filter approved work orders by work order status
      final approvedDocs = _allWorkOrders.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['clientStatus'] == 'Approved';
      }).toList();
          
      if (_workOrderStatusFilter != 'All') {
        return approvedDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['status'] == _workOrderStatusFilter;
        }).toList();
      }
      return approvedDocs;
    } else if (_isClientStatusFilterMode && _statusFilter != 'All') {
      return _allWorkOrders.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final clientStatus = data['clientStatus'] ?? 'To be Reviewed';
        // Handle legacy "Declined" status by treating as "To be Reviewed"
        if (clientStatus == 'Declined' && _statusFilter == 'To be Reviewed') {
          return true;
        }
        return clientStatus == _statusFilter;
      }).toList();
    } else if (!_isClientStatusFilterMode && _priorityFilter != 'All') {
      return _allWorkOrders.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['priority'] == _priorityFilter;
      }).toList();
    }
    return _allWorkOrders;
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.poppins()),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserRoleProvider, (_, next) {
      final info = next.value;
      if (info == null || !mounted) return;
      setState(() {
        _currentRole = info.roleLabel;
        _organization = info.organization;
        _isJVAlmacisUser = info.isServiceProviderOrg;
        _isAdminClient = info.role == UserRole.admin && info.isClient;
      });
    });
    return ResponsiveScreenWrapper(
      title: 'Work Orders',
      facilityId: widget.facilityId,
      currentRole: _currentRole,
      organization: _organization,
      floatingActionButton: _isJVAlmacisUser
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _showForm = !_showForm),
              backgroundColor: AppColors.primary,
              icon: Icon(_showForm ? Icons.close_rounded : Icons.add_rounded, color: Colors.white),
              label: Text(
                _showForm ? 'Cancel' : 'New Work Order',
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
            )
          : null,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final isTablet = screenWidth > 600 && screenWidth <= 900;
    final padding = isMobile ? 16.0 : isTablet ? 24.0 : 32.0;
    final fontSizeTitle = isMobile ? 20.0 : isTablet ? 24.0 : 28.0;
    final fontSizeSubtitle = isMobile ? 14.0 : isTablet ? 16.0 : 18.0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(padding, 16.0, padding, padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter header card
          Container(
            padding: EdgeInsets.symmetric(horizontal: padding, vertical: 14),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.surfaceAltColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isInApprovedSubView) ...[
                  Row(
                    children: [
                      InkWell(
                        onTap: () => setState(() {
                          _isInApprovedSubView = false;
                          _workOrderStatusFilter = 'All';
                        }),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text('Back', style: GoogleFonts.poppins(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Approved Work Orders',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: context.textPrimary, fontSize: fontSizeSubtitle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildWorkOrderStatusTabBar(isMobile, isTablet),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isClientStatusFilterMode ? 'Filter by Client Status' : 'Filter by Priority',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: context.textPrimary, fontSize: fontSizeSubtitle),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _isClientStatusFilterMode = !_isClientStatusFilterMode;
                            _statusFilter = 'All';
                            _priorityFilter = 'All';
                          });
                        },
                        icon: const Icon(Icons.tune_rounded, size: 15, color: AppColors.primary),
                        label: Text(
                          _isClientStatusFilterMode ? 'By Priority' : 'By Status',
                          style: GoogleFonts.poppins(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          backgroundColor: context.surfaceAltColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildResponsiveTabBar(isMobile, isTablet),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_showForm && _isJVAlmacisUser) _buildWorkOrderForm(padding, fontSizeTitle, fontSizeSubtitle),
          const SizedBox(height: 24),
          _buildWorkOrdersList(padding, fontSizeSubtitle, isMobile),
          const SizedBox(height: 80), // Padding to avoid overlap with FAB
        ],
      ),
    );
  }

  Widget _buildResponsiveTabBar(bool isMobile, bool isTablet) {
    if (_isClientStatusFilterMode) {
      // Client status filter tabs (removed declined)
      if (isMobile) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTabButton('All', _allCount, Colors.grey, 0, true),
              const SizedBox(width: 8),
              _buildTabButton('Approved', _approvedCount, Colors.green, 1, true),
              const SizedBox(width: 8),
              _buildTabButton('To be Reviewed', _toBeReviewedCount, Colors.orange, 2, true),
            ],
          ),
        );
      } else {
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _buildTabButton('All', _allCount, Colors.grey, 0, true),
            _buildTabButton('Approved', _approvedCount, Colors.green, 1, true),
            _buildTabButton('To be Reviewed', _toBeReviewedCount, Colors.orange, 2, true),
          ],
        );
      }
    } else {
      // Priority filter tabs
      if (isMobile) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTabButton('All', _allPriorityCount, Colors.grey, 0, false),
              const SizedBox(width: 8),
              _buildTabButton('High', _highPriorityCount, Colors.red, 1, false),
              const SizedBox(width: 8),
              _buildTabButton('Medium', _mediumPriorityCount, Colors.orange, 2, false),
              const SizedBox(width: 8),
              _buildTabButton('Low', _lowPriorityCount, Colors.green, 3, false),
            ],
          ),
        );
      } else {
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _buildTabButton('All', _allPriorityCount, Colors.grey, 0, false),
            _buildTabButton('High', _highPriorityCount, Colors.red, 1, false),
            _buildTabButton('Medium', _mediumPriorityCount, Colors.orange, 2, false),
            _buildTabButton('Low', _lowPriorityCount, Colors.green, 3, false),
          ],
        );
      }
    }
  }

  Widget _buildWorkOrderStatusTabBar(bool isMobile, bool isTablet) {
    if (isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildWorkOrderStatusTabButton('All', _approvedAllCount, Colors.grey, 0),
            const SizedBox(width: 8),
            _buildWorkOrderStatusTabButton('Open', _approvedOpenCount, Colors.blue, 1),
            const SizedBox(width: 8),
            _buildWorkOrderStatusTabButton('In Progress', _approvedInProgressCount, Colors.orange, 2),
            const SizedBox(width: 8),
            _buildWorkOrderStatusTabButton('Completed', _approvedCompletedCount, Colors.green, 3),
          ],
        ),
      );
    } else {
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _buildWorkOrderStatusTabButton('All', _approvedAllCount, Colors.grey, 0),
          _buildWorkOrderStatusTabButton('Open', _approvedOpenCount, Colors.blue, 1),
          _buildWorkOrderStatusTabButton('In Progress', _approvedInProgressCount, Colors.orange, 2),
          _buildWorkOrderStatusTabButton('Completed', _approvedCompletedCount, Colors.green, 3),
        ],
      );
    }
  }

  Widget _buildTabButton(String label, int count, Color color, int index, bool isStatusMode) {
    final isSelected = isStatusMode
        ? _statusFilter == (index == 0 ? 'All' : ['Approved', 'To be Reviewed'][index - 1])
        : _priorityFilter == (index == 0 ? 'All' : ['High', 'Medium', 'Low'][index - 1]);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isStatusMode) {
            final newFilter = index == 0 ? 'All' : ['Approved', 'To be Reviewed'][index - 1];
            _statusFilter = newFilter;
            if (newFilter == 'Approved') {
              _isInApprovedSubView = true;
              _workOrderStatusFilter = 'All';
            }
          } else {
            _priorityFilter = index == 0 ? 'All' : ['High', 'Medium', 'Low'][index - 1];
          }
        });
      },
      child: _filterChip(label: label, count: count, color: color, isSelected: isSelected),
    );
  }

  Widget _buildWorkOrderStatusTabButton(String label, int count, Color color, int index) {
    final statuses = ['All', 'Open', 'In Progress', 'Completed'];
    final isSelected = _workOrderStatusFilter == statuses[index];
    return GestureDetector(
      onTap: () => setState(() => _workOrderStatusFilter = statuses[index]),
      child: _filterChip(label: label, count: count, color: color, isSelected: isSelected),
    );
  }

  Widget _filterChip({required String label, required int count, required Color color, required bool isSelected}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        color: isSelected ? color : Colors.transparent,
        border: Border.all(
          color: isSelected ? color : color.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : color,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withValues(alpha: 0.25) : color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              count.toString(),
              style: GoogleFonts.poppins(
                color: isSelected ? Colors.white : color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkOrdersList(double padding, double fontSizeSubtitle, bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Work_Orders')
          .where('facilityId', isEqualTo: widget.facilityId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _isLoading) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
                
        if (snapshot.hasError) {
          _logger.e('Firestore error: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading work orders',
                    style: GoogleFonts.poppins(
                      fontSize: fontSizeSubtitle,
                      color: Colors.red[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your connection and try again',
                    style: GoogleFonts.poppins(
                      fontSize: fontSizeSubtitle - 2,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
                
        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
                
        // Cache all work orders for better performance
        _allWorkOrders = snapshot.data!.docs;
        _isLoading = false;
                
        // Update counts based on all work orders (not filtered)
        if (_isClientStatusFilterMode) {
          _updateClientStatusCounts(_allWorkOrders);
        } else {
          _updatePriorityCounts(_allWorkOrders);
        }

        // Update work order status counts for approved items
        final approvedDocs = _allWorkOrders.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['clientStatus'] == 'Approved';
        }).toList();
        _updateWorkOrderStatusCounts(approvedDocs);

        // Get filtered work orders
        final filteredWorkOrders = _getFilteredWorkOrders();

        if (filteredWorkOrders.isEmpty) {
          String filterText;
          if (_isInApprovedSubView) {
            filterText = _workOrderStatusFilter == 'All'
               ? 'No approved work orders found'
               : 'No $_workOrderStatusFilter approved work orders';
          } else if (_isClientStatusFilterMode) {
            filterText = _statusFilter == 'All'
               ? 'No work orders found'
               : 'No $_statusFilter work orders';
          } else {
            filterText = _priorityFilter == 'All'
               ? 'No work orders found'
               : 'No $_priorityFilter priority work orders';
          }
                  
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(
                    Icons.work_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    filterText,
                    style: GoogleFonts.poppins(
                      fontSize: fontSizeSubtitle,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_isJVAlmacisUser) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Tap the + button to create your first work order',
                      style: GoogleFonts.poppins(
                        fontSize: fontSizeSubtitle - 2,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
                
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredWorkOrders.length,
          itemBuilder: (context, index) {
            final data = filteredWorkOrders[index].data() as Map<String, dynamic>;
            final workOrder = WorkOrder.fromMap(data, filteredWorkOrders[index].id);
            return _buildWorkOrderCard(workOrder, fontSizeSubtitle, isMobile);
          },
        );
      },
    );
  }

  Widget _buildWorkOrderCard(WorkOrder workOrder, double fontSize, bool isMobile) {
    final priorityColor = _getPriorityColor(workOrder.priority);
    final clientStatusColor = _getClientStatusColor(workOrder.clientStatus);
    final woStatusColor = _getWorkOrderStatusColor(workOrder.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.surfaceAltColor),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Priority color band
              Container(width: 5, color: priorityColor),
              // Card body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row: title + status badges
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              workOrder.title,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: context.textPrimary,
                                fontSize: fontSize,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Client status badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: clientStatusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                  border: Border.all(color: clientStatusColor.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_getClientStatusIcon(workOrder.clientStatus), size: 11, color: clientStatusColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      workOrder.clientStatus,
                                      style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: clientStatusColor),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isInApprovedSubView) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: woStatusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                    border: Border.all(color: woStatusColor.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    workOrder.status,
                                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: woStatusColor),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Description
                      Text(
                        workOrder.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: fontSize - 1.5,
                          color: context.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Meta chips row
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          _woMetaChip(
                            icon: Icons.flag_rounded,
                            label: workOrder.priority,
                            color: priorityColor,
                          ),
                          if (workOrder.equipmentName != null && workOrder.equipmentName!.isNotEmpty)
                            _woMetaChip(
                              icon: Icons.build_rounded,
                              label: workOrder.equipmentName!,
                              color: context.textSecondary,
                            ),
                          _woMetaChip(
                            icon: Icons.calendar_today_rounded,
                            label: workOrder.createdAt != null ? DateFormat.yMMMd().format(workOrder.createdAt!) : 'Unknown',
                            color: context.textSecondary,
                          ),
                          if (_isJVAlmacisUser && workOrder.assignedTo.isNotEmpty)
                            FutureBuilder<String>(
                              future: _getUsernameFromCollection(workOrder.assignedTo),
                              builder: (context, snap) => _woMetaChip(
                                icon: Icons.person_rounded,
                                label: snap.data ?? (workOrder.assignedToEmail.isNotEmpty ? workOrder.assignedToEmail : '…'),
                                color: AppColors.primary,
                              ),
                            ),
                          if (_isJVAlmacisUser && workOrder.assignedTo.isEmpty)
                            _woMetaChip(icon: Icons.person_off_rounded, label: 'Unassigned', color: context.textSecondary),
                        ],
                      ),
                      // Extra details (created by, related request, client notes)
                      if (_isJVAlmacisUser) ...[
                        const SizedBox(height: 8),
                        FutureBuilder<String>(
                          future: _getUsernameFromCollection(workOrder.createdBy),
                          builder: (context, snap) {
                            final name = snap.data ?? (workOrder.createdByEmail.isNotEmpty ? workOrder.createdByEmail : '…');
                            return _buildDetailRow('Created By', name, fontSize, isMobile);
                          },
                        ),
                      ],
                      if (workOrder.requestId != null)
                        FutureBuilder<String>(
                          future: _getRequestTitleFromId(workOrder.requestId!),
                          builder: (context, snap) => _buildDetailRow('Related Request', snap.data ?? '…', fontSize, isMobile),
                        ),
                      if (workOrder.clientNotes.isNotEmpty)
                        _buildDetailRow('Client Notes', workOrder.clientNotes, fontSize, isMobile),
                      if (workOrder.attachments.isNotEmpty)
                        _buildAttachmentsSection(workOrder.attachments, fontSize),
                      if (workOrder.history.isNotEmpty)
                        _buildHistorySection(workOrder.history, fontSize),
                      const SizedBox(height: 10),
                      _buildActionButtons(workOrder, fontSize),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _woMetaChip({required IconData icon, required String label, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label, style: GoogleFonts.poppins(fontSize: 11.5, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high': return AppColors.error;
      case 'medium': return AppColors.warning;
      case 'low': return AppColors.success;
      default: return context.textSecondary;
    }
  }

  Widget _buildDetailRow(String label, String value, double fontSize, bool isMobile) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: isMobile
               ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label:',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                  color: context.textSecondary,
                  fontSize: fontSize,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.poppins(
                  color: Colors.grey[800],
                   fontSize: fontSize,
                ),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  '$label:',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w500,
                    color: context.textSecondary,
                    fontSize: fontSize,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.poppins(
                    color: Colors.grey[800],
                     fontSize: fontSize,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildAttachmentsSection(List<Map<String, String>> attachments, double fontSize) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attachments:',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              color: context.textSecondary,
              fontSize: fontSize,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: attachments
                .map((attachment) => GestureDetector(
                      onLongPress: () => _showAttachmentOptions(attachment['url']!, attachment['name']!),
                      onTap: () => _viewAttachment(attachment['url']!, attachment['name']!),
                      child: Chip(
                        avatar: Icon(
                          _getFileIcon(attachment['name']!),
                          size: 16,
                          color: _getFileIconColor(attachment['name']!),
                        ),
                        label: Text(
                          attachment['name']!,
                          style: GoogleFonts.poppins(fontSize: fontSize - 2),
                        ),
                        backgroundColor: Colors.blue[50],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  void _showAttachmentOptions(String url, String fileName) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.visibility, color: Colors.blue[700]),
              title: Text('View', style: GoogleFonts.poppins()),
              onTap: () {
                Navigator.pop(context);
                _viewAttachment(url, fileName);
              },
            ),
            ListTile(
              leading: Icon(Icons.download, color: Colors.green[700]),
              title: Text('Download', style: GoogleFonts.poppins()),
              onTap: () {
                Navigator.pop(context);
                _downloadAttachment(url, fileName);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection(List<Map<String, dynamic>> history, double fontSize) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'History:',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              color: context.textSecondary,
              fontSize: fontSize,
            ),
          ),
          const SizedBox(height: 4),
          ...history.map((entry) => Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry['action'] ?? 'Action',
                      style: GoogleFonts.poppins(fontSize: fontSize - 2, fontWeight: FontWeight.w500),
                    ),
                    // Show different history format based on user type
                    if (_isJVAlmacisUser) ...[
                      // JV Almacis users see full history with actors
                      FutureBuilder<String>(
                        future: entry['userId'] != null && entry['userId'] != 'system'
                             ? _getUsernameFromCollection(entry['userId'])
                            : Future.value(entry['username'] ?? entry['userEmail'] ?? 'Unknown'),
                        builder: (context, snapshot) {
                          final displayName = snapshot.data ?? 'Loading...';
                          return Text(
                            'by $displayName at ${entry['timestamp'] != null ? DateFormat.yMMMd().format((entry['timestamp'] as Timestamp).toDate()) : 'Unknown date'}',
                            style: GoogleFonts.poppins(
                              fontSize: fontSize - 4,
                              color: Colors.grey[600],
                            ),
                          );
                        },
                      ),
                    ] else ...[
                      // Client users see only date without actor
                      Text(
                        'on ${entry['timestamp'] != null ? DateFormat.yMMMd().format((entry['timestamp'] as Timestamp).toDate()) : 'Unknown date'}',
                        style: GoogleFonts.poppins(
                          fontSize: fontSize - 4,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                    if (entry['notes'] != null && entry['notes'].isNotEmpty)
                      Text(
                        entry['notes'],
                        style: GoogleFonts.poppins(fontSize: fontSize - 3),
                      ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildActionButtons(WorkOrder workOrder, double fontSize) {
    if (_isAdminClient) {
      return _actionArea(
        label: 'Client Actions',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildActionButton(workOrder, 'To be Reviewed', Icons.rate_review_rounded, AppColors.warning, fontSize,
                isCurrentStatus: workOrder.clientStatus == 'To be Reviewed'),
            _buildActionButton(workOrder, 'Approved', Icons.check_circle_rounded, AppColors.success, fontSize,
                isCurrentStatus: workOrder.clientStatus == 'Approved'),
          ],
        ),
      );
    } else if (_isJVAlmacisUser) {
      return _actionArea(
        label: 'Update Status',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildWorkOrderStatusButton(workOrder, 'Open', Icons.radio_button_unchecked_rounded, AppColors.primary, fontSize,
                isCurrentStatus: workOrder.status == 'Open'),
            _buildWorkOrderStatusButton(workOrder, 'In Progress', Icons.pending_rounded, AppColors.warning, fontSize,
                isCurrentStatus: workOrder.status == 'In Progress'),
            _buildWorkOrderStatusButton(workOrder, 'Completed', Icons.check_circle_rounded, AppColors.success, fontSize,
                isCurrentStatus: workOrder.status == 'Completed'),
          ],
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _actionArea({required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.surfaceAltColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: context.textPrimary, fontSize: 12.5)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildActionButton(
    WorkOrder workOrder,
    String action,
    IconData icon,
    Color color,
    double fontSize, {
    bool isCurrentStatus = false,
  }) {
    return OutlinedButton.icon(
      onPressed: isCurrentStatus ? null : () => _showEnhancedClientActionDialog(workOrder, action, fontSize),
      icon: Icon(icon, size: 15, color: isCurrentStatus ? color.withValues(alpha: 0.5) : color),
      label: Text(
        action == 'To be Reviewed' ? 'Mark Review' : action == 'Approved' ? 'Approve' : action,
        style: GoogleFonts.poppins(fontSize: 12.5, color: isCurrentStatus ? color.withValues(alpha: 0.5) : color, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: isCurrentStatus ? color.withValues(alpha: 0.3) : color.withValues(alpha: 0.6), width: 1.5),
        backgroundColor: isCurrentStatus ? color.withValues(alpha: 0.08) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }

  Widget _buildWorkOrderStatusButton(
    WorkOrder workOrder,
    String status,
    IconData icon,
    Color color,
    double fontSize, {
    bool isCurrentStatus = false,
  }) {
    return OutlinedButton.icon(
      onPressed: isCurrentStatus ? null : () => _showEnhancedUpdateStatusDialog(workOrder, status, fontSize),
      icon: Icon(icon, size: 15, color: isCurrentStatus ? color.withValues(alpha: 0.5) : color),
      label: Text(
        status,
        style: GoogleFonts.poppins(fontSize: 12.5, color: isCurrentStatus ? color.withValues(alpha: 0.5) : color, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: isCurrentStatus ? color.withValues(alpha: 0.3) : color.withValues(alpha: 0.6), width: 1.5),
        backgroundColor: isCurrentStatus ? color.withValues(alpha: 0.08) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }

  void _showEnhancedClientActionDialog(WorkOrder workOrder, String action, double fontSize) {
    final notesController = TextEditingController();
      
    // Pre-fill with existing notes if updating the same status
    if (workOrder.clientStatus == action && workOrder.clientNotes.isNotEmpty) {
      notesController.text = workOrder.clientNotes;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                action == 'Approved' ? Colors.green[700]! : Colors.orange[700]!,
                action == 'Approved' ? Colors.green[500]! : Colors.orange[500]!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Icon(
                action == 'Approved' ? Icons.check_circle : Icons.rate_review,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${action == 'To be Reviewed' ? 'Review' : action == 'Approved' ? 'Approve' : action} Work Order',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                     fontSize: fontSize,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        titlePadding: EdgeInsets.zero,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current status indicator
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Text(
                      'Current Status: ',
                      style: GoogleFonts.poppins(
                        fontSize: fontSize - 1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getClientStatusColor(workOrder.clientStatus),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        workOrder.clientStatus,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: fontSize - 2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
                          
              // Action confirmation
              RichText(
                text: TextSpan(
                  style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.black87),
                  children: [
                    const TextSpan(text: 'Change status to '),
                    TextSpan(
                      text: action,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: action == 'Approved' ? Colors.green[700] : Colors.orange[700],
                      ),
                    ),
                    const TextSpan(text: '?'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
                          
              // Notes input
              TextFormField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: 'Comments (Optional)',
                  hintText: 'Add your comments about this ${action.toLowerCase()} action...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: context.surfaceAltColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: context.surfaceAltColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(
                      color: action == 'Approved' ? Colors.green : Colors.orange,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: context.surfaceColor,
                  labelStyle: GoogleFonts.poppins(color: context.textSecondary),
                  prefixIcon: Icon(
                    Icons.comment,
                    color: context.textSecondary,
                  ),
                ),
                style: GoogleFonts.poppins(fontSize: fontSize),
                maxLines: 4,
                minLines: 2,
              ),
                          
              // Show previous notes if they exist
              if (workOrder.clientNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Previous Notes:',
                        style: GoogleFonts.poppins(
                          fontSize: fontSize - 2,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue[800],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        workOrder.clientNotes,
                        style: GoogleFonts.poppins(
                          fontSize: fontSize - 2,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
               style: GoogleFonts.poppins(
                fontSize: fontSize,
                color: Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _updateClientStatus(workOrder.id, action, notesController.text);
              Navigator.pop(context);
            },
            icon: Icon(
              action == 'Approved' ? Icons.check : Icons.rate_review,
              size: 16,
              color: Colors.white,
            ),
            label: Text(
              action == 'To be Reviewed' ? 'Review' : action == 'Approved' ? 'Approve' : action,
              style: GoogleFonts.poppins(
                color: Colors.white,
                 fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: action == 'Approved' ? Colors.green[700] : Colors.orange[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 3,
            ),
          ),
        ],
      ),
    );
  }

  void _showEnhancedUpdateStatusDialog(WorkOrder workOrder, String selectedStatus, double fontSize) {
    final notesController = TextEditingController();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.work_outline,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Update Work Order Status',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                     fontSize: fontSize,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        titlePadding: EdgeInsets.zero,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current status indicator
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Text(
                      'Current Status: ',
                      style: GoogleFonts.poppins(
                        fontSize: fontSize - 1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getWorkOrderStatusColor(workOrder.status),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        workOrder.status,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: fontSize - 2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
                          
              // Action confirmation
              RichText(
                text: TextSpan(
                  style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.black87),
                  children: [
                    const TextSpan(text: 'Change status to '),
                    TextSpan(
                      text: selectedStatus,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: _getWorkOrderStatusColor(selectedStatus),
                      ),
                    ),
                    const TextSpan(text: '?'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
                          
              // Notes input
              TextFormField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  hintText: 'Add notes about this status update...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: context.surfaceAltColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: context.surfaceAltColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: context.surfaceColor,
                  labelStyle: GoogleFonts.poppins(color: context.textSecondary),
                  prefixIcon: Icon(
                    Icons.note_add,
                    color: Colors.grey[600],
                  ),
                ),
                style: GoogleFonts.poppins(fontSize: fontSize),
                maxLines: 3,
                minLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
               style: GoogleFonts.poppins(
                fontSize: fontSize,
                color: Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _updateStatus(workOrder.id, selectedStatus, notesController.text);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.update, size: 16, color: Colors.white),
            label: Text(
              'Update',
              style: GoogleFonts.poppins(
                color: Colors.white,
                 fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _getWorkOrderStatusColor(selectedStatus),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 3,
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to get work order status colors
  Color _getWorkOrderStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.blue[600]!;
      case 'in progress':
        return Colors.orange[600]!;
      case 'completed':
        return Colors.green[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  Color _getClientStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'to be reviewed':
        return Colors.orange;
      // Handle legacy "Declined" status
      case 'declined':
        return Colors.orange;
       default:
        return Colors.grey;
    }
  }

  IconData _getClientStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_circle;
      case 'to be reviewed':
        return Icons.rate_review;
      // Handle legacy "Declined" status
      case 'declined':
        return Icons.rate_review;
       default:
        return Icons.help;
    }
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'docx':
      case 'doc':
        return Icons.description;
      case 'txt':
        return Icons.text_snippet;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Colors.red[600]!;
      case 'docx':
      case 'doc':
        return Colors.blueGrey[600]!;
      case 'txt':
        return Colors.grey[600]!;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Colors.green[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  Widget _buildWorkOrderForm(double padding, double fontSizeTitle, double fontSizeSubtitle) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: padding, vertical: 4),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.surfaceAltColor),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Form header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                border: Border(bottom: BorderSide(color: context.surfaceAltColor)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: context.surfaceAltColor, borderRadius: BorderRadius.circular(AppRadius.sm)),
                    child: Icon(Icons.work_history_rounded, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('New Work Order', style: GoogleFonts.poppins(fontSize: fontSizeTitle, fontWeight: FontWeight.w700, color: context.textPrimary)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: context.textSecondary),
                    onPressed: () => setState(() => _showForm = false),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isMobile) ...[
                    _buildRequestField(fontSizeSubtitle),
                    const SizedBox(height: 14),
                    _buildEquipmentField(fontSizeSubtitle),
                    const SizedBox(height: 14),
                    _buildTextField(_titleController, 'Title', fontSizeSubtitle, validator: (v) => v!.isEmpty ? 'Enter a title' : null),
                    const SizedBox(height: 14),
                    _buildTextField(_descriptionController, 'Description', fontSizeSubtitle, maxLines: 3),
                    const SizedBox(height: 14),
                    _buildTechnicianField(fontSizeSubtitle),
                    const SizedBox(height: 14),
                    _buildDropdown('Priority', _priority, ['Low', 'Medium', 'High'], (v) => setState(() => _priority = v!), fontSizeSubtitle),
                    const SizedBox(height: 14),
                    _buildTextField(_notesController, 'Notes', fontSizeSubtitle, maxLines: 2),
                  ] else ...[
                    Row(children: [
                      Expanded(child: _buildRequestField(fontSizeSubtitle)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildTextField(_titleController, 'Title', fontSizeSubtitle, validator: (v) => v!.isEmpty ? 'Enter a title' : null)),
                    ]),
                    const SizedBox(height: 14),
                    _buildEquipmentField(fontSizeSubtitle),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: _buildTextField(_descriptionController, 'Description', fontSizeSubtitle, maxLines: 3)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildTechnicianField(fontSizeSubtitle)),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: _buildDropdown('Priority', _priority, ['Low', 'Medium', 'High'], (v) => setState(() => _priority = v!), fontSizeSubtitle)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildTextField(_notesController, 'Notes', fontSizeSubtitle, maxLines: 2)),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  // Attachment buttons
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _uploadImageAttachment,
                        icon: Icon(Icons.image_rounded, size: 16, color: AppColors.success),
                        label: Text('Add Image', style: GoogleFonts.poppins(fontSize: fontSizeSubtitle, color: AppColors.success, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.success.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _uploadDocumentAttachment,
                        icon: Icon(Icons.attach_file_rounded, size: 16, color: AppColors.primary),
                        label: Text('Add Document', style: GoogleFonts.poppins(fontSize: fontSizeSubtitle, color: AppColors.primary, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                        ),
                      ),
                    ),
                  ]),
                  if (_attachmentUrls.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _attachmentUrls
                          .map((att) => Chip(
                                avatar: Icon(_getFileIcon(att['name']!), size: 14, color: _getFileIconColor(att['name']!)),
                                label: Text(att['name']!, style: GoogleFonts.poppins(fontSize: fontSizeSubtitle - 2)),
                                                                side: BorderSide(color: context.surfaceAltColor),
                                onDeleted: () => setState(() => _attachmentUrls.remove(att)),
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Footer buttons
                  Row(children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() => _showForm = false),
                        child: Text('Cancel', style: GoogleFonts.poppins(color: context.textSecondary, fontSize: fontSizeSubtitle, fontWeight: FontWeight.w500)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _isSubmitting ? null : _addWorkOrder,
                          icon: _isSubmitting
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                          label: Text(
                            _isSubmitting ? 'Creating…' : 'Create Work Order',
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: fontSizeSubtitle, fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEquipmentField(double fontSize) {
    return EquipmentPickerField(
      facilityId: widget.facilityId,
      value: _selectedEquipment,
      fontSize: fontSize,
      onChanged: (v) => setState(() => _selectedEquipment = v),
    );
  }

  Widget _buildRequestField(double fontSize) {
    return TextFormField(
      controller: TextEditingController(text: _selectedRequestId != null ? 'Selected Request' : ''),
      decoration: InputDecoration(
        labelText: 'Related Request (Optional)',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: AppColors.primary, width: 2)),
        filled: true,
        fillColor: context.surfaceColor,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        labelStyle: GoogleFonts.poppins(color: context.textSecondary, fontSize: fontSize),
        hintText: 'Tap to select from open requests',
        hintStyle: GoogleFonts.poppins(color: context.textSecondary),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedRequestId != null)
              IconButton(
                icon: Icon(Icons.visibility_rounded, color: AppColors.primary, size: 18),
                onPressed: () => _showRequestDetails(_selectedRequestId!),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(Icons.assignment_rounded, color: context.textSecondary, size: 18),
            ),
          ],
        ),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary),
      readOnly: true,
      onTap: () => _showRequestSelectionDialog(fontSize),
    );
  }

  Future<void> _showRequestSelectionDialog(double fontSize) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('Work_Requests')
        .where('facilityId', isEqualTo: widget.facilityId)
        .where('status', isEqualTo: 'Open')
        .orderBy('createdAt', descending: true)
        .get();

    if (snapshot.docs.isEmpty) {
      if (mounted) _showSnackBar('No open requests available.');
      return;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select a Request', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSize)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: snapshot.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.docs[index];
              final data = doc.data();
                          
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(data['title'] ?? 'Untitled', style: GoogleFonts.poppins(fontSize: fontSize, fontWeight: FontWeight.w500)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (data['description'] ?? '').length > 100
                           ? '${(data['description'] ?? '').substring(0, 100)}...'
                           : (data['description'] ?? ''),
                        style: GoogleFonts.poppins(fontSize: fontSize - 2),
                      ),
                      Text(
                        'Priority: ${data['priority'] ?? 'Medium'} | Created: ${data['createdAt'] != null ? DateFormat.yMMMd().format((data['createdAt'] as Timestamp).toDate()) : 'Unknown'}',
                        style: GoogleFonts.poppins(fontSize: fontSize - 3, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.visibility, color: Colors.blue[600]),
                        onPressed: () => _showRequestDetails(doc.id),
                      ),
                      IconButton(
                        icon: Icon(Icons.check, color: Colors.green[600]),
                        onPressed: () {
                          setState(() {
                            _selectedRequestId = doc.id;
                            _titleController.text = data['title'] ?? '';
                            _descriptionController.text = data['description'] ?? '';
                            _priority = data['priority'] ?? 'Medium';
                            // Carry the request's equipment over, unless one was already chosen.
                            if (_selectedEquipment == null && data['equipmentId'] != null) {
                              _selectedEquipment = EquipmentRef(
                                id: data['equipmentId'] as String,
                                name: (data['equipmentName'] as String?) ?? 'Equipment',
                                spaceId: data['spaceId'] as String?,
                              );
                            }
                          });
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: GoogleFonts.poppins(fontSize: fontSize)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showRequestDetails(String requestId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Work_Requests')
          .doc(requestId)
          .get();

      if (!doc.exists) {
        _showSnackBar('Request not found');
        return;
      }

      final data = doc.data() as Map<String, dynamic>;

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Request Details', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDetailRow('Title', data['title'] ?? 'Untitled', 14, false),
                  _buildDetailRow('Description', data['description'] ?? '', 14, false),
                  _buildDetailRow('Priority', data['priority'] ?? 'Medium', 14, false),
                  _buildDetailRow('Status', data['status'] ?? 'Open', 14, false),
                  FutureBuilder<String>(
                    future: _getUsernameFromCollection(data['createdBy'] ?? ''),
                    builder: (context, snapshot) {
                      final displayName = snapshot.data ?? (data['createdByEmail'] ?? 'Loading...');
                      return _buildDetailRow('Created By', displayName, 14, false);
                    },
                  ),
                  _buildDetailRow('Created', data['createdAt'] != null ? DateFormat.yMMMd().format((data['createdAt'] as Timestamp).toDate()) : 'Unknown', 14, false),
                  if (data['attachments'] != null && (data['attachments'] as List).isNotEmpty)
                    _buildAttachmentsSection(List<Map<String, String>>.from((data['attachments'] as List).map((item) => Map<String, String>.from(item))), 14),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              child: Text('Close', style: GoogleFonts.poppins()),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } catch (e) {
      _logger.e('Error showing request details: $e');
      _showSnackBar('Error loading request details');
    }
  }

  Widget _buildTechnicianField(double fontSize) {
    return TextFormField(
      controller: TextEditingController(
        text: _selectedTechnicianEmail != null
            ? _selectedTechnicianEmail!
            : ""
      ),
      decoration: InputDecoration(
        labelText: 'Assign To (Optional)',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: context.surfaceAltColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: context.surfaceAltColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        filled: true,
        fillColor: context.surfaceColor,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
        hintText: 'Select JV Almacis technician',
        hintStyle: GoogleFonts.poppins(color: Colors.grey),
        suffixIcon: Icon(Icons.person, color: Colors.blueGrey[600]),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize),
      readOnly: true,
      onTap: () => _showTechnicianSelectionDialog(fontSize),
    );
  }

  Future<void> _showTechnicianSelectionDialog(double fontSize) async {
    try {
      // Get JV Almacis technicians from multiple collections with proper deduplication
      final Map<String, Map<String, dynamic>> uniqueTechnicians = {};
          
      // Get from Technicians collection
      final techSnapshot = await FirebaseFirestore.instance
          .collection('Technicians')
          .where('organization', isEqualTo: 'JV Almacis')
          .get();
          
      for (var doc in techSnapshot.docs) {
        final data = doc.data();
        final email = data['email'];
        if (email != null && email.isNotEmpty) {
          uniqueTechnicians[email] = {
            'id': doc.id,
            'email': email,
            'username': data['username'] ?? data['name'] ?? data['displayName'] ?? 'Unknown User',
            'source': 'Technicians'
          };
        }
      }
          
      // Get from Developers collection (they are JV Almacis by default)
      final devSnapshot = await FirebaseFirestore.instance
          .collection('Developers')
          .get();
          
      for (var doc in devSnapshot.docs) {
        final data = doc.data();
        final email = data['email'];
        if (email != null && email.isNotEmpty) {
          // Only add if not already present (avoid duplicates)
          if (!uniqueTechnicians.containsKey(email)) {
            uniqueTechnicians[email] = {
              'id': doc.id,
              'email': email,
              'username': data['username'] ?? data['name'] ?? data['displayName'] ?? 'Developer',
              'source': 'Developers'
            };
          }
        }
      }

      // Get from Users collection where role is Technician and organization is JV Almacis
      final userSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('role', isEqualTo: 'Technician')
          .where('organization', isEqualTo: 'JV Almacis')
          .get();
          
      for (var doc in userSnapshot.docs) {
        final data = doc.data();
        final email = data['email'];
        if (email != null && email.isNotEmpty) {
          // Only add if not already present (avoid duplicates)
          if (!uniqueTechnicians.containsKey(email)) {
            uniqueTechnicians[email] = {
              'id': doc.id,
              'email': email,
              'username': data['username'] ?? data['name'] ?? data['displayName'] ?? 'User',
              'source': 'Users'
            };
          }
        }
      }

      final techniciansList = uniqueTechnicians.values.toList();

      if (techniciansList.isEmpty) {
        if (mounted) _showSnackBar('No JV Almacis technicians available.');
        return;
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Select a Technician', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSize)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: techniciansList.length,
              itemBuilder: (context, index) {
                final technician = techniciansList[index];
                final email = technician['email'] ?? 'Unknown Email';
                final username = technician['username'] ?? 'Unknown User';
                final source = technician['source'] ?? '';
                              
                return ListTile(
                  title: Text(username, style: GoogleFonts.poppins(fontSize: fontSize, fontWeight: FontWeight.w500)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(email, style: GoogleFonts.poppins(fontSize: fontSize - 2)),
                      Text('Source: $source', style: GoogleFonts.poppins(fontSize: fontSize - 3, color: Colors.grey[600])),
                    ],
                  ),
                  onTap: () {
                    setState(() {
                      _selectedTechnicianId = technician['id'];
                      _selectedTechnicianEmail = email;
                    });
                    Navigator.pop(context);
                  },
                  isThreeLine: true,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              child: Text('Cancel', style: GoogleFonts.poppins(fontSize: fontSize)),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } catch (e) {
      _logger.e('Error loading technicians: $e');
      if (mounted) _showSnackBar('Error loading technicians');
    }
  }

  Widget _buildTextField(
    TextEditingController controller,
    String labelText,
    double fontSize, {
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: labelText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: AppColors.primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: AppColors.error)),
        filled: true,
        fillColor: context.surfaceColor,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        labelStyle: GoogleFonts.poppins(color: context.textSecondary, fontSize: fontSize),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary),
      maxLines: maxLines,
      validator: validator,
    );
  }

  Widget _buildDropdown(
    String labelText,
    String value,
    List<String> items,
    Function(String?) onChanged,
    double fontSize,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items
          .map((item) => DropdownMenuItem(
                value: item,
                child: Text(item, style: GoogleFonts.poppins(color: context.textPrimary)),
              ))
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: labelText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: AppColors.primary, width: 2)),
        filled: true,
        fillColor: context.surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: GoogleFonts.poppins(color: context.textSecondary, fontSize: fontSize),
      ),
      style: GoogleFonts.poppins(color: context.textPrimary, fontSize: fontSize),
      dropdownColor: context.cardColor,
      icon: Icon(Icons.keyboard_arrow_down_rounded, color: context.textSecondary),
    );
  }
}

// Image viewer screen for viewing attached images
class ImageViewerScreen extends StatelessWidget {
  final String imageUrl;
  final String fileName;

  const ImageViewerScreen({
    super.key,
    required this.imageUrl,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            imageUrl,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading image',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
