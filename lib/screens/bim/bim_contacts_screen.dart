import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cmms/models/bim_model.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/screens/bim/bim_widgets.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

/// Browse manufacturer, contractor and other contacts imported from COBie Contact sheet
/// (facilities/{fId}/bimContacts), grouped by category.
class BimContactsScreen extends ConsumerStatefulWidget {
  final String facilityId;

  const BimContactsScreen({super.key, required this.facilityId});

  @override
  ConsumerState<BimContactsScreen> createState() => _BimContactsScreenState();
}

class _BimContactsScreenState extends ConsumerState<BimContactsScreen> {
  final Logger _logger = Logger();
  String _filter = '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _contactsStream = FirebaseFirestore.instance
      .collection('facilities')
      .doc(widget.facilityId)
      .collection('bimContacts')
      .orderBy('name')
      .snapshots();

  @override
  Widget build(BuildContext context) {
    final roleInfo = ref.watch(currentUserRoleProvider).value;
    return ResponsiveScreenWrapper(
      title: 'BIM Contacts',
      facilityId: widget.facilityId,
      currentRole: roleInfo?.roleLabel ?? '-',
      organization: roleInfo?.organization ?? '-',
      child: BimPage(
        children: [
          _buildSearch(),
          const SizedBox(height: AppSpacing.sm),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _contactsStream,
            builder: (context, snap) {
              if (snap.hasError) {
                _logger.e('bimContacts load failed', error: snap.error);
                return AppErrorBanner(message: 'Could not load contacts: ${snap.error}');
              }
              if (!snap.hasData) return const AppSkeletonList(count: 4);
              final all = snap.data!.docs.map(BimContact.fromSnapshot).toList();
              if (all.isEmpty) return _buildEmpty();
              final filtered = _filter.isEmpty
                  ? all
                  : all
                      .where((c) =>
                          c.name.toLowerCase().contains(_filter) ||
                          (c.company?.toLowerCase().contains(_filter) ?? false) ||
                          (c.email?.toLowerCase().contains(_filter) ?? false) ||
                          (c.category?.toLowerCase().contains(_filter) ?? false))
                      .toList();
              if (filtered.isEmpty) {
                return Center(
                    child: Text('No contacts match "$_filter"',
                        style: GoogleFonts.poppins(color: AppColors.textSecondary)));
              }

              // Group by category.
              final grouped = <String, List<BimContact>>{};
              for (final c in filtered) {
                final key = c.category ?? 'Other';
                grouped.putIfAbsent(key, () => []).add(c);
              }
              final categories = grouped.keys.toList()..sort();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${filtered.length} contact${filtered.length == 1 ? '' : 's'}',
                      style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.sm),
                  for (final cat in categories) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 6),
                      child: Row(children: [
                        const Icon(Icons.label_outline_rounded, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(cat,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                      ]),
                    ),
                    for (final c in grouped[cat]!) _buildContactCard(c),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search contacts…',
        prefixIcon: const Icon(Icons.search_rounded),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: AppColors.surfaceAlt,
      ),
      style: GoogleFonts.poppins(fontSize: 14),
      onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
    );
  }

  Widget _buildEmpty() {
    return AppCard(
      child: Column(children: [
        const Icon(Icons.contacts_outlined, size: 48, color: AppColors.primaryLight),
        const SizedBox(height: 12),
        Text('No contacts found',
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(
          'Contacts are imported from the COBie Contact sheet (manufacturers, installers, contractors).',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
        ),
      ]),
    );
  }

  Widget _buildContactCard(BimContact c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AppColors.surfaceAlt,
              child: Text(
                c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  if (c.company != null)
                    Text(c.company!,
                        style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                  if (c.description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(c.description!,
                          style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    if (c.email != null)
                      _contactChip(Icons.email_outlined, c.email!, () => _launchEmail(c.email!)),
                    if (c.phone != null)
                      _contactChip(Icons.phone_outlined, c.phone!, () => _launchPhone(c.phone!)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactChip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.primary,
                  decoration: TextDecoration.underline)),
        ]),
      ),
    );
  }

  void _launchEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
