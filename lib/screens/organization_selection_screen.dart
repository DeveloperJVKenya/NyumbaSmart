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
import 'package:cmms/widgets/brand/brand_kit.dart';

const List<BrandStep> _kEntrySteps = [
  BrandStep('Organization', Icons.business_rounded),
  BrandStep('Facility', Icons.location_city_rounded),
  BrandStep('Dashboard', Icons.dashboard_rounded),
];

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
  final TextEditingController _searchController = TextEditingController();
  bool _isAddingOrganization = false;
  bool _isSaving = false;
  String _searchQuery = '';

  // Built once so a parent rebuild doesn't tear down and re-attach the listener.
  late final Stream<QuerySnapshot> _organizationsStream = FirebaseFirestore.instance
      .collection('Organizations')
      .where('isActive', isEqualTo: true)
      .snapshots();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Organization creation is available to Admins on the JV Almacis
  /// (contractor/service-provider) side — same access rule as facility location edits.
  bool _canAddOrganization(UserRoleInfo? roleInfo) {
    if (roleInfo == null) return false;
    return roleInfo.role == UserRole.admin && roleInfo.isServiceProviderOrg;
  }

  Future<void> _addOrganization() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final name = _nameController.text.trim();
      final existing = await FirebaseFirestore.instance
          .collection('Organizations')
          .where('name', isEqualTo: name)
          .get();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleInfo = ref.watch(currentUserRoleProvider).value;
    final canAdd = _canAddOrganization(roleInfo);

    return Scaffold(
      backgroundColor: BrandColors.ink,
      body: BrandBackdrop(
        child: SafeArea(
          child: _isAddingOrganization ? _buildAddOrganizationForm() : _buildSelectionView(),
        ),
      ),
      floatingActionButton: canAdd && !_isAddingOrganization
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _isAddingOrganization = true),
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.textPrimary,
              icon: const Icon(Icons.add_rounded),
              label: Text('Add Organization', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
            )
          : null,
    );
  }

  Widget _buildSelectionView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: BrandStepper(steps: _kEntrySteps, current: 0, compact: true),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandEyebrow(label: 'Facility Management · CMMS', icon: Icons.corporate_fare_rounded),
              const SizedBox(height: 12),
              Text('Select Organization', style: BrandFonts.display(fontSize: 30)),
              const SizedBox(height: 10),
              const BrandAccentBar(width: 72),
              const SizedBox(height: 8),
              Text(
                'Choose a client organization to manage its facilities',
                style: BrandFonts.body(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.72)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: BrandSearchField(
            controller: _searchController,
            hint: 'Search organizations…',
            onChanged: (q) => setState(() => _searchQuery = q.toLowerCase()),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _organizationsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: AppSkeletonList(count: 5, itemHeight: 76),
                );
              }

              if (snapshot.hasError) {
                logger.e('Firestore error: ${snapshot.error}');
                return Center(
                  child: Text('Error: ${snapshot.error}', style: BrandFonts.body(color: AppColors.error)),
                );
              }

              final docs = snapshot.data?.docs ?? [];
              final allOrgs = docs
                  .map((doc) => Organization.fromFirestore(doc))
                  .where((org) => org.name != 'JV Almacis')
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));

              final filtered = _searchQuery.isEmpty
                  ? allOrgs
                  : allOrgs
                      .where((o) =>
                          o.name.toLowerCase().contains(_searchQuery) ||
                          (o.description?.toLowerCase().contains(_searchQuery) ?? false))
                      .toList();

              if (allOrgs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.business_rounded, size: 64, color: Colors.white.withValues(alpha: 0.25)),
                      const SizedBox(height: 16),
                      Text('No client organizations available', style: BrandFonts.display(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                        'Contact your administrator to add client organizations',
                        style: BrandFonts.body(color: Colors.white.withValues(alpha: 0.65)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    'No organizations match "$_searchQuery"',
                    style: BrandFonts.body(color: Colors.white.withValues(alpha: 0.65)),
                  ),
                );
              }

              logger.i('Fetched ${allOrgs.length} client organizations for app launch selection (excluding JV Almacis)');

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final org = filtered[index];
                  return FadeSlideIn(
                    delay: Duration(milliseconds: 55 * index),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: HoverLift(
                        builder: (ctx, hovered) => _GlassOrgCard(
                          organization: org,
                          hovered: hovered,
                          onTap: () {
                            widget.onOrganizationSelected(org.id, org.name);
                            logger.i('Selected client organization: ${org.name}, ID: ${org.id}');
                          },
                        ),
                      ),
                    ),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _isAddingOrganization = false),
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
                const SizedBox(width: 4),
                Text('New Organization', style: BrandFonts.display(fontSize: 22)),
              ],
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.only(left: 48),
              child: BrandAccentBar(width: 60),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Column(
                children: [
                  _GlassFormField(
                    controller: _nameController,
                    label: 'Organization Name',
                    icon: Icons.business_rounded,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter an organization name' : null,
                  ),
                  const SizedBox(height: 16),
                  _GlassFormField(
                    controller: _descriptionController,
                    label: 'Description (optional)',
                    icon: Icons.notes_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                BrandCta(
                  label: 'Cancel',
                  primary: false,
                  onPressed: () => setState(() => _isAddingOrganization = false),
                ),
                const SizedBox(width: 12),
                BrandCta(
                  label: 'Add Organization',
                  icon: Icons.add_rounded,
                  loading: _isSaving,
                  onPressed: _isSaving ? null : _addOrganization,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassOrgCard extends StatelessWidget {
  final Organization organization;
  final bool hovered;
  final VoidCallback onTap;

  const _GlassOrgCard({required this.organization, required this.hovered, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: hovered ? 0.14 : 0.07),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: hovered
                  ? AppColors.accentLight.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              BrandMonogram(name: organization.name, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      organization.name,
                      style: BrandFonts.body(fontSize: 15.5, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2),
                    ),
                    if (organization.description != null && organization.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        organization.description!,
                        style: BrandFonts.body(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.65)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: hovered ? AppColors.accentLight : Colors.white.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;

  const _GlassFormField({required this.controller, required this.label, required this.icon, this.validator});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      style: BrandFonts.body(color: Colors.white),
      cursorColor: AppColors.accentLight,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: BrandFonts.body(fontSize: 13, color: Colors.white.withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: AppColors.accentLight, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.accentLight, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
    );
  }
}
