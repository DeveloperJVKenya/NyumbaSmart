import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  WelcomeScreenState createState() => WelcomeScreenState();
}

class WelcomeScreenState extends State<WelcomeScreen> {
  int _currentIndex = 0;

  final List<Slide> slides = [
    Slide(
      image: 'assets/nyumbasmart.jpg',
      title: 'Facility Management Software',
      subtitle: 'Developed by JV ALMA C.I.S',
    ),
    Slide(
      image: 'assets/fm.jpg',
      title: 'Digitize Your Facility Management',
      subtitle: 'NyumbaSmart keeps your buildings and facilities secure and efficient. Log in to manage maintenance, billing, and more with confidence.',
    ),
    Slide(
      images: ['assets/aircon.jpg', 'assets/hvac.jpg'],
      title: 'Optimize Your System and Electricals',
      subtitle: 'Ensure your systems and electricals are running smoothly with our comprehensive management tools.',
    ),
    Slide(
      image: 'assets/teams.jpg',
      title: 'Track Maintenance with Ease',
      subtitle: 'Monitor work orders and preventive maintenance in real-time for seamless operations.',
    ),
    Slide(
      image: 'assets/maintenance.jpg',
      title: 'Monitor Maintenance Team Activities',
      subtitle: 'Track work done by the team as they record activities and updates using the app.',
    ),
    Slide(
      image: 'assets/accountant1.jpg',
      title: 'Simplify Reports and Billing Processes',
      subtitle: 'Manage facility costs and get customized reports with system integrated tools.',
    ),
    Slide(
      image: 'assets/lock2.jpg',
      title: 'Secure Access for Authorized Users',
      subtitle: 'Protect sensitive data with role-based access for facility staff only.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isMobile = AppBreakpoints.isMobile(screenWidth);
    final isTablet = AppBreakpoints.isTablet(screenWidth);
    final isDesktop = AppBreakpoints.isDesktop(screenWidth);
    // On wide screens, cap the carousel width like a hero panel instead of
    // stretching a mobile-shaped layout full-bleed.
    final carouselWidth = isDesktop ? screenWidth * 0.7 : screenWidth;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AppAnimatedBackdrop()),
          Center(
            child: SizedBox(
              width: carouselWidth,
              height: screenHeight,
              child: ClipRRect(
                borderRadius: isDesktop
                    ? BorderRadius.circular(AppRadius.xl)
                    : BorderRadius.zero,
                child: CarouselSlider(
                  options: CarouselOptions(
                    height: screenHeight,
                    enlargeCenterPage: true,
                    enableInfiniteScroll: true,
                    autoPlay: true,
                    autoPlayInterval: const Duration(seconds: 6),
                    viewportFraction: 1.0,
                    onPageChanged: (index, reason) {
                      setState(() => _currentIndex = index);
                    },
                  ),
                  items: slides.map((slide) {
                    return Builder(
                      builder: (BuildContext context) {
                        return SizedBox(
                          width: carouselWidth,
                          height: screenHeight,
                          child: _buildSlide(slide, isMobile, isTablet, carouselWidth, screenHeight),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: isMobile ? 32.0 : 48.0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isDesktop ? screenWidth * 0.2 : 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _GradientCta(
                      label: 'Sign In',
                      icon: Icons.login_rounded,
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pushNamed(context, '/needAccount'),
                      icon: const Icon(Icons.help_outline, size: 18),
                      label: Text(
                        'Need an Account?',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(slides.length, (index) {
                        final active = _currentIndex == index;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 4.0),
                          width: active ? 22.0 : 8.0,
                          height: 8.0,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            color: active ? AppColors.accent : Colors.white.withValues(alpha: 0.45),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlide(Slide slide, bool isMobile, bool isTablet, double width, double height) {
    final titleSize = isMobile ? 22.0 : isTablet ? 26.0 : 30.0;
    final subtitleSize = isMobile ? 14.0 : isTablet ? 15.5 : 17.0;

    if (slide.image == 'assets/nyumbasmart.jpg') {
      return DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 24, offset: const Offset(0, 10)),
                  ],
                ),
                child: Image.asset(
                  slide.image!,
                  height: isMobile ? 90.0 : isTablet ? 130.0 : 170.0,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    slide.title,
                    style: GoogleFonts.poppins(fontSize: titleSize, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    slide.subtitle,
                    style: GoogleFonts.poppins(fontSize: subtitleSize, color: Colors.white.withValues(alpha: 0.9)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget imageLayer;
    if (slide.images != null && slide.images!.length > 1) {
      imageLayer = Row(
        children: [
          Expanded(child: Image.asset(slide.images![0], fit: BoxFit.cover, height: height)),
          Expanded(child: Image.asset(slide.images![1], fit: BoxFit.cover, height: height)),
        ],
      );
    } else {
      imageLayer = Image.asset(slide.image!, fit: BoxFit.cover, width: width, height: height);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        imageLayer,
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
              stops: const [0.4, 1.0],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 190.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  slide.title,
                  style: GoogleFonts.poppins(fontSize: titleSize, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  slide.subtitle,
                  style: GoogleFonts.poppins(fontSize: subtitleSize, color: Colors.white.withValues(alpha: 0.9)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GradientCta extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _GradientCta({required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
        boxShadow: [
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onPressed,
          child: Container(
            width: double.infinity,
            height: 54,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(label, style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Slide {
  final String? image;
  final List<String>? images;
  final String title;
  final String subtitle;

  Slide({this.image, this.images, required this.title, required this.subtitle});
}
