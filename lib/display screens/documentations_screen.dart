import 'package:flutter/material.dart';
import 'package:cmms/models/documentations.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/widgets/building_info_document_list.dart';

class DocumentationsScreen extends StatelessWidget {
  final String facilityId;

  const DocumentationsScreen({super.key, required this.facilityId});

  static const Map<String, String> documentCategories = {
    'Building Information': 'Building Information',
    'Floor Plans': 'Floor Plans',
    'MEP Layouts': 'MEP Layouts',
    'Fire Safety': 'Fire Safety',
    'Compliance': 'Compliance',
    'Maintenance': 'Maintenance',
    'Waste Management': 'Waste Management',
    'Contractors': 'Contractors',
    'Land Rates': 'Land Rates',
  };

  static IconData _fileIcon(String fileName) {
    switch (fileName.toLowerCase().split('.').last) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  static Color _fileIconColor(String fileName) {
    switch (fileName.toLowerCase().split('.').last) {
      case 'pdf':
        return AppColors.error;
      case 'doc':
      case 'docx':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BuildingInfoScreen(
      facilityId: facilityId,
      title: 'Documentations',
      listHeading: 'Uploaded Documents',
      emptyMessage: 'No documents uploaded yet',
      collectionName: 'Documentations',
      storagePathSegment: 'documentations',
      categories: documentCategories,
      defaultCategory: 'Building Information',
      allowedExtensions: const ['pdf', 'doc', 'docx', 'txt'],
      fileIcon: _fileIcon,
      fileIconColor: _fileIconColor,
      fromSnapshot: (doc) {
        final documentation = Documentation.fromSnapshot(doc);
        return BuildingInfoDocument(
          id: documentation.id,
          title: documentation.title,
          fileName: documentation.fileName,
          downloadUrl: documentation.downloadUrl,
          uploadedAt: documentation.uploadedAt,
          category: documentation.category,
        );
      },
    );
  }
}
