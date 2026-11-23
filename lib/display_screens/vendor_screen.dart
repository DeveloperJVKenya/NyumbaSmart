import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:cmms/models/vendor.dart';
import 'package:cmms/theme/app_theme.dart';

class VendorScreen extends StatefulWidget {
  final String facilityId;

  const VendorScreen({super.key, required this.facilityId});

  @override
  State<VendorScreen> createState() => _VendorScreenState();
}

class _VendorScreenState extends State<VendorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _serviceController = TextEditingController();
  final _contractController = TextEditingController();
  final Logger _logger = Logger();
  String _category = 'General';
  String _status = 'Active';
  String _categoryFilter = 'All';
  String _statusFilter = 'All';
  double _rating = 5.0;
  bool _showForm = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _logger.i('VendorScreen initialized: facilityId=${widget.facilityId}');
  }

  Future<void> _addVendor() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('Please sign in to add vendors');
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final vendorId = const Uuid().v4();
      _logger.i('Adding vendor: vendorId=$vendorId, name=${_nameController.text}');

      final vendor = Vendor(
        id: vendorId,
        vendorId: vendorId,
        name: _nameController.text.trim(),
        contact: _contactController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        services: _serviceController.text.trim(),
        contractDetails: _contractController.text.trim(),
        category: _category,
        rating: _rating,
        status: _status,
        serviceHistory: [
          {
            'action': 'Vendor Added',
            'timestamp': Timestamp.now(),
            'notes': 'Vendor registered in system',
            'userId': user.uid,
          }
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: user.uid,
        userId: user.uid,
        facilityId: widget.facilityId,
      );

      await FirebaseFirestore.instance
          .collection('Vendors')
          .doc(vendorId)
          .set(vendor.toMap());

      if (mounted) {
        setState(() {
          _showForm = false;
          _isLoading = false;
        });
        _clearForm();
        _showSnackBar('Vendor added successfully');
      }
    } catch (e, stackTrace) {
      _logger.e('Error adding vendor: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error adding vendor: $e');
      }
    }
  }

  Future<void> _addServiceHistory(String docId, String service, String notes) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      _logger.i('Adding service history: docId=$docId, service=$service');
      await FirebaseFirestore.instance
          .collection('Vendors')
          .doc(docId)
          .update({
        'serviceHistory': FieldValue.arrayUnion([
          {
            'action': service,
            'timestamp': Timestamp.now(),
            'notes': notes,
            'userId': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          }
        ]),
        'updatedAt': Timestamp.now(),
      });
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Service logged successfully');
      }
    } catch (e, stackTrace) {
      _logger.e('Error logging service: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error logging service: $e');
      }
    }
  }

  Future<void> _updateVendorRating(String docId, double newRating) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      _logger.i('Updating vendor rating: docId=$docId, rating=$newRating');
      await FirebaseFirestore.instance
          .collection('Vendors')
          .doc(docId)
          .update({
        'rating': newRating,
        'updatedAt': Timestamp.now(),
        'serviceHistory': FieldValue.arrayUnion([
          {
            'action': 'Rating updated to $newRating stars',
            'timestamp': Timestamp.now(),
            'notes': 'Vendor rating updated',
            'userId': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          }
        ]),
      });
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Rating updated successfully');
      }
    } catch (e, stackTrace) {
      _logger.e('Error updating rating: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error updating rating: $e');
      }
    }
  }

  Future<void> _updateVendorStatus(String docId, String newStatus) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      _logger.i('Updating vendor status: docId=$docId, status=$newStatus');
      await FirebaseFirestore.instance
          .collection('Vendors')
          .doc(docId)
          .update({
        'status': newStatus,
        'updatedAt': Timestamp.now(),
        'serviceHistory': FieldValue.arrayUnion([
          {
            'action': 'Status changed to $newStatus',
            'timestamp': Timestamp.now(),
            'notes': 'Vendor status updated',
            'userId': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          }
        ]),
      });
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Status updated to $newStatus');
      }
    } catch (e, stackTrace) {
      _logger.e('Error updating status: $e', stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error updating status: $e');
      }
    }
  }

  void _clearForm() {
    _nameController.clear();
    _contactController.clear();
    _emailController.clear();
    _phoneController.clear();
    _serviceController.clear();
    _contractController.clear();
    _category = 'General';
    _status = 'Active';
    _rating = 5.0;
  }

  void _clearFilters() {
    if (mounted) {
      setState(() {
        _categoryFilter = 'All';
        _statusFilter = 'All';
      });
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _serviceController.dispose();
    _contractController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Vendor Management',
      facilityId: widget.facilityId,
      currentRole: 'Engineer',
      organization: '-',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _showForm = !_showForm),
        backgroundColor: AppColors.primary,
        icon: Icon(_showForm ? Icons.close_rounded : Icons.add_rounded, color: Colors.white),
        label: Text(_showForm ? 'Cancel' : 'New Vendor', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      ),
      child: Stack(
        children: [
          _buildBody(),
          if (_showForm) _buildFormOverlay(),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 768;
    final isTablet = screenWidth > 768 && screenWidth <= 1024;
    final padding = isMobile ? 8.0 : isTablet ? 12.0 : 16.0;
    final fontSizeTitle = isMobile ? 16.0 : isTablet ? 20.0 : 24.0;
    final fontSize = isMobile ? 12.0 : isTablet ? 14.0 : 16.0;

    return Column(
      children: [
        _buildFilterSection(padding: padding, fontSizeTitle: fontSizeTitle, fontSize: fontSize, isMobile: isMobile),
        Expanded(child: _buildVendorList(padding: padding, fontSize: fontSize)),
      ],
    );
  }

  Widget _buildFilterSection({required double padding, required double fontSizeTitle, required double fontSize, required bool isMobile}) {
    return Container(
      margin: EdgeInsets.all(padding),
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.surfaceAltColor),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Filters', style: GoogleFonts.poppins(fontSize: fontSizeTitle, fontWeight: FontWeight.w700, color: context.textPrimary)),
              TextButton.icon(
                onPressed: _clearFilters,
                icon: Icon(Icons.clear_rounded, size: 15, color: context.textSecondary),
                label: Text('Clear', style: GoogleFonts.poppins(fontSize: fontSize, color: context.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          isMobile
              ? Wrap(spacing: 12, runSpacing: 12, children: [
                  _buildFilterDropdown('Category', _categoryFilter, ['All', 'General', 'Electrical', 'Plumbing', 'HVAC', 'Cleaning', 'Security', 'IT Support'], (v) => setState(() => _categoryFilter = v!), fontSize),
                  _buildFilterDropdown('Status', _statusFilter, ['All', 'Active', 'Inactive', 'Suspended'], (v) => setState(() => _statusFilter = v!), fontSize),
                ])
              : Row(children: [
                  Expanded(child: _buildFilterDropdown('Category', _categoryFilter, ['All', 'General', 'Electrical', 'Plumbing', 'HVAC', 'Cleaning', 'Security', 'IT Support'], (v) => setState(() => _categoryFilter = v!), fontSize)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildFilterDropdown('Status', _statusFilter, ['All', 'Active', 'Inactive', 'Suspended'], (v) => setState(() => _statusFilter = v!), fontSize)),
                ]),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, double fontSize) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary)))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: AppColors.primary, width: 2)),
        filled: true, fillColor: context.surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        labelStyle: GoogleFonts.poppins(fontSize: fontSize, color: context.textSecondary),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary, fontWeight: FontWeight.w500),
      dropdownColor: context.cardColor,
      icon: Icon(Icons.keyboard_arrow_down_rounded, color: context.textSecondary),
    );
  }

  Widget _buildVendorList({required double padding, required double fontSize}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _buildVendorStream(),
      builder: (context, snapshot) {
        _logger.i('StreamBuilder snapshot: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, docCount=${snapshot.data?.docs.length ?? 0}');
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          _logger.e('Firestore error: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                const SizedBox(height: 8),
                Text(
                  'Error loading vendors',
                  style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.red[600]),
                ),
                Text(
                  '${snapshot.error}',
                  style: GoogleFonts.poppins(fontSize: fontSize - 2, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.business_outlined, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  'No vendors found',
                  style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(padding),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final vendor = Vendor.fromSnapshot(docs[index]);
            final statusColor = _getStatusColor(vendor.status);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.surfaceAltColor),
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Material(
                  color: Colors.transparent,
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.sm)),
                      child: Icon(_getStatusIcon(vendor.status), color: statusColor, size: 20),
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(vendor.name, style: GoogleFonts.poppins(fontSize: fontSize + 1, fontWeight: FontWeight.w600, color: context.textPrimary))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(vendor.status, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Wrap(spacing: 10, children: [
                        _vendorChip(Icons.category_rounded, vendor.category, context.textSecondary, fontSize),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          ...List.generate(5, (i) => Icon(i < vendor.rating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFF59E0B), size: 13)),
                          const SizedBox(width: 3),
                          Text(vendor.rating.toStringAsFixed(1), style: GoogleFonts.poppins(fontSize: 11.5, color: context.textSecondary, fontWeight: FontWeight.w500)),
                        ]),
                      ]),
                    ),
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Divider(color: context.surfaceAltColor, height: 16),
                            _buildDetailRow('Contact', vendor.contact, fontSize: fontSize),
                            if (vendor.email.isNotEmpty) _buildDetailRow('Email', vendor.email, fontSize: fontSize),
                            if (vendor.phone.isNotEmpty) _buildDetailRow('Phone', vendor.phone, fontSize: fontSize),
                            _buildDetailRow('Services', vendor.services, fontSize: fontSize),
                            if (vendor.contractDetails.isNotEmpty) _buildDetailRow('Contract', vendor.contractDetails, fontSize: fontSize),
                            _buildDetailRow('Added', vendor.createdAt != null ? DateFormat.yMMMd().format(vendor.createdAt!) : 'Unknown', fontSize: fontSize),
                            if (vendor.serviceHistory.isNotEmpty) _buildHistorySection(vendor.serviceHistory, fontSize: fontSize, padding: padding),
                            const SizedBox(height: 10),
                            _buildActionButtons(vendor, fontSize: fontSize),
                          ],
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Stream<QuerySnapshot> _buildVendorStream() {
    Query query = FirebaseFirestore.instance
        .collection('Vendors')
        .where('facilityId', isEqualTo: widget.facilityId);

    if (_categoryFilter != 'All') {
      query = query.where('category', isEqualTo: _categoryFilter);
    }
    if (_statusFilter != 'All') {
      query = query.where('status', isEqualTo: _statusFilter);
    }

    return query.orderBy('createdAt', descending: true).snapshots();
  }

  Widget _vendorChip(IconData icon, String label, Color color, double fontSize) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 3),
      Text(label, style: GoogleFonts.poppins(fontSize: 11.5, color: color, fontWeight: FontWeight.w500)),
    ]);
  }

  Widget _buildDetailRow(String label, String value, {required double fontSize}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: GoogleFonts.poppins(fontSize: fontSize - 1, fontWeight: FontWeight.w500, color: context.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: GoogleFonts.poppins(fontSize: fontSize - 1, color: context.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(List<Map<String, dynamic>> history, {required double fontSize, required double padding}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Service History:',
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          ...history.take(3).map((entry) => Container(
                margin: EdgeInsets.only(bottom: padding / 2),
                padding: EdgeInsets.all(padding),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry['action'] ?? '',
                      style: GoogleFonts.poppins(fontSize: fontSize, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'at ${entry['timestamp'] != null ? DateFormat.yMMMd().format((entry['timestamp'] as Timestamp).toDate()) : 'Unknown date'}',
                      style: GoogleFonts.poppins(
                        fontSize: fontSize - 2,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (entry['notes'] != null && entry['notes'].isNotEmpty)
                      Text(
                        entry['notes'],
                        style: GoogleFonts.poppins(fontSize: fontSize - 1),
                      ),
                  ],
                ),
              )),
          if (history.length > 3)
            Text(
              '... and ${history.length - 3} more entries',
              style: GoogleFonts.poppins(
                fontSize: fontSize - 1,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Vendor vendor, {required double fontSize}) {
    return Wrap(spacing: 8, runSpacing: 6, children: [
      OutlinedButton.icon(
        onPressed: () => _showLogServiceDialog(vendor),
        icon: Icon(Icons.add_task_rounded, size: 14, color: AppColors.primary),
        label: Text('Log Service', style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      ),
      OutlinedButton.icon(
        onPressed: () => _showRatingDialog(vendor),
        icon: const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
        label: Text('Rate', style: GoogleFonts.poppins(fontSize: 12.5, color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0x80F59E0B)),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      ),
      OutlinedButton.icon(
        onPressed: () => _showStatusDialog(vendor),
        icon: Icon(Icons.edit_rounded, size: 14, color: context.textSecondary),
        label: Text('Status', style: GoogleFonts.poppins(fontSize: 12.5, color: context.textSecondary, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: context.textSecondary.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      ),
    ]);
  }

  void _showLogServiceDialog(Vendor vendor) {
    final serviceController = TextEditingController();
    final notesController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        title: Row(children: [
          Icon(Icons.add_task_rounded, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text('Log Service', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: context.textPrimary)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: serviceController,
            decoration: _fieldDeco('Service Performed', 14),
            style: GoogleFonts.poppins(color: context.textPrimary),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: notesController,
            decoration: _fieldDeco('Notes (optional)', 14),
            style: GoogleFonts.poppins(color: context.textPrimary),
            maxLines: 2,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.poppins(color: context.textSecondary))),
          ElevatedButton(
            onPressed: () {
              if (serviceController.text.isNotEmpty && mounted) { _addServiceHistory(vendor.id, serviceController.text, notesController.text); Navigator.pop(context); }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm))),
            child: Text('Log Service', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showRatingDialog(Vendor vendor) {
    double newRating = vendor.rating;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          title: Row(children: [
            const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 20),
            const SizedBox(width: 8),
            Text('Rate Vendor', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: context.textPrimary)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Current: ${vendor.rating.toStringAsFixed(1)} stars', style: GoogleFonts.poppins(color: context.textSecondary)),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) => GestureDetector(
              onTap: () => setDState(() => newRating = i + 1.0),
              child: Icon(i < newRating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFF59E0B), size: 32),
            ))),
            const SizedBox(height: 8),
            Text('New: ${newRating.toStringAsFixed(1)} stars', style: GoogleFonts.poppins(color: context.textPrimary, fontWeight: FontWeight.w600)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.poppins(color: context.textSecondary))),
            ElevatedButton(
              onPressed: () { if (mounted) { _updateVendorRating(vendor.id, newRating); Navigator.pop(context); } },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm))),
              child: Text('Update Rating', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  void _showStatusDialog(Vendor vendor) {
    String selectedStatus = vendor.status;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        title: Row(children: [
          Icon(Icons.edit_rounded, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text('Update Status', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: context.textPrimary)),
        ]),
        content: DropdownButtonFormField<String>(
          initialValue: selectedStatus,
          items: ['Active', 'Inactive', 'Suspended']
              .map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins(color: context.textPrimary)))).toList(),
          onChanged: (v) => selectedStatus = v!,
          decoration: _fieldDeco('Status', 14),
          style: GoogleFonts.poppins(color: context.textPrimary, fontWeight: FontWeight.w500),
          dropdownColor: context.cardColor,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: context.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.poppins(color: context.textSecondary))),
          ElevatedButton(
            onPressed: () { if (mounted) { _updateVendorStatus(vendor.id, selectedStatus); Navigator.pop(context); } },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm))),
            child: Text('Update', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildFormOverlay() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 768;
    final isTablet = screenWidth > 768 && screenWidth <= 1024;
    final padding = isMobile ? 8.0 : isTablet ? 12.0 : 16.0;
    final fontSize = isMobile ? 12.0 : isTablet ? 14.0 : 16.0;

    return GestureDetector(
      onTap: () => setState(() => _showForm = false),
      child: Container(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: isMobile ? screenWidth * 0.95 : isTablet ? screenWidth * 0.75 : 620,
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: _buildVendorForm(padding: padding, fontSize: fontSize),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDeco(String label, double fontSize, {IconData? icon}) => InputDecoration(
    labelText: label,
    prefixIcon: icon != null ? Icon(icon, size: 18, color: context.textSecondary) : null,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.surfaceAltColor)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: AppColors.primary, width: 2)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: AppColors.error)),
    filled: true, fillColor: context.surfaceColor,
    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
    labelStyle: GoogleFonts.poppins(color: context.textSecondary, fontSize: fontSize),
  );

  Widget _buildVendorForm({required double padding, required double fontSize}) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
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
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: context.surfaceAltColor, borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: Icon(Icons.business_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Add New Vendor', style: GoogleFonts.poppins(fontSize: fontSize + 2, fontWeight: FontWeight.w700, color: context.textPrimary))),
                IconButton(icon: Icon(Icons.close_rounded, color: context.textSecondary), onPressed: () => setState(() => _showForm = false)),
              ]),
            ),
            Padding(
              padding: EdgeInsets.all(padding * 1.5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextFormField(
                  controller: _nameController,
                  decoration: _fieldDeco('Vendor Name', fontSize, icon: Icons.business_rounded),
                  style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary),
                  validator: (v) => v!.isEmpty ? 'Enter vendor name' : null,
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: TextFormField(
                    controller: _emailController,
                    decoration: _fieldDeco('Email', fontSize, icon: Icons.email_rounded),
                    style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) { if (v!.isNotEmpty && !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) return 'Invalid email'; return null; },
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: TextFormField(
                    controller: _phoneController,
                    decoration: _fieldDeco('Phone', fontSize, icon: Icons.phone_rounded),
                    style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary),
                    keyboardType: TextInputType.phone,
                    validator: (v) { if (v!.isNotEmpty && !RegExp(r'^\+?[\d\s-]{7,15}$').hasMatch(v)) return 'Invalid phone'; return null; },
                  )),
                ]),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _contactController,
                  decoration: _fieldDeco('Primary Contact', fontSize, icon: Icons.person_rounded),
                  style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary),
                  validator: (v) => v!.isEmpty ? 'Enter contact info' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  items: ['General', 'Electrical', 'Plumbing', 'HVAC', 'Cleaning', 'Security', 'IT Support']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c, style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary)))).toList(),
                  onChanged: (v) { if (mounted) setState(() => _category = v!); },
                  decoration: _fieldDeco('Category', fontSize),
                  style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary, fontWeight: FontWeight.w500),
                  dropdownColor: context.cardColor,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: context.textSecondary),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _serviceController,
                  decoration: _fieldDeco('Services Offered', fontSize, icon: Icons.build_rounded),
                  style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary),
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _contractController,
                  decoration: _fieldDeco('Contract Details (optional)', fontSize, icon: Icons.description_rounded),
                  style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary),
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    items: ['Active', 'Inactive', 'Suspended']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary)))).toList(),
                    onChanged: (v) { if (mounted) setState(() => _status = v!); },
                    decoration: _fieldDeco('Status', fontSize),
                    style: GoogleFonts.poppins(fontSize: fontSize, color: context.textPrimary, fontWeight: FontWeight.w500),
                    dropdownColor: context.cardColor,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: context.textSecondary),
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Initial Rating', style: GoogleFonts.poppins(fontSize: fontSize - 1, color: context.textSecondary, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Row(children: List.generate(5, (i) => GestureDetector(
                      onTap: () { if (mounted) setState(() => _rating = i + 1.0); },
                      child: Icon(i < _rating ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFF59E0B), size: fontSize + 6),
                    ))),
                  ])),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _addVendor,
                      icon: const Icon(Icons.business_center_rounded, color: Colors.white, size: 18),
                      label: Text('Add Vendor', style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.white, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green.shade600;
      case 'inactive':
        return Colors.grey.shade600;
      case 'suspended':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Icons.check_circle;
      case 'inactive':
        return Icons.pause_circle;
      case 'suspended':
        return Icons.block;
      default:
        return Icons.help;
    }
  }
}
