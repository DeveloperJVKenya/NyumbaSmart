import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/organization.dart';
import 'package:cmms/models/user_model.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

class OrganizationSelectionScreen extends ConsumerStatefulWidget {
  final Function(String organizationId, String organizationName) onOrganizationSelected;

  const OrganizationSelectionScreen({
    super.key,
    required this.onOrganizationSelected,
  });

  @override
  OrganizationSelectionScreenState createState() => OrganizationSelectionScreenState();
}

class OrganizationSelectionScreenState extends ConsumerState<OrganizationSelectionScreen> {
  final Logger logger = Logger(printer: PrettyPrinter());
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isAddingOrganization = false;
  bool _isSaving = false;

  // Built once and reused so a parent rebuild doesn't tear down and
  // re-attach the Firestore listener (StreamBuilder tears down its
  // subscription whenever it's handed a *new* Stream instance).
  late final Stream<QuerySnapshot> _organizationsStream = FirebaseFirestore.instance
      .collection('Organizations')
      .where('isActive', isEqualTo: true)
      .snapshots();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Organization creation is available to Admins on the JV Almacis
  /// (contractor/service-provider) side — the same access rule used for
  /// editing a facility's location — since they're the ones onboarding new
  /// client organizations. Editing/deactivating stays in the Developer
  /// backend tool for now.
  bool _canAddOrganization(UserRoleInfo? roleInfo) {
    if (roleInfo == null) return false;
    return roleInfo.role == UserRole.admin && roleInfo.isServiceProviderOrg;
  }

  Future<void> _addOrganization() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final name = _nameController.text.trim();
      final existing = await FirebaseFirestore.instance.collection('Organizations').where('name', isEqualTo: name).get();
      if (existing.docs.isNotEmpty) {
        _showSnackBar('An organization with this name already exists');
        return;
      }

      final organization = Organization(
        id: '',
        name: name,
        description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
        isActive: true,
        createdAt: DateTime.now(),
        createdBy: FirebaseAuth.instance.currentUser?.uid,
      );
      await FirebaseFirestore.instance.collection('Organizations').add(organization.toFirestore());

      _nameController.clear();
      _descriptionController.clear();
      setState(() => _isAddingOrganization = false);
      _showSnackBar('Organization added successfully');
    } catch (e) {
      logger.e('Error adding organization: $e');
      _showSnackBar('Error adding organization: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.poppins())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = AppBreakpoints.isMobile(screenWidth);
    final isDesktop = AppBreakpoints.isDesktop(screenWidth);
    final contentWidth = isDesktop ? screenWidth * 0.7 : screenWidth;
    final roleInfo = ref.watch(currentUserRoleProvider).value;
    final canAdd = _canAddOrganization(roleInfo);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Center(
            child: SizedBox(
              width: contentWidth,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: _isAddingOrganization ? _buildAddOrganizationForm() : _buildSelectionView(isMobile),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: canAdd && !_isAddingOrganization
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _isAddingOrganization = true),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text('Add Organization', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
            )
          : null,
    );
  }

  Widget _buildSelectionView(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Client Organization',
          style: GoogleFonts.poppins(fontSize: isMobile ? 20 : 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Choose a client organization to manage its facilities',
          style: GoogleFonts.poppins(fontSize: isMobile ? 13 : 15, color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _organizationsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppSkeletonList(count: 5, itemHeight: 108);
              }

              if (snapshot.hasError) {
                logger.e('Firestore error: ${snapshot.error}');
                return Center(
                  child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins(color: AppColors.error)),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              // Excludes JV Almacis (the internal service-provider
              // org) from this app-launch selection only.
              final clientOrganizations = docs
                  .map((doc) => Organization.fromFirestore(doc))
                  .where((org) => org.name != 'JV Almacis')
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));

              if (clientOrganizations.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.business_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text(
                        'No client organizations available',
                        style: GoogleFonts.poppins(fontSize: isMobile ? 16 : 18, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Contact your administrator to add client organizations',
                        style: GoogleFonts.poppins(fontSize: isMobile ? 13 : 15, color: AppColors.textSecondary.withValues(alpha: 0.8)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              logger.i('Fetched ${clientOrganizations.length} client organizations for app launch selection (excluding JV Almacis)');

              return GridView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 420,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  mainAxisExtent: 118,
                ),
                itemCount: clientOrganizations.length,
                itemBuilder: (context, index) {
                  final organization = clientOrganizations[index];
                  return _OrganizationCard(
                    organization: organization,
                    isMobile: isMobile,
                    onTap: () {
                      widget.onOrganizationSelected(organization.id, organization.name);
                      logger.i('Selected client organization: ${organization.name}, ID: ${organization.id}');
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddOrganizationForm() {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _isAddingOrganization = false),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.textPrimary,
                ),
                Text(
                  'Add New Organization',
                  style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _nameController,
              label: 'Organization Name *',
              icon: Icons.business_rounded,
              validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter an organization name' : null,
            ),
            const SizedBox(height: 16),
            AppTextField(controller: _descriptionController, label: 'Description (optional)', icon: Icons.notes_rounded),
            const SizedBox(height: 32),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 16,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _isAddingOrganization = false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.textSecondary.withValues(alpha: 0.35)),
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                  child: const Text('Cancel'),
                ),
                AppGradientButton(label: 'Add Organization', isLoading: _isSaving, onPressed: _isSaving ? null : _addOrganization),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrganizationCard extends StatelessWidget {
  final Organization organization;
  final bool isMobile;
  final VoidCallback onTap;

  const _OrganizationCard({required this.organization, required this.isMobile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Icon(Icons.business_rounded, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      organization.name,
                      style: GoogleFonts.poppins(fontSize: isMobile ? 15 : 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text('Client', style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.success)),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textSecondary, size: 14),
                ],
              ),
              if (organization.description != null && organization.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  organization.description!,
                  style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
