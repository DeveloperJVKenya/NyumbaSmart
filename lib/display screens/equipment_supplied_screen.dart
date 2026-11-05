import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/models/equipment.dart';
import 'package:cmms/models/bim_model.dart';
import 'package:cmms/screens/bim/bim_import_screen.dart';
import 'package:cmms/display%20screens/request_screen.dart';
import 'package:cmms/display%20screens/work_order_screen.dart';
import 'package:cmms/screens/bim/bim_models_screen.dart';
import 'package:cmms/screens/bim/bim_viewer_screen.dart';
import 'package:cmms/widgets/equipment_activity_section.dart';
import 'package:cmms/widgets/equipment_picker_field.dart';
import 'package:cmms/screens/bim/spaces_screen.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class EquipmentSuppliedScreen extends StatefulWidget {
  final String facilityId;

  const EquipmentSuppliedScreen({super.key, required this.facilityId});

  @override
  State<EquipmentSuppliedScreen> createState() => _EquipmentSuppliedScreenState();
}

class _EquipmentSuppliedScreenState extends State<EquipmentSuppliedScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _serialController = TextEditingController();
  final _locationController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _warrantyController = TextEditingController();
  final _notesController = TextEditingController();
  final Logger _logger = Logger();
  String _status = 'Active';
  String _statusFilter = 'All';
  String _typeFilter = 'All';
  final List<Map<String, String>> _attachmentUrls = [];
  bool _showForm = false;
  double? _uploadProgress;

  // BIM: floors/rooms for the form picker, the space filter and resolving spaceId -> name.
  List<BimSpace> _spaces = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _spacesSub;
  String? _formSpaceId;
  String _sourceFilter = 'All'; // All | Manual | BIM import
  String _spaceFilter = 'All'; // All | <space doc id>
  bool _majorOnly = false; // hide minor electrical components (conduits, cables, etc.)

  @override
  void initState() {
    super.initState();
    _logger.i('EquipmentSuppliedScreen initialized: facilityId=${widget.facilityId}');
    _spacesSub = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('spaces')
        .snapshots()
        .listen((snap) {
      final spaces = snap.docs.map(BimSpace.fromSnapshot).toList();
      // Floors first (by elevation), then rooms by name, so dropdowns read top-down.
      spaces.sort((a, b) {
        if (a.kind != b.kind) return a.kind == BimSpaceKind.storey ? -1 : 1;
        if (a.kind == BimSpaceKind.storey) return (a.elevation ?? 0).compareTo(b.elevation ?? 0);
        return a.name.compareTo(b.name);
      });
      if (mounted) setState(() => _spaces = spaces);
    }, onError: (e) => _logger.w('Spaces unavailable: $e'));
  }

  BimSpace? _spaceById(String? id) {
    if (id == null) return null;
    for (final s in _spaces) {
      if (s.id == id) return s;
    }
    return null;
  }

  String _spaceLabel(BimSpace s) {
    if (s.kind == BimSpaceKind.storey) return s.name;
    final floor = _spaceById(s.parentId);
    return floor == null ? s.name : '${s.name}  ·  ${floor.name}';
  }

  @override
  void dispose() {
    _spacesSub?.cancel();
    _nameController.dispose();
    _typeController.dispose();
    _serialController.dispose();
    _locationController.dispose();
    _purchasePriceController.dispose();
    _warrantyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addEquipment() async {
    if (_formKey.currentState!.validate()) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) _showSnackBar('Please sign in to add equipment');
        return;
      }

      try {
        final equipmentId = const Uuid().v4();
        _logger.i('Adding equipment: equipmentId=$equipmentId, name=${_nameController.text}');

        final equipment = Equipment(
          id: equipmentId,
          equipmentId: equipmentId,
          name: _nameController.text.trim(),
          type: _typeController.text.trim(),
          serialNumber: _serialController.text.trim(),
          // The picked room also fills the legacy free-text location when that was left empty.
          locationId: _locationController.text.trim().isNotEmpty
              ? _locationController.text.trim()
              : (_spaceById(_formSpaceId)?.name ?? ''),
          spaceId: _spaceById(_formSpaceId)?.id,
          bimSource: 'manual',
          purchasePrice: double.tryParse(_purchasePriceController.text) ?? 0.0,
          purchaseDate: DateTime.now(),
          warrantyMonths: int.tryParse(_warrantyController.text) ?? 0,
          status: _status,
          notes: _notesController.text.trim(),
          attachments: _attachmentUrls,
          maintenanceHistory: [
            {
              'action': 'Equipment Created',
              'timestamp': Timestamp.now(),
              'notes': _notesController.text.trim(),
              'userId': user.uid,
            }
          ],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          createdBy: user.uid,
        );

        await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('equipment')
            .doc(equipmentId)
            .set(equipment.toMap());

        if (mounted) {
          setState(() {
            _attachmentUrls.clear();
            _showForm = false;
          });
          _clearForm();
          _showSnackBar('Equipment added successfully');
        }
      } catch (e, stackTrace) {
        _logger.e('Error adding equipment: $e', stackTrace: stackTrace);
        if (mounted) _showSnackBar('Error adding equipment: $e');
      }
    }
  }

  Future<void> _uploadAttachment() async {
    try {
      _logger.i('Picking attachment file');
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'png', 'docx'],
      );

      if (file == null) {
        if (mounted) _showSnackBar('No file selected');
        return;
      }

      if (!['pdf', 'jpg', 'png', 'docx'].contains(file.extension)) {
        if (mounted) _showSnackBar('Please select a PDF, JPG, PNG, or DOCX file');
        return;
      }

      final fileName = '${const Uuid().v4()}_${file.name}';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('equipment/${widget.facilityId}/$fileName');

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('Uploading: ${file.name}', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            content: Column(
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
              ],
            ),
          ),
        ),
      );

      UploadTask uploadTask;
      if (kIsWeb) {
        Uint8List fileBytes;
        try {
          fileBytes = await file.readAsBytes();
        } catch (e) {
          if (mounted) {
            Navigator.pop(context);
            _showSnackBar('File data unavailable');
          }
          return;
        }
        uploadTask = storageRef.putData(fileBytes);
      } else {
        if (file.path == null) {
          if (mounted) {
            Navigator.pop(context);
            _showSnackBar('File path unavailable');
          }
          return;
        }
        uploadTask = storageRef.putFile(File(file.path!));
      }

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
      final url = await storageRef.getDownloadURL();

      if (mounted) {
        setState(() {
          _attachmentUrls.add({'name': file.name, 'url': url});
        });
        Navigator.pop(context);
        _showSnackBar('Attachment uploaded successfully');
      }
      _logger.i('Uploaded attachment: ${file.name}, url: $url');
    } catch (e, stackTrace) {
      _logger.e('Error uploading attachment: $e', stackTrace: stackTrace);
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error uploading attachment: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _updateStatus(String docId, String newStatus, String notes) async {
    try {
      _logger.i('Updating status: docId=$docId, newStatus=$newStatus');
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('equipment')
          .doc(docId)
          .update({
        'status': newStatus,
        'updatedAt': Timestamp.now(),
        'maintenanceHistory': FieldValue.arrayUnion([
          {
            'action': 'Status changed to $newStatus',
            'timestamp': Timestamp.now(),
            'notes': notes,
            'userId': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          }
        ]),
      });
      if (mounted) _showSnackBar('Status updated to $newStatus');
    } catch (e, stackTrace) {
      _logger.e('Error updating status: $e', stackTrace: stackTrace);
      if (mounted) _showSnackBar('Error updating status: $e');
    }
  }

  void _clearForm() {
    _nameController.clear();
    _typeController.clear();
    _serialController.clear();
    _locationController.clear();
    _purchasePriceController.clear();
    _warrantyController.clear();
    _notesController.clear();
    _status = 'Active';
    _formSpaceId = null;
  }

  bool _isImported(Equipment e) => e.bimSource == 'cobie' || e.bimSource == 'ifc';

  Widget _tag(IconData icon, String label, MaterialColor color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color[50], borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color[700]),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                style: GoogleFonts.poppins(fontSize: 11, color: color[800], fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      );

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Equipment Supplied',
      facilityId: widget.facilityId,
      currentRole: 'User',
      organization: '-',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _showForm = !_showForm),
        backgroundColor: Colors.blueGrey[800],
        icon: Icon(_showForm ? Icons.close : Icons.add, color: Colors.white),
        label: Text(
          _showForm ? 'Cancel' : 'New Equipment',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
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
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _push(BimImportScreen(facilityId: widget.facilityId)),
                  icon: const Icon(Icons.upload_file),
                  label: Text('Import COBie / IFC', style: GoogleFonts.poppins()),
                ),
                OutlinedButton.icon(
                  onPressed: () => _push(SpacesScreen(facilityId: widget.facilityId)),
                  icon: const Icon(Icons.meeting_room_outlined),
                  label: Text('Floors & Rooms', style: GoogleFonts.poppins()),
                ),
                OutlinedButton.icon(
                  onPressed: () => _push(BimModelsScreen(facilityId: widget.facilityId)),
                  icon: const Icon(Icons.view_in_ar_outlined),
                  label: Text('BIM Models', style: GoogleFonts.poppins()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildFilterSection(padding, fontSizeSubtitle),
          const SizedBox(height: 24),
          if (_showForm) _buildForm(padding, fontSizeTitle, fontSizeSubtitle),
          const SizedBox(height: 24),
          Text(
            'Equipment List',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: fontSizeTitle,
              color: Colors.blueGrey[900],
            ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: _buildEquipmentStream(),
            builder: (context, snapshot) {
              _logger.i('StreamBuilder snapshot: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, docCount=${snapshot.data?.docs.length ?? 0}');
              if (snapshot.hasError) {
                _logger.e('Firestore error: ${snapshot.error}');
                return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins());
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              // Type, source and space are filtered here rather than in the query, so imported types
              // (e.g. a COBie type name) still match and no extra composite indexes are needed.
              const minorKeywords = [
                'conduit', 'cable', 'wire', 'wiring', 'tray', 'cable tray',
                'raceway', 'busduct', 'busbar', 'sleeve', 'junction box',
                'pull box', 'fitting', 'duct tape', 'gland',
              ];
              final docs = snapshot.data!.docs.where((d) {
                final e = Equipment.fromSnapshot(d);
                if (_typeFilter != 'All' && e.type != _typeFilter) return false;
                if (_sourceFilter == 'BIM import' && !(e.bimSource == 'cobie' || e.bimSource == 'ifc')) return false;
                if (_sourceFilter == 'Manual' && (e.bimSource == 'cobie' || e.bimSource == 'ifc')) return false;
                if (_spaceFilter != 'All') {
                  // A floor filter also includes the rooms on that floor.
                  final space = _spaceById(e.spaceId);
                  if (space == null || (space.id != _spaceFilter && space.parentId != _spaceFilter)) return false;
                }
                if (_majorOnly) {
                  final nameLower = e.name.toLowerCase();
                  final typeLower = (e.typeName ?? e.type).toLowerCase();
                  if (minorKeywords.any((kw) => nameLower.contains(kw) || typeLower.contains(kw))) return false;
                }
                return true;
              }).toList();
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.precision_manufacturing_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No equipment found',
                        style: GoogleFonts.poppins(
                          fontSize: fontSizeSubtitle,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }
              return isMobile
                  ? _buildEquipmentList(docs, isMobile, fontSizeSubtitle)
                  : _buildEquipmentList(docs, isMobile, fontSizeSubtitle);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(double padding, double fontSize) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    final filters = <Widget>[
      _buildFilterDropdown('Status', _statusFilter, ['All', 'Active', 'Inactive', 'Under Repair', 'Decommissioned'], (value) => setState(() => _statusFilter = value!), fontSize),
      _buildFilterDropdown('Type', _typeFilter, ['All', 'Electrical', 'Mechanical', 'HVAC', 'Plumbing', 'Safety', 'IT Equipment'], (value) => setState(() => _typeFilter = value!), fontSize),
      _buildFilterDropdown('Source', _sourceFilter, ['All', 'Manual', 'BIM import'], (value) => setState(() => _sourceFilter = value!), fontSize),
      if (_spaces.isNotEmpty) _buildSpaceFilter(fontSize),
    ];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.all(padding),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isMobile
                ? Column(
                    children: [
                      for (final f in filters) ...[f, const SizedBox(height: 12)],
                    ],
                  )
                : Row(
                    children: [
                      for (var i = 0; i < filters.length; i++) ...[
                        if (i > 0) const SizedBox(width: 16),
                        Expanded(flex: filters.length == 4 && i == 3 ? 2 : 1, child: filters[i]),
                      ],
                    ],
                  ),
            const SizedBox(height: 10),
            FilterChip(
              label: Text('Major components only',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      color: _majorOnly ? Colors.white : Colors.blueGrey[700])),
              avatar: Icon(
                Icons.filter_list_rounded,
                size: 16,
                color: _majorOnly ? Colors.white : Colors.blueGrey[600],
              ),
              selected: _majorOnly,
              onSelected: (v) => setState(() => _majorOnly = v),
              selectedColor: Colors.blueGrey[700],
              backgroundColor: Colors.grey[100],
              checkmarkColor: Colors.white,
              side: BorderSide(color: Colors.blueGrey[300]!),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpaceFilter(double fontSize) {
    // A stale selection (space deleted) falls back to All instead of crashing the dropdown.
    final value = _spaceFilter == 'All' || _spaceById(_spaceFilter) != null ? _spaceFilter : 'All';
    return DropdownButtonFormField<String>(
      key: ValueKey('space_filter_${_spaces.length}'),
      initialValue: value,
      isExpanded: true,
      items: [
        DropdownMenuItem(value: 'All', child: Text('All', style: GoogleFonts.poppins(fontSize: fontSize))),
        for (final s in _spaces)
          DropdownMenuItem(
            value: s.id,
            child: Text(
              s.kind == BimSpaceKind.storey ? '${s.name} (whole floor)' : _spaceLabel(s),
              style: GoogleFonts.poppins(fontSize: fontSize),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) => setState(() => _spaceFilter = v ?? 'All'),
      decoration: InputDecoration(
        labelText: 'Floor / Room',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      style: GoogleFonts.poppins(color: Colors.blueGrey[800], fontWeight: FontWeight.w500),
    );
  }

  Widget _buildFormSpacePicker(double fontSize) {
    if (_spaces.isEmpty) {
      return _buildTextField(_locationController, 'Location (optional)', fontSize);
    }
    return DropdownButtonFormField<String?>(
      initialValue: _spaceById(_formSpaceId)?.id,
      isExpanded: true,
      items: [
        DropdownMenuItem<String?>(value: null, child: Text('Not assigned', style: GoogleFonts.poppins(fontSize: fontSize))),
        for (final s in _spaces)
          DropdownMenuItem<String?>(
            value: s.id,
            child: Text(_spaceLabel(s), style: GoogleFonts.poppins(fontSize: fontSize), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() => _formSpaceId = v),
      decoration: InputDecoration(
        labelText: 'Floor / Room (optional)',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      style: GoogleFonts.poppins(color: Colors.blueGrey[800], fontWeight: FontWeight.w500),
    );
  }

  Widget _buildFilterDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged, double fontSize) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: items.map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins(fontSize: fontSize)))).toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      style: GoogleFonts.poppins(color: Colors.blueGrey[800], fontWeight: FontWeight.w500),
      dropdownColor: Colors.white,
      icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
    );
  }

  Widget _buildEquipmentList(List<QueryDocumentSnapshot> docs, bool isMobile, double fontSize) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final equipment = Equipment.fromSnapshot(docs[index]);
        return _buildEquipmentCard(equipment, isMobile, fontSize);
      },
    );
  }

  Widget _buildEquipmentCard(Equipment equipment, bool isMobile, double fontSize) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(equipment.status),
          child: Icon(
            _getStatusIcon(equipment.status),
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          equipment.name,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.blueGrey[900],
            fontSize: fontSize,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Type: ${equipment.type} | Status: ${equipment.status}',
              style: GoogleFonts.poppins(
                fontSize: fontSize - 2,
                color: Colors.grey[600],
              ),
            ),
            Text(
              'Serial: ${equipment.serialNumber.isEmpty ? 'N/A' : equipment.serialNumber}',
              style: GoogleFonts.poppins(
                fontSize: fontSize - 2,
                color: Colors.grey[600],
              ),
            ),
            if (_spaceById(equipment.spaceId) != null || _isImported(equipment))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (_spaceById(equipment.spaceId) != null)
                      _tag(Icons.meeting_room_outlined, _spaceLabel(_spaceById(equipment.spaceId)!), Colors.blueGrey),
                    if (_isImported(equipment))
                      _tag(Icons.view_in_ar_outlined, equipment.bimSource == 'cobie' ? 'COBie' : 'IFC', Colors.indigo),
                  ],
                ),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_spaceById(equipment.spaceId) != null)
                  _buildDetailRow('Floor / Room', _spaceLabel(_spaceById(equipment.spaceId)!), fontSize)
                else
                  _buildDetailRow('Location ID', equipment.locationId.isEmpty ? 'N/A' : equipment.locationId, fontSize),
                if (equipment.typeName != null && equipment.typeName != equipment.type) _buildDetailRow('Product type', equipment.typeName!, fontSize),
                if (equipment.manufacturer != null) _buildDetailRow('Manufacturer', equipment.manufacturer!, fontSize),
                if (equipment.modelNumber != null) _buildDetailRow('Model', equipment.modelNumber!, fontSize),
                if (equipment.systemName != null) _buildDetailRow('System', equipment.systemName!, fontSize),
                if (equipment.classification != null) _buildDetailRow('Classification', equipment.classification!, fontSize),
                if (_isImported(equipment)) _buildDetailRow('BIM source', equipment.bimSource == 'cobie' ? 'COBie import' : 'IFC import', fontSize),
                if (equipment.isBimLinked) _buildDetailRow('IFC GlobalId', equipment.bimGlobalId!, fontSize),
                _buildDetailRow('Purchase Price', '\$${equipment.purchasePrice.toStringAsFixed(2)}', fontSize),
                _buildDetailRow('Warranty', '${equipment.warrantyMonths} months', fontSize),
                _buildDetailRow('Created', equipment.createdAt != null ? DateFormat.yMMMd().format(equipment.createdAt!) : 'Unknown date', fontSize),
                if (equipment.notes.isNotEmpty) _buildDetailRow('Notes', equipment.notes, fontSize),
                if (equipment.attachments.isNotEmpty) _buildAttachmentsSection(equipment.attachments, fontSize),
                if (equipment.maintenanceHistory.isNotEmpty) _buildHistorySection(equipment.maintenanceHistory, fontSize),
                EquipmentActivitySection(facilityId: widget.facilityId, equipmentId: equipment.id, fontSize: fontSize),
                const SizedBox(height: 12),
                _buildActionButtons(equipment),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, double fontSize) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                color: Colors.blueGrey[700],
                fontSize: fontSize - 2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                color: Colors.grey[800],
                fontSize: fontSize - 2,
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
              color: Colors.blueGrey[700],
              fontSize: fontSize - 2,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: attachments
                .map((attachment) => Chip(
                      label: Text(
                        attachment['name'] ?? 'Unknown',
                        style: GoogleFonts.poppins(fontSize: fontSize - 4),
                      ),
                      backgroundColor: Colors.blue[50],
                    ))
                .toList(),
          ),
        ],
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
            'Maintenance History:',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey[700],
              fontSize: fontSize - 2,
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
                      entry['action'] ?? '',
                      style: GoogleFonts.poppins(fontSize: fontSize - 2, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'at ${entry['timestamp'] != null ? DateFormat.yMMMd().format((entry['timestamp'] as Timestamp).toDate()) : 'Unknown date'}',
                      style: GoogleFonts.poppins(
                        fontSize: fontSize - 4,
                        color: Colors.grey[600],
                      ),
                    ),
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

  Widget _buildActionButtons(Equipment equipment) {
    final ref = EquipmentRef.fromEquipment(equipment);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      runSpacing: 4,
      children: [
        if (equipment.isBimLinked)
          TextButton.icon(
            onPressed: () => _push(BimViewerScreen(facilityId: widget.facilityId, focusGlobalId: equipment.bimGlobalId)),
            icon: const Icon(Icons.threed_rotation_rounded, size: 16, color: Colors.indigo),
            label: Text('Show in 3D', style: GoogleFonts.poppins(color: Colors.indigo)),
          ),
        TextButton.icon(
          onPressed: () => _push(WorkOrderScreen(facilityId: widget.facilityId, initialEquipment: ref)),
          icon: const Icon(Icons.build_outlined, size: 16, color: Colors.blueGrey),
          label: Text('New Work Order', style: GoogleFonts.poppins(color: Colors.blueGrey)),
        ),
        TextButton.icon(
          onPressed: () => _push(RequestScreen(facilityId: widget.facilityId, initialEquipment: ref)),
          icon: const Icon(Icons.report_problem_outlined, size: 16, color: Colors.blueGrey),
          label: Text('Report Problem', style: GoogleFonts.poppins(color: Colors.blueGrey)),
        ),
        TextButton.icon(
          onPressed: () => _showUpdateStatusDialog(equipment),
          icon: const Icon(Icons.edit, size: 16, color: Colors.blueGrey),
          label: Text('Update Status', style: GoogleFonts.poppins(color: Colors.blueGrey)),
          style: TextButton.styleFrom(foregroundColor: Colors.blueGrey[700]),
        ),
      ],
    );
  }

  Widget _buildForm(double padding, double fontSizeTitle, double fontSizeSubtitle) {
    final isMobile = MediaQuery.of(context).size.width <= 600;
    final isTablet = MediaQuery.of(context).size.width > 600 && MediaQuery.of(context).size.width <= 900;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.all(padding),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add New Equipment',
                    style: GoogleFonts.poppins(
                      fontSize: fontSizeTitle,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[900],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.blueGrey),
                    onPressed: () => setState(() => _showForm = false),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              isMobile
                  ? Column(
                      children: [
                        _buildTextField(_nameController, 'Equipment Name', fontSizeSubtitle, validator: (value) => value!.isEmpty ? 'Enter equipment name' : null),
                        const SizedBox(height: 16),
                        _buildTypeDropdown(fontSizeSubtitle),
                        const SizedBox(height: 16),
                        _buildTextField(_serialController, 'Serial Number (optional)', fontSizeSubtitle),
                        const SizedBox(height: 16),
                        _buildFormSpacePicker(fontSizeSubtitle),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              _buildTextField(_nameController, 'Equipment Name', fontSizeSubtitle, validator: (value) => value!.isEmpty ? 'Enter equipment name' : null),
                              const SizedBox(height: 16),
                              _buildTextField(_serialController, 'Serial Number (optional)', fontSizeSubtitle),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            children: [
                              _buildTypeDropdown(fontSizeSubtitle),
                              const SizedBox(height: 16),
                              _buildFormSpacePicker(fontSizeSubtitle),
                            ],
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
              isMobile || isTablet
                  ? Column(
                      children: [
                        _buildTextField(_purchasePriceController, 'Purchase Price (optional)', fontSizeSubtitle, keyboardType: TextInputType.number, prefixText: '\$ '),
                        const SizedBox(height: 16),
                        _buildTextField(_warrantyController, 'Warranty Months (optional)', fontSizeSubtitle, keyboardType: TextInputType.number),
                        const SizedBox(height: 16),
                        _buildStatusDropdown(fontSizeSubtitle),
                        const SizedBox(height: 16),
                        _buildTextField(_notesController, 'Notes (optional)', fontSizeSubtitle, maxLines: 2),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              _buildTextField(_purchasePriceController, 'Purchase Price (optional)', fontSizeSubtitle, keyboardType: TextInputType.number, prefixText: '\$ '),
                              const SizedBox(height: 16),
                              _buildTextField(_notesController, 'Notes (optional)', fontSizeSubtitle, maxLines: 2),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            children: [
                              _buildTextField(_warrantyController, 'Warranty Months (optional)', fontSizeSubtitle, keyboardType: TextInputType.number),
                              const SizedBox(height: 16),
                              _buildStatusDropdown(fontSizeSubtitle),
                            ],
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _uploadAttachment,
                      icon: const Icon(Icons.attach_file, color: Colors.white),
                      label: Text('Add Attachment', style: GoogleFonts.poppins(color: Colors.white, fontSize: fontSizeSubtitle)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[600],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              if (_attachmentUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: _attachmentUrls
                      .asMap()
                      .entries
                      .map((entry) => Chip(
                            label: Text(
                              entry.value['name'] ?? 'Unknown',
                              style: GoogleFonts.poppins(fontSize: fontSizeSubtitle - 4),
                            ),
                            backgroundColor: Colors.blue[50],
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              setState(() {
                                _attachmentUrls.removeAt(entry.key);
                              });
                            },
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _addEquipment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey[800],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    'Add Equipment',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: fontSizeSubtitle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    double fontSize, {
    TextInputType? keyboardType,
    String? prefixText,
    int? maxLines,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
        prefixText: prefixText,
      ),
      style: GoogleFonts.poppins(fontSize: fontSize),
      keyboardType: keyboardType,
      maxLines: maxLines ?? 1,
      validator: validator,
    );
  }

  Widget _buildTypeDropdown(double fontSize) {
    return DropdownButtonFormField<String>(
      initialValue: _typeController.text.isEmpty ? 'Electrical' : _typeController.text,
      items: ['Electrical', 'Mechanical', 'HVAC', 'Plumbing', 'Safety', 'IT Equipment']
          .map((type) => DropdownMenuItem(value: type, child: Text(type, style: GoogleFonts.poppins(fontSize: fontSize))))
          .toList(),
      onChanged: (value) {
        setState(() {
          _typeController.text = value!;
        });
      },
      decoration: InputDecoration(
        labelText: 'Equipment Type',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      style: GoogleFonts.poppins(color: Colors.blueGrey[800], fontWeight: FontWeight.w500),
      dropdownColor: Colors.white,
      icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
    );
  }

  Widget _buildStatusDropdown(double fontSize) {
    return DropdownButtonFormField<String>(
      initialValue: _status,
      items: ['Active', 'Inactive', 'Under Repair', 'Decommissioned']
          .map((status) => DropdownMenuItem(value: status, child: Text(status, style: GoogleFonts.poppins(fontSize: fontSize))))
          .toList(),
      onChanged: (value) {
        setState(() {
          _status = value!;
        });
      },
      decoration: InputDecoration(
        labelText: 'Status',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      style: GoogleFonts.poppins(color: Colors.blueGrey[800], fontWeight: FontWeight.w500),
      dropdownColor: Colors.white,
      icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
    );
  }

  void _showUpdateStatusDialog(Equipment equipment) {
    final notesController = TextEditingController();
    String selectedStatus = equipment.status;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Equipment Status', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedStatus,
              items: ['Active', 'Inactive', 'Under Repair', 'Decommissioned']
                  .map((status) => DropdownMenuItem(value: status, child: Text(status, style: GoogleFonts.poppins())))
                  .toList(),
              onChanged: (value) => selectedStatus = value!,
              decoration: InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[100],
                labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(color: Colors.blueGrey[800], fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[100],
                labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
              ),
              style: GoogleFonts.poppins(),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () {
              _updateStatus(equipment.id, selectedStatus, notesController.text);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[800],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Update', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Stream<QuerySnapshot> _buildEquipmentStream() {
    Query query = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('equipment');

    if (_statusFilter != 'All') {
      query = query.where('status', isEqualTo: _statusFilter);
    }

    return query.orderBy('createdAt', descending: true).snapshots();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green.shade600;
      case 'inactive':
        return Colors.grey.shade600;
      case 'under repair':
        return Colors.orange.shade600;
      case 'decommissioned':
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
      case 'under repair':
        return Icons.build_circle;
      case 'decommissioned':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }
}