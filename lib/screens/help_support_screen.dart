import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/theme/app_theme.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

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
        title: Text('Help & Support',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Contact cards row
            Row(
              children: [
                Expanded(child: _contactCard(
                  icon: Icons.email_rounded,
                  color: AppColors.primary,
                  label: 'Email Support',
                  value: 'support@nyumbasmart.co.ke',
                )),
                const SizedBox(width: 12),
                Expanded(child: _contactCard(
                  icon: Icons.phone_rounded,
                  color: const Color(0xFF12B886),
                  label: 'WhatsApp',
                  value: '+254 700 000 000',
                )),
              ],
            ),
            const SizedBox(height: 20),

            _sectionCard(
              icon: Icons.help_outline_rounded,
              color: const Color(0xFF4C6EF5),
              title: 'Frequently Asked Questions',
              child: Column(
                children: const [
                  _FaqTile(
                    q: 'How do I create a work order?',
                    a: 'Go to Work Orders from the sidebar, then tap the + button. Fill in the details and assign to a technician.',
                  ),
                  _FaqTile(
                    q: 'How do I set up preventive maintenance?',
                    a: 'Navigate to Preventive Maintenance, tap + New Schedule, and configure the asset, frequency and responsible team.',
                  ),
                  _FaqTile(
                    q: 'How do I add a new asset?',
                    a: 'From Assets & BIM, tap + Add Asset. You can scan a QR code or enter asset details manually.',
                  ),
                  _FaqTile(
                    q: 'Why can I not see all menu items?',
                    a: 'Module visibility is based on your role. Contact your organization administrator to request additional access.',
                  ),
                  _FaqTile(
                    q: 'How do I view BIM / 3D models?',
                    a: 'Open Assets & BIM from the sidebar, then select a space or model file. A WebGL viewer will load.',
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _sectionCard(
              icon: Icons.menu_book_rounded,
              color: const Color(0xFFFF922B),
              title: 'Quick Start Guide',
              child: Column(
                children: const [
                  _GuideTile(step: '1', title: 'Log In', desc: 'Sign in with your organization email and password.'),
                  _GuideTile(step: '2', title: 'Select Organization', desc: 'Pick your client organization from the list.'),
                  _GuideTile(step: '3', title: 'Select Facility', desc: 'Choose the facility you manage.'),
                  _GuideTile(step: '4', title: 'Explore Dashboard', desc: 'Use Quick Access cards or the sidebar to navigate modules.'),
                  _GuideTile(step: '5', title: 'Create Tasks', desc: 'Open Work Orders or Preventive Maintenance to get started.', last: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _sectionCard(
              icon: Icons.bug_report_rounded,
              color: const Color(0xFFFF6B6B),
              title: 'Report an Issue',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Found a bug or something not working as expected? Reach out and we\'ll investigate.',
                      style: GoogleFonts.poppins(
                          fontSize: 13.5, color: AppColors.textSecondary, height: 1.6),
                    ),
                    const SizedBox(height: 14),
                    _contactRow(Icons.email_rounded, AppColors.primary,
                        'infojvalmacis@gmail.com'),
                    const SizedBox(height: 10),
                    _contactRow(Icons.phone_rounded, const Color(0xFF12B886),
                        '+254 700 000 000'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _contactCard({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 11.5, color: AppColors.textSecondary)),
          const SizedBox(height: 3),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  static Widget _sectionCard({
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

  static Widget _contactRow(IconData icon, Color color, String value) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Text(value,
            style: GoogleFonts.poppins(
                fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ],
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String q;
  final String a;
  final bool last;

  const _FaqTile({required this.q, required this.a, this.last = false});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.q,
                      style: GoogleFonts.poppins(
                          fontSize: 13.5, fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: Color(0xFFADB5BD)),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(widget.a,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
          ),
          crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
        if (!widget.last)
          const Divider(height: 1, indent: 16, endIndent: 0, color: Color(0xFFF3F4F6)),
      ],
    );
  }
}

class _GuideTile extends StatelessWidget {
  final String step;
  final String title;
  final String desc;
  final bool last;

  const _GuideTile({
    required this.step,
    required this.title,
    required this.desc,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(step,
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.poppins(
                            fontSize: 13.5, fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(desc,
                        style: GoogleFonts.poppins(
                            fontSize: 12.5, color: AppColors.textSecondary, height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!last)
          const Divider(height: 1, indent: 56, endIndent: 0, color: Color(0xFFF3F4F6)),
      ],
    );
  }
}
