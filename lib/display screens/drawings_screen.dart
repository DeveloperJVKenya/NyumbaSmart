import 'package:flutter/material.dart';
import 'package:cmms/models/drawings.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/widgets/building_info_document_list.dart';

class DrawingsScreen extends StatelessWidget {
  final String facilityId;

  const DrawingsScreen({super.key, required this.facilityId});

  static const Map<String, String> drawingCategories = {
    'Architectural': 'Architectural Drawings',
    'Structural': 'Structural Drawings',
    'Electrical': 'Electrical Drawings',
    'Mechanical': 'Mechanical Drawings',
    'Plumbing': 'Plumbing Drawings',
    'HVAC': 'HVAC Drawings',
    'Fire Safety': 'Fire Safety Drawings',
    'Site Plan': 'Site Plan',
  };

  static IconData _fileIcon(String fileName) {
    switch (fileName.toLowerCase().split('.').last) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'dwg':
      case 'dxf':
        return Icons.architecture_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  static Color _fileIconColor(String fileName) {
    switch (fileName.toLowerCase().split('.').last) {
      case 'pdf':
        return AppColors.error;
      case 'dwg':
      case 'dxf':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BuildingInfoScreen(
      facilityId: facilityId,
      title: 'Drawings',
      listHeading: 'Uploaded Drawings',
      emptyMessage: 'No drawings uploaded yet',
      collectionName: 'Drawings',
      storagePathSegment: 'drawings',
      categories: drawingCategories,
      defaultCategory: 'Architectural',
      allowedExtensions: const ['pdf', 'dwg', 'dxf'],
      fileIcon: _fileIcon,
      fileIconColor: _fileIconColor,
      fromSnapshot: (doc) {
        final drawing = Drawing.fromSnapshot(doc);
        return BuildingInfoDocument(
          id: drawing.id,
          title: drawing.title,
          fileName: drawing.fileName,
          downloadUrl: drawing.downloadUrl,
          uploadedAt: drawing.uploadedAt,
          category: drawing.category,
        );
      },
    );
  }
}
