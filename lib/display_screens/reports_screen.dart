import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/models/reports.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:cmms/utils/app_date_format.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  final String facilityId;

  const ReportsScreen({super.key, required this.facilityId});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final logger = Logger(printer: PrettyPrinter());
  final TextEditingController _titleController = TextEditingController();
  double? _uploadProgress;
  String _currentRole = 'User';
  String _organization = '-';
  bool _isUploadVisible = false; // Track visibility of upload card

  @override
  void initState() {
    super.initState();
    logger.i('ReportsScreen initialized with facilityId: ${widget.facilityId}');
  }


  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _uploadDocument() async {
    try {
      final platformFile = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (platformFile == null) return;

      final fileName = platformFile.name;
      final user = FirebaseAuth.instance.currentUser;
      
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please log in to upload reports', style: GoogleFonts.poppins())),
          );
        }
        return;
      }

      final title = _titleController.text.trim().isEmpty ? fileName : _titleController.text.trim();
      
      if (!mounted) {
        logger.w('Widget not mounted, skipping confirmation dialog for $fileName');
        return;
      }

      final bool? confirmUpload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Upload', style: GoogleFonts.poppins()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kIsWeb) 
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'WEB',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Do you want to upload the file: $fileName?',
                style: GoogleFonts.poppins(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Upload', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      );

      if (confirmUpload != true) {
        logger.i('User cancelled report upload: $fileName');
        return;
      }

      if (!mounted) {
        logger.w('Widget not mounted, skipping progress dialog for $fileName');
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
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
                  const SizedBox(height: 8),
                  Text(
                    _uploadProgress != null
                        ? '${(_uploadProgress! * 100).toStringAsFixed(0)}%'
                        : 'Starting upload...',
                    style: GoogleFonts.poppins(),
                  ),
                  if (kIsWeb) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Web Upload',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.blue[600],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      );

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('facilities/${widget.facilityId}/reports/${DateTime.now().millisecondsSinceEpoch}_$fileName');

      late UploadTask uploadTask;
      
      if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final metadata = SettableMetadata(
          contentType: 'application/pdf',
          customMetadata: {
            'uploadedBy': user.uid,
            'originalName': fileName,
            'platform': kIsWeb ? 'web' : Platform.operatingSystem,
          },
        );

        uploadTask = storageRef.putData(await platformFile.readAsBytes(), metadata);
      } else {
        if (platformFile.path == null) {
          throw 'File path not available for mobile upload';
        }
        
        final file = File(platformFile.path!);
        final metadata = SettableMetadata(
          contentType: 'application/pdf',
          customMetadata: {
            'uploadedBy': user.uid,
            'originalName': fileName,
            'platform': Platform.operatingSystem,
          },
        );
        
        uploadTask = storageRef.putFile(file, metadata);
      }

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (mounted) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      }, onError: (e) {
        logger.e('Upload progress error: $e');
      });

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('Reports').add({
        'userId': user.uid,
        'title': title,
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'uploadedAt': FieldValue.serverTimestamp(),
        'facilityId': widget.facilityId,
        'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report uploaded successfully', style: GoogleFonts.poppins())),
        );
        _titleController.clear();
        setState(() {
          _isUploadVisible = false; // Hide upload card after successful upload
        });
      }
      logger.i('Uploaded report: $fileName, URL: $downloadUrl, facilityId: ${widget.facilityId}');
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading report: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error uploading report: $e');
    } finally {
      if (mounted) {
        setState(() {
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _viewDocument(String url, String fileName) async {
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
            Text('Loading document...', style: GoogleFonts.poppins()),
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
          throw 'Could not open report in browser';
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        if (fileName.toLowerCase().endsWith('.pdf')) {
          final tempDir = await getTemporaryDirectory();
          final filePath = '${tempDir.path}/$fileName';
          final viewResponse = await http.get(Uri.parse(url));
          await File(filePath).writeAsBytes(viewResponse.bodyBytes);
          final file = File(filePath);
          if (await file.exists()) {
            if (mounted) {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PDFViewerScreen(filePath: filePath, fileName: fileName),
                ),
              );
            }
          } else {
            throw 'Failed to download PDF';
          }
        } else {
          Navigator.pop(context);
          throw 'Only PDF viewing is supported on mobile';
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error viewing report: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error viewing report: $e');
    }
  }

  Future<void> _downloadDocument(String url, String fileName) async {
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
            Text('Downloading...', style: GoogleFonts.poppins()),
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
          throw 'Could not download report';
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        bool permissionGranted = await _requestStoragePermission();
        if (!permissionGranted) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Storage permission denied', style: GoogleFonts.poppins())),
            );
          }
          return;
        }

        final downloadsDir = await getExternalStorageDirectory();
        final filePath = '${downloadsDir!.path}/$fileName';
        final dlResponse = await http.get(Uri.parse(url));
        await File(filePath).writeAsBytes(dlResponse.bodyBytes);

        final file = File(filePath);
        if (await file.exists()) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Report downloaded to $filePath', style: GoogleFonts.poppins()),
                action: SnackBarAction(
                  label: 'Open',
                  onPressed: () => OpenFile.open(filePath),
                ),
              ),
            );
          }
          logger.i('Downloaded report: $fileName to $filePath');
        } else {
          throw 'Failed to download report';
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading report: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error downloading report: $e');
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
      }
      return status.isGranted;
    }
    return true;
  }

  Future<void> _deleteDocument(String downloadUrl, String fileName, String docId) async {
    if (!mounted) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Deletion', style: GoogleFonts.poppins()),
        content: Text('Are you sure you want to delete "$fileName"?', style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) {
      logger.i('Deletion cancelled for: $fileName');
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Deleting...', style: GoogleFonts.poppins()),
            ],
          ),
        ),
      );
    }

    try {
      await FirebaseStorage.instance.refFromURL(downloadUrl).delete();
      await FirebaseFirestore.instance.collection('Reports').doc(docId).delete();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report deleted successfully', style: GoogleFonts.poppins())),
        );
      }
      logger.i('Deleted report: $fileName, docId: $docId');
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting report: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error deleting report: $e');
    }
  }

  IconData _getFileIcon(String fileName) {
    return Icons.picture_as_pdf;
  }

  Color _getFileIconColor(String fileName) {
    return Colors.red[600]!;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserRoleProvider, (_, next) {
      final info = next.value;
      if (info == null || !mounted) return;
      setState(() {
        _currentRole = info.roleLabel;
        _organization = info.organization;
      });
    });
    return Scaffold(
      body: ResponsiveScreenWrapper(
        title: 'Reports',
        facilityId: widget.facilityId,
        currentRole: _currentRole,
        organization: _organization,
        child: _buildBody(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _isUploadVisible = !_isUploadVisible),
        backgroundColor: AppColors.primary,
        icon: Icon(_isUploadVisible ? Icons.close_rounded : Icons.upload_file_rounded, color: Colors.white),
        label: Text(
          _isUploadVisible ? 'Cancel' : 'Upload Report',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      ),
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
          if (_isUploadVisible) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: context.surfaceAltColor),
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))],
              ),
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Icon(Icons.upload_file_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Upload Report',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSizeTitle, color: context.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTextField(fontSizeSubtitle),
                            const SizedBox(height: 12),
                            _buildUploadButton(fontSizeSubtitle),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(flex: 3, child: _buildTextField(fontSizeSubtitle)),
                            const SizedBox(width: 12),
                            Expanded(flex: 1, child: _buildUploadButton(fontSizeSubtitle)),
                          ],
                        ),
                ],
              ),
            ),
          ],

          Center(
            child: Text(
              'Uploaded Reports',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSizeTitle, color: context.textPrimary),
            ),
          ),
          const SizedBox(height: 16),

          // Grouping reports by year
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('Reports')
                .where('facilityId', isEqualTo: widget.facilityId)
                .orderBy('uploadedAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                logger.e('StreamBuilder error: ${snapshot.error}');
                return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins());
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Container(
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: context.surfaceAltColor),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  padding: const EdgeInsets.all(40.0),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Icon(Icons.picture_as_pdf_rounded, size: 48, color: Colors.red.withValues(alpha: 0.5)),
                      ),
                      const SizedBox(height: 16),
                      Text('No reports uploaded yet', style: GoogleFonts.poppins(fontSize: fontSizeSubtitle, color: context.textSecondary, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      Text('Use the upload button above to add your first report', style: GoogleFonts.poppins(fontSize: fontSizeSubtitle - 2, color: context.textSecondary.withValues(alpha: 0.7)), textAlign: TextAlign.center),
                    ],
                  ),
                );
              }

              // Grouping by year
              Map<int, List<Report>> groupedReports = {};
              for (var doc in docs) {
                final report = Report.fromSnapshot(doc);
                final year = report.uploadedAt?.year ?? DateTime.now().year;

                if (!groupedReports.containsKey(year)) {
                  groupedReports[year] = [];
                }
                groupedReports[year]!.add(report);
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: groupedReports.entries.map((entry) {
                  final year = entry.key;
                  final reports = entry.value;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: context.surfaceAltColor),
                      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Material(
                        color: Colors.transparent,
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                        initiallyExpanded: true,
                        title: Text(
                          '$year',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSizeTitle, color: context.textPrimary),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text('${reports.length}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary)),
                        ),
                        children: reports.map((report) {
                          final fileIconColor = _getFileIconColor(report.fileName);
                          return Container(
                            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                            decoration: BoxDecoration(
                              color: context.surfaceColor,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: context.surfaceAltColor),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: fileIconColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                    ),
                                    child: Icon(_getFileIcon(report.fileName), color: fileIconColor, size: isMobile ? 24 : 28),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(report.title, style: GoogleFonts.poppins(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: fontSizeSubtitle)),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(Icons.calendar_today_rounded, size: 11, color: context.textSecondary),
                                            const SizedBox(width: 3),
                                            Text(
                                              report.uploadedAt != null ? AppDateFormat.format(report.uploadedAt!) : 'Unknown date',
                                              style: GoogleFonts.poppins(fontSize: isMobile ? 11 : 12, color: context.textSecondary),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'view') {
                                        _viewDocument(report.downloadUrl, report.fileName);
                                      } else if (value == 'download') {
                                        _downloadDocument(report.downloadUrl, report.fileName);
                                      } else if (value == 'delete') {
                                        _deleteDocument(report.downloadUrl, report.fileName, report.id);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: 'view',
                                        child: Row(children: [Icon(Icons.visibility_rounded, color: AppColors.primary, size: 18), const SizedBox(width: 10), Text('View', style: GoogleFonts.poppins())]),
                                      ),
                                      PopupMenuItem(
                                        value: 'download',
                                        child: Row(children: [Icon(Icons.download_rounded, color: AppColors.success, size: 18), const SizedBox(width: 10), Text('Download', style: GoogleFonts.poppins())]),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(children: [Icon(Icons.delete_rounded, color: AppColors.error, size: 18), const SizedBox(width: 10), Text('Delete', style: GoogleFonts.poppins(color: AppColors.error))]),
                                      ),
                                    ],
                                    icon: Icon(Icons.more_vert_rounded, color: context.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                              ),
                            ),
                          ),
                        ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(double fontSize) {
    return TextFormField(
      controller: _titleController,
      decoration: InputDecoration(
        labelText: 'Report Title (Optional)',
        prefixIcon: Icon(Icons.title_rounded, size: 18, color: context.textSecondary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: AppColors.primary, width: 2)),
        filled: true,
        fillColor: context.surfaceColor,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        labelStyle: GoogleFonts.poppins(color: context.textSecondary, fontSize: fontSize),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize),
    );
  }

  Widget _buildUploadButton(double fontSize) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: ElevatedButton.icon(
        onPressed: _uploadDocument,
        icon: const Icon(Icons.upload_file_rounded, color: Colors.white),
        label: Text('Upload PDF', style: GoogleFonts.poppins(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      ),
    );
  }
}

class PDFViewerScreen extends StatelessWidget {
  final String filePath;
  final String fileName;

  const PDFViewerScreen({super.key, required this.filePath, required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: PDFView(
          filePath: filePath,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          onError: (error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error loading PDF: $error', style: GoogleFonts.poppins())),
            );
          },
        ),
      ),
    );
  }
}
