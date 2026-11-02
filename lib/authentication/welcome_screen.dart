import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/theme/app_theme.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  WelcomeScreenState createState() => WelcomeScreenState();
}

class WelcomeScreenState extends State<WelcomeScreen> {
  int _currentIndex = 0;
  Timer? _autoPlayTimer;
  double _dragStartX = 0;

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
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 6), (_) => _goTo(_currentIndex + 1));
  }

  void _goTo(int index) {
    if (!mounted) return;
    setState(() => _currentIndex = index % slides.length);
    _startAutoPlay(); // reset the auto-play clock on manual navigation too
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    super.dispose();
  }

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
    final slide = slides[_currentIndex];

    return Scaffold(
      // Solid, static backdrop — no gradient/animation here. That treatment
      // is reserved for the login/registration cards (AppAuthBackground);
      // this screen should just be the carousel imagery filling the device.
      backgroundColor: AppColors.primaryDark,
      body: Stack(
        children: [
          Center(
            child: GestureDetector(
              onHorizontalDragStart: (details) => _dragStartX = details.localPosition.dx,
              onHorizontalDragEnd: (details) {
                final delta = details.localPosition.dx - _dragStartX;
                if (delta.abs() < 40) return;
                _goTo(delta < 0 ? _currentIndex + 1 : _currentIndex - 1 + slides.length);
              },
              child: SizedBox(
                width: carouselWidth,
                height: screenHeight,
                child: ClipRRect(
                  borderRadius: isDesktop ? BorderRadius.circular(AppRadius.xl) : BorderRadius.zero,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 700),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      fit: StackFit.expand,
                      children: [...previousChildren, ?currentChild],
                    ),
                    child: SizedBox(
                      key: ValueKey(_currentIndex),
                      width: carouselWidth,
                      height: screenHeight,
                      child: _buildSlide(slide, isMobile, isTablet, carouselWidth, screenHeight),
                    ),
                  ),
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
                    Center(
                      child: _GradientCta(
                        label: 'Sign In',
                        icon: Icons.login_rounded,
                        onPressed: () => Navigator.pushNamed(context, '/login'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(child: _GlassCta(onPressed: () => Navigator.pushNamed(context, '/needAccount'))),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(slides.length, (index) {
                        final active = _currentIndex == index;
                        return GestureDetector(
                          onTap: () => _goTo(index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4.0),
                            width: active ? 22.0 : 8.0,
                            height: 8.0,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              color: active ? AppColors.accent : Colors.white.withValues(alpha: 0.45),
                            ),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Decorative glow blobs
            Positioned(top: -60, right: -40,
              child: Container(width: 260, height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.08)))),
            Positioned(bottom: -80, left: -60,
              child: Container(width: 300, height: 300,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.1)))),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    boxShadow: [
                      BoxShadow(color: AppColors.accent.withValues(alpha: 0.2), blurRadius: 32, offset: const Offset(0, 12)),
                    ],
                  ),
                  child: Image.asset(
                    slide.image!,
                    height: isMobile ? 96.0 : isTablet ? 136.0 : 176.0,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        slide.title,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: titleSize + 2, fontWeight: FontWeight.w800,
                            color: Colors.white, letterSpacing: -0.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        slide.subtitle,
                        style: GoogleFonts.poppins(fontSize: subtitleSize,
                            color: Colors.white.withValues(alpha: 0.75), height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
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
        // Cinematic multi-stop gradient — top stays photo-bright,
        // bottom fades to near-black for text legibility.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Color(0x15000000),
                Color(0x70000000),
                Color(0xD8000000),
              ],
              stops: [0.0, 0.35, 0.68, 1.0],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 190.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  slide.title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: titleSize, fontWeight: FontWeight.w800,
                      color: Colors.white, letterSpacing: -0.3, height: 1.2),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  slide.subtitle,
                  style: GoogleFonts.poppins(
                      fontSize: subtitleSize,
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.5),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
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
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
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

class _GlassCta extends StatelessWidget {
  final VoidCallback onPressed;
  const _GlassCta({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onPressed,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_outlined, color: Colors.white.withValues(alpha: 0.9), size: 18),
              const SizedBox(width: 8),
              Text(
                'Need an Account?',
                style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],
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
