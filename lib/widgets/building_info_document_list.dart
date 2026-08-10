import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';
import 'package:cmms/widgets/pdf_viewer_screen.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

/// A single uploaded file entry, normalized across the three Building
/// Information collections (BuildingSurveys/Documentations/Drawings) so
/// [BuildingInfoScreen] doesn't need to know about their individual model
/// classes.
class BuildingInfoDocument {
  final String id;
  final String title;
  final String fileName;
  final String downloadUrl;
  final DateTime? uploadedAt;
  final String category;

  const BuildingInfoDocument({
    required this.id,
    required this.title,
    required this.fileName,
    required this.downloadUrl,
    required this.uploadedAt,
    required this.category,
  });
}

/// Shared screen powering Building Survey, Documentations, and Drawings —
/// previously three ~900-line near-identical copies differing only in
/// collection name, category list, storage path, and allowed file types.
/// Each thin screen file (building_survey_screen.dart etc.) just supplies
/// those parameters.
class BuildingInfoScreen extends ConsumerStatefulWidget {
  final String facilityId;
  final String title;
  final String listHeading;
  final String emptyMessage;
  final String collectionName;
  final String storagePathSegment;
  final Map<String, String> categories;
  final String defaultCategory;
  final List<String> allowedExtensions;
  final BuildingInfoDocument Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) fromSnapshot;
  final IconData Function(String fileName) fileIcon;
  final Color Function(String fileName) fileIconColor;

  const BuildingInfoScreen({
    super.key,
    required this.facilityId,
    required this.title,
    required this.listHeading,
    required this.emptyMessage,
    required this.collectionName,
    required this.storagePathSegment,
    required this.categories,
    required this.defaultCategory,
    required this.allowedExtensions,
    required this.fromSnapshot,
    required this.fileIcon,
    required this.fileIconColor,
  });

  @override
  ConsumerState<BuildingInfoScreen> createState() => _BuildingInfoScreenState();
}

class _BuildingInfoScreenState extends ConsumerState<BuildingInfoScreen> {
  final Logger logger = Logger(printer: PrettyPrinter());
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory; // null = "All"

  // Created once (not inline in build/StreamBuilder) so typing in the
  // search box or tapping a category chip — both call setState on this
  // widget — don't hand StreamBuilder a new Stream instance each time.
  // A fresh instance reads as a brand new subscription, which briefly
  // resets StreamBuilder to ConnectionState.waiting (the skeleton
  // placeholder) and was the cause of the layout flicker between the
  // skeleton's height and the loaded list's height.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _documentsStream;

  @override
  void initState() {
    super.initState();
    _documentsStream = FirebaseFirestore.instance
        .collection(widget.collectionName)
        .where('facilityId', isEqualTo: widget.facilityId)
        .orderBy('uploadedAt', descending: true)
        .snapshots();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roleInfo = ref.watch(currentUserRoleProvider).valueOrNull;

    return ResponsiveScreenWrapper(
      title: widget.title,
      facilityId: widget.facilityId,
      currentRole: roleInfo?.roleLabel ?? 'User',
      organization: roleInfo?.organization ?? '-',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUploadSheet(context),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.upload_file_rounded, color: Colors.white),
        label: Text('Upload', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      ),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(top: false, child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = AppBreakpoints.isMobile(screenWidth);
    const maxContentWidth = 1100.0;
    const basePadding = AppSpacing.xl;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Widen the padding itself on very wide windows instead of
        // centering a fixed-width box inside the scroll view — a
        // Center/Align wrapper here previously ended up vertically
        // centering this (usually short) content within the whole
        // viewport, leaving a large blank band above the header. Padding
        // can only ever push content in from the edges, so top-anchoring
        // is guaranteed regardless of content height.
        final overflow = constraints.maxWidth - maxContentWidth;
        final horizontalPadding = isMobile ? AppSpacing.md : basePadding + (overflow > 0 ? overflow / 2 : 0);

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontalPadding, AppSpacing.md, horizontalPadding, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isMobile),
              const SizedBox(height: AppSpacing.lg),
              _buildSearchField(isMobile),
              const SizedBox(height: AppSpacing.sm),
              _buildCategoryFilters(),
              const SizedBox(height: AppSpacing.lg),
              _buildDocumentStream(isMobile),
            ],
          ),
        );
      },
    );
  }

  /// A single compact identity block instead of the old duplicate-title
  /// layout (the AppBar already shows [widget.title]) — this removed the
  /// awkward gap that previously sat above the list heading.
  Widget _buildHeader(bool isMobile) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: const Icon(Icons.folder_special_rounded, color: Colors.white, size: 26),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.listHeading,
                style: GoogleFonts.poppins(fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                'Browse, search and manage every uploaded file',
                style: GoogleFonts.poppins(fontSize: isMobile ? 12.5 : 13.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(bool isMobile) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: 'Search by title or file name…',
        hintStyle: GoogleFonts.poppins(fontSize: 13.5, color: AppColors.textSecondary.withValues(alpha: 0.8)),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                onPressed: () => setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                }),
              ),
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: isMobile ? 12 : 14),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _categoryChip(label: 'All', selected: _selectedCategory == null, onTap: () => setState(() => _selectedCategory = null)),
          ...widget.categories.keys.map(
            (category) => Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: _categoryChip(
                label: widget.categories[category] ?? category,
                selected: _selectedCategory == category,
                onTap: () => setState(() => _selectedCategory = category),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip({required String label, required bool selected, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: selected ? AppColors.primaryGradient : null,
            color: selected ? null : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: selected ? Colors.transparent : AppColors.textSecondary.withValues(alpha: 0.2)),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentStream(bool isMobile) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _documentsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          logger.e('Firestore error: ${snapshot.error}');
          return Center(
            child: Column(
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                const SizedBox(height: 12),
                Text('Error loading ${widget.listHeading.toLowerCase()}', style: GoogleFonts.poppins(color: AppColors.error, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppSkeletonList(count: 4, itemHeight: 96);
        }

        final allItems = snapshot.data?.docs.map(widget.fromSnapshot).toList() ?? [];

        if (allItems.isEmpty) {
          return _emptyState(icon: Icons.folder_open_rounded, message: widget.emptyMessage, hint: 'Tap "Upload" to add your first file');
        }

        final items = allItems.where((item) {
          final matchesCategory = _selectedCategory == null || item.category == _selectedCategory;
          final matchesSearch = _searchQuery.isEmpty ||
              item.title.toLowerCase().contains(_searchQuery) ||
              item.fileName.toLowerCase().contains(_searchQuery);
          return matchesCategory && matchesSearch;
        }).toList();

        if (items.isEmpty) {
          return _emptyState(icon: Icons.search_off_rounded, message: 'No files match your search', hint: 'Try a different keyword or category');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: 4),
              child: Text(
                '${items.length} ${items.length == 1 ? 'file' : 'files'}',
                style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
              ),
            ),
            // An adaptive grid on wide screens and a single column on
            // mobile — genuinely responds to available width instead of a
            // fixed-column layout or a permanently full-width row.
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 380).floor().clamp(1, 3);
                if (columns == 1) {
                  return Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        _AnimatedEntry(index: i, child: _buildCard(items[i], isMobile)),
                      ],
                    ],
                  );
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: constraints.maxWidth / columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 108,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _AnimatedEntry(index: index, child: _buildCard(items[index], false)),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildCard(BuildingInfoDocument item, bool isMobile) {
    return _DocumentCard(
      document: item,
      isMobile: isMobile,
      icon: widget.fileIcon(item.fileName),
      iconColor: widget.fileIconColor(item.fileName),
      onView: () => _viewDocument(item.downloadUrl, item.fileName),
      onDownload: () => _downloadDocument(item.downloadUrl, item.fileName),
      onDelete: () => _deleteDocument(item.downloadUrl, item.fileName, item.id),
    );
  }

  Widget _emptyState({required IconData icon, required String message, required String hint}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(icon, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(message, style: GoogleFonts.poppins(fontSize: 16, color: AppColors.textSecondary, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(hint, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }

  Future<void> _showUploadSheet(BuildContext context) async {
    final titleController = TextEditingController();
    String selectedCategory = widget.defaultCategory;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              return Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(color: AppColors.textSecondary.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    Text('Upload ${widget.title}', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const SizedBox(height: 20),
                    AppTextField(controller: titleController, label: 'Title (optional)', icon: Icons.title_rounded),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_rounded, color: AppColors.primary)),
                      items: widget.categories.entries
                          .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value, style: GoogleFonts.poppins())))
                          .toList(),
                      onChanged: (value) => setSheetState(() => selectedCategory = value ?? selectedCategory),
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppGradientButton(
                        label: 'Choose File & Upload',
                        icon: Icons.upload_file_rounded,
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _pickAndUpload(titleController.text.trim(), selectedCategory);
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _pickAndUpload(String titleInput, String category) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: widget.allowedExtensions,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;

      final platformFile = result.files.single;
      final fileName = platformFile.name;
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        _showSnackBar('Please log in to upload');
        return;
      }

      final title = titleInput.isEmpty ? fileName : titleInput;

      if (!mounted) return;
      _showProgressDialog('Uploading $fileName…');

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('facilities/${widget.facilityId}/${widget.storagePathSegment}/${DateTime.now().millisecondsSinceEpoch}_$fileName');

      UploadTask uploadTask;
      if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final fileBytes = platformFile.bytes;
        if (fileBytes == null) throw 'Failed to read file data for web/desktop upload';
        uploadTask = storageRef.putData(
          fileBytes,
          SettableMetadata(customMetadata: {'originalName': fileName, 'uploadedBy': user.uid, 'facilityId': widget.facilityId}),
        );
      } else {
        final filePath = platformFile.path;
        if (filePath == null) throw 'Failed to get file path for mobile upload';
        final file = File(filePath);
        if (!await file.exists()) throw 'Selected file does not exist';
        uploadTask = storageRef.putFile(
          file,
          SettableMetadata(customMetadata: {'originalName': fileName, 'uploadedBy': user.uid, 'facilityId': widget.facilityId}),
        );
      }

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection(widget.collectionName).add({
        'userId': user.uid,
        'title': title,
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'uploadedAt': FieldValue.serverTimestamp(),
        'facilityId': widget.facilityId,
        'category': category,
        'fileSize': platformFile.size,
        'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      });

      if (mounted) {
        Navigator.pop(context); // close progress dialog
        _showSnackBar('$fileName uploaded successfully');
      }
      logger.i('Uploaded ${widget.collectionName} file: $fileName');
    } catch (e) {
      logger.e('Error uploading file: $e');
      if (mounted) {
        Navigator.pop(context); // close progress dialog
        _showSnackBar('Error uploading file: $e');
      }
    }
  }

  Future<void> _viewDocument(String url, String fileName) async {
    try {
      if (kIsWeb) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not open file in browser';
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        if (fileName.toLowerCase().endsWith('.pdf')) {
          final tempDir = await getTemporaryDirectory();
          final filePath = '${tempDir.path}/$fileName';

          if (mounted) _showProgressDialog('Downloading for viewing…');
          await Dio().download(url, filePath);
          final file = File(filePath);
          if (mounted) Navigator.pop(context);

          if (await file.exists()) {
            if (mounted) {
              Navigator.push(context, MaterialPageRoute(builder: (context) => PDFViewerScreen(filePath: filePath, fileName: fileName)));
            }
          } else {
            throw 'Failed to download file';
          }
        } else {
          throw 'Only PDF preview is supported on mobile — use Download instead';
        }
      } else {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not open file';
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        _showSnackBar('Error viewing file: $e');
      }
      logger.e('Error viewing file: $e');
    }
  }

  Future<void> _downloadDocument(String url, String fileName) async {
    try {
      if (kIsWeb) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not download file';
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        final permissionGranted = await _requestStoragePermission();
        if (!permissionGranted) {
          _showSnackBar('Storage permission denied');
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';

        if (mounted) _showProgressDialog('Downloading $fileName…');
        await Dio().download(url, filePath);
        if (mounted) Navigator.pop(context);

        final file = File(filePath);
        if (await file.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Downloaded $fileName', style: GoogleFonts.poppins()),
                backgroundColor: AppColors.success,
                action: SnackBarAction(label: 'Open', textColor: Colors.white, onPressed: () => OpenFile.open(filePath)),
              ),
            );
          }
        } else {
          throw 'Failed to download file';
        }
      } else {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not download file';
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        _showSnackBar('Error downloading file: $e');
      }
      logger.e('Error downloading file: $e');
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) status = await Permission.storage.request();
      return status.isGranted;
    }
    return true;
  }

  Future<void> _deleteDocument(String downloadUrl, String fileName, String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Delete "$fileName"?', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text('This cannot be undone.', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('Cancel', style: GoogleFonts.poppins(color: AppColors.textPrimary))),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text('Delete', style: GoogleFonts.poppins(color: AppColors.error, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseStorage.instance.refFromURL(downloadUrl).delete();
      await FirebaseFirestore.instance.collection(widget.collectionName).doc(docId).delete();
      _showSnackBar('Deleted successfully');
      logger.i('Deleted ${widget.collectionName} file: $fileName');
    } catch (e) {
      logger.e('Error deleting file: $e');
      _showSnackBar('Error deleting file: $e');
    }
  }

  void _showProgressDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        content: Row(
          children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary)),
            const SizedBox(width: 16),
            Expanded(child: Text(message, style: GoogleFonts.poppins())),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.poppins())));
    }
  }
}

class _DocumentCard extends StatefulWidget {
  final BuildingInfoDocument document;
  final bool isMobile;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onView;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _DocumentCard({
    required this.document,
    required this.isMobile,
    required this.icon,
    required this.iconColor,
    required this.onView,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  State<_DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<_DocumentCard> {
  bool _hovering = false;

  BuildingInfoDocument get document => widget.document;
  bool get isMobile => widget.isMobile;
  IconData get icon => widget.icon;
  Color get iconColor => widget.iconColor;
  VoidCallback get onView => widget.onView;
  VoidCallback get onDownload => widget.onDownload;
  VoidCallback get onDelete => widget.onDelete;

  Widget _menu() {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      onSelected: (value) {
        if (value == 'view') onView();
        if (value == 'download') onDownload();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'view', child: Row(children: [const Icon(Icons.visibility_rounded, color: AppColors.primary, size: 20), const SizedBox(width: 8), Text('View', style: GoogleFonts.poppins())])),
        PopupMenuItem(value: 'download', child: Row(children: [const Icon(Icons.download_rounded, color: AppColors.success, size: 20), const SizedBox(width: 8), Text('Download', style: GoogleFonts.poppins())])),
        PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete_rounded, color: AppColors.error, size: 20), const SizedBox(width: 8), Text('Delete', style: GoogleFonts.poppins())])),
      ],
    );
  }

  Widget _categoryPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        document.category,
        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.primaryDark),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _dateRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.textSecondary.withValues(alpha: 0.8)),
        const SizedBox(width: 6),
        Text(
          document.uploadedAt != null ? DateFormat('MMM dd, yyyy').format(document.uploadedAt!) : 'Unknown date',
          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary.withValues(alpha: 0.8)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _hovering ? 1.01 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: onView,
            // A full-width row (not a fixed-width grid tile) so the item
            // always spans the actual available width — 1 or 2 documents no
            // longer look pinned to the left of a wide screen.
            child: SizedBox(
              width: double.infinity,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: _hovering ? 0.16 : 0.08),
                      blurRadius: _hovering ? 28 : 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.md)),
                      child: Icon(icon, color: iconColor, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            document.title,
                            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          if (isMobile)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [_categoryPill(), const SizedBox(height: 8), _dateRow()],
                            )
                          else
                            Row(children: [_categoryPill(), const SizedBox(width: 14), _dateRow()]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _menu(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Staggers each card's fade + slide-in by index so the list/grid feels
/// alive on first paint instead of popping in all at once.
class _AnimatedEntry extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedEntry({required this.index, required this.child});

  @override
  State<_AnimatedEntry> createState() => _AnimatedEntryState();
}

class _AnimatedEntryState extends State<_AnimatedEntry> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(_fade);
    Future.delayed(Duration(milliseconds: 25 * widget.index.clamp(0, 12)), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
