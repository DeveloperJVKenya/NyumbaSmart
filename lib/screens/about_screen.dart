import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('About NyumbaSmart',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        child: Column(
          children: [
            // App hero banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.22),
                      blurRadius: 20,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: const Icon(Icons.business_center_rounded, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text('NyumbaSmart',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 26, fontWeight: FontWeight.w800,
                          color: Colors.white, letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  Text('Facility Management CMMS',
                      style: GoogleFonts.poppins(
                          fontSize: 13.5, color: Colors.white.withValues(alpha: 0.8))),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: Text('Version 2.0.0 · Build 2026',
                        style: GoogleFonts.poppins(
                            fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _card(
              icon: Icons.info_outline_rounded,
              color: AppColors.primary,
              title: 'About the App',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                child: Text(
                  'NyumbaSmart is an enterprise-grade CMMS built for multi-tenant facility management. '
                  'It enables organizations to digitize work orders, track assets, run preventive '
                  'maintenance programs, manage billing, and visualize facilities in 3D through BIM integration. '
                  'Developed by JV Almacis Consultancy & Integrated Services.',
                  style: GoogleFonts.poppins(
                      fontSize: 13.5, color: AppColors.textSecondary, height: 1.65),
                ),
              ),
            ),
            const SizedBox(height: 16),

            _card(
              icon: Icons.star_rounded,
              color: const Color(0xFFFF922B),
              title: 'Key Features',
              child: Column(
                children: const [
                  _FeatureTile(
                    icon: Icons.assignment_rounded, color: Color(0xFF4C6EF5),
                    title: 'Work Orders', subtitle: 'Create, assign and track corrective maintenance tasks'),
                  _FeatureTile(
                    icon: Icons.event_repeat_rounded, color: Color(0xFF12B886),
                    title: 'Preventive Maintenance', subtitle: 'Schedule recurring tasks with auto-reminders', last: false),
                  _FeatureTile(
                    icon: Icons.inventory_2_rounded, color: Color(0xFFFF922B),
                    title: 'Asset Management', subtitle: 'Full asset lifecycle with QR scan and history'),
                  _FeatureTile(
                    icon: Icons.view_in_ar_rounded, color: Color(0xFF9775FA),
                    title: 'BIM & 3D Viewer', subtitle: 'Interactive model viewer for spatial facility data'),
                  _FeatureTile(
                    icon: Icons.bar_chart_rounded, color: Color(0xFF339AF0),
                    title: 'Reports & KPIs', subtitle: 'Real-time dashboards and exportable reports'),
                  _FeatureTile(
                    icon: Icons.notifications_active_rounded, color: Color(0xFFFF6B6B),
                    title: 'Smart Notifications', subtitle: 'Push and in-app alerts for assignments and deadlines', last: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _card(
              icon: Icons.code_rounded,
              color: const Color(0xFF748FFC),
              title: 'Technical Stack',
              child: Column(
                children: [
                  _techRow('Platform', 'Flutter (Web · Android · iOS)'),
                  _techDiv(),
                  _techRow('Backend', 'Firebase Cloud Services'),
                  _techDiv(),
                  _techRow('Database', 'Cloud Firestore'),
                  _techDiv(),
                  _techRow('Auth', 'Firebase Authentication'),
                  _techDiv(),
                  _techRow('State', 'Flutter Riverpod'),
                  _techDiv(),
                  _techRow('Fonts', 'Plus Jakarta Sans · Poppins'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _card(
              icon: Icons.business_rounded,
              color: const Color(0xFF12B886),
              title: 'Developer',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _devRow(Icons.apartment_rounded, 'JV Almacis Consultancy & Integrated Services'),
                    const SizedBox(height: 10),
                    _devRow(Icons.location_on_rounded, 'Nairobi, Kenya'),
                    const SizedBox(height: 10),
                    _devRow(Icons.email_rounded, 'info@jvalmacis.co.ke'),
                    const SizedBox(height: 16),
                    Text('© 2026 JV Almacis. All rights reserved.',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required Color color,
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: color, size: 17),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          child,
        ],
      ),
    );
  }

  static Widget _techRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  static Widget _techDiv() =>
      const Divider(height: 1, indent: 16, endIndent: 0, color: Color(0xFFF3F4F6));

  static Widget _devRow(IconData icon, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 13.5, color: AppColors.textPrimary, height: 1.5)),
        ),
      ],
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool last;

  const _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.poppins(
                            fontSize: 13.5, fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!last)
          const Divider(height: 1, indent: 65, endIndent: 0, color: Color(0xFFF3F4F6)),
      ],
    );
  }
}
