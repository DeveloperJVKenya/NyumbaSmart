import 'package:flutter/material.dart';
import 'package:cmms/models/building_survey.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/widgets/building_info_document_list.dart';

class BuildingSurveyScreen extends StatelessWidget {
  final String facilityId;
  final String selectedSubSection;

  const BuildingSurveyScreen({
    super.key,
    required this.facilityId,
    required this.selectedSubSection,
  });

  static const Map<String, String> surveyCategories = {
    'General Survey': 'General Building Survey',
    'Structural': 'Structural Assessment',
    'MEP Systems': 'MEP Systems Survey',
    'Safety': 'Safety Assessment',
    'Compliance': 'Compliance Survey',
    'Environmental': 'Environmental Assessment',
  };

  @override
  Widget build(BuildContext context) {
    return BuildingInfoScreen(
      facilityId: facilityId,
      title: 'Building Survey',
      listHeading: 'Uploaded Surveys',
      emptyMessage: 'No surveys uploaded yet',
      collectionName: 'BuildingSurveys',
      storagePathSegment: 'building_surveys',
      categories: surveyCategories,
      defaultCategory: 'General Survey',
      allowedExtensions: const ['pdf'],
      fileIcon: (_) => Icons.picture_as_pdf_rounded,
      fileIconColor: (_) => AppColors.error,
      fromSnapshot: (doc) {
        final survey = BuildingSurvey.fromSnapshot(doc);
        return BuildingInfoDocument(
          id: survey.id,
          title: survey.title,
          fileName: survey.fileName,
          downloadUrl: survey.downloadUrl,
          uploadedAt: survey.uploadedAt,
          category: survey.category,
        );
      },
    );
  }
}
