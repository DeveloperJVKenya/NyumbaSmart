import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:cmms/theme/app_theme.dart';

class NeedAccountScreen extends StatelessWidget {
  const NeedAccountScreen({super.key});

  Future<void> _launchURL(String url) async {
    try {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      Logger().e('Error launching URL: $e');
    }
  }

  Future<void> _launchEmail(String email) async {
    try {
      final url = 'mailto:$email';
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      Logger().e('Error launching email: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1200;
    final isDesktop = screenWidth >= 1200;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Need an Account?',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: isMobile ? 20 : isTablet ? 22 : 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primaryDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 4,
        shadowColor: AppColors.primary.withAlpha(128),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? screenWidth * 0.6 : screenWidth, // Limit to 60% on desktop
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main title outside card with custom styling
                    AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 500),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Text(
                            'Learn about NyumbaSmart and how to get started.',
                            style: GoogleFonts.poppins(
                              fontSize: isMobile ? 24 : isTablet ? 26 : 28,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(
                                  blurRadius: 4.0,
                                  color: AppColors.primary.withAlpha(80),
                                  offset: const Offset(2.0, 2.0),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Overview',
                      content:
                          'NyumbaSmart is a CMMS software tailored for managing maintenance of facilities. It offers features like work order tracking, preventive maintenance, billing, and custom reports, with added facility-specific tools.',
                      fontSize: isMobile ? 18 : isTablet ? 20 : 22,
                      contentFontSize: isMobile ? 14 : isTablet ? 15 : 16,
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Who Uses NyumbaSmart?',
                      content:
                          'Facility managers, maintenance teams, and billing administrators. Secure access for authorized personnel handling sensitive data.',
                      fontSize: isMobile ? 18 : isTablet ? 20 : 22,
                      contentFontSize: isMobile ? 14 : isTablet ? 15 : 16,
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'How to Get Started',
                      content:
                          'To use NyumbaSmart, you must be added by your organization’s NyumbaSmart Administrator, typically a facility manager. If your organization is not yet a customer, contact your administrator or visit our website at ',
                      fontSize: isMobile ? 18 : isTablet ? 20 : 22,
                      contentFontSize: isMobile ? 14 : isTablet ? 15 : 16,
                      additionalContent: GestureDetector(
                        onTap: () => _launchURL('https://jvalmacis.com'),
                        child: Text(
                          'jvalmacis.com',
                          style: GoogleFonts.poppins(
                            fontSize: isMobile ? 14 : isTablet ? 15 : 16,
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'Steps',
                      content:
                          'Your administrator will be given access to the software with privilege of onboarding his/her users with defined role(Technician) and once having onboarded your account with the user role, you will be able to access the system features from both web and mobile platforms with the same account 👍',
                      fontSize: isMobile ? 18 : isTablet ? 20 : 22,
                      contentFontSize: isMobile ? 14 : isTablet ? 15 : 16,
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      context,
                      title: 'See Also',
                      content:
                          'For more information, check out our support page or contact us at ',
                      fontSize: isMobile ? 18 : isTablet ? 20 : 22,
                      contentFontSize: isMobile ? 14 : isTablet ? 15 : 16,
                      additionalContent: GestureDetector(
                        onTap: () => _launchEmail('infojvalmacis@gmail.com'),
                        child: Text(
                          'infojvalmacis@gmail.com',
                          style: GoogleFonts.poppins(
                            fontSize: isMobile ? 14 : isTablet ? 15 : 16,
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    String? content,
    Widget? additionalContent,
    required double fontSize,
    double? contentFontSize,
  }) {
    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 500),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (content != null) ...[
                const SizedBox(height: 8),
                Text(
                  content,
                  style: GoogleFonts.poppins(
                    fontSize: contentFontSize,
                    color: Colors.black87,
                    height: 1.5,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (additionalContent != null) ...[
                const SizedBox(height: 8),
                Center(child: additionalContent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}