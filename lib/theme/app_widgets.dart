import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';

/// Shared curvy building blocks reused across the auth flow and dashboard
/// shell so those screens share one visual language instead of each
/// hand-rolling its own form fields/buttons/cards.

class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.poppins(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class AppGradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  const AppGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    return Opacity(
      opacity: disabled && isLoading ? 0.85 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          gradient: disabled && !isLoading ? null : AppColors.primaryGradient,
          color: disabled && !isLoading ? Colors.grey[300] : null,
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: disabled ? null : onPressed,
            child: SizedBox(
              height: 54,
              child: Padding(
                // Breathing room around text/icon — needed now that this
                // button hugs its own content instead of being stretched
                // full-width by a parent Expanded/SizedBox.
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[
                              Icon(icon, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                label,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

class AppErrorBanner extends StatelessWidget {
  final String message;

  const AppErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.poppins(color: AppColors.error, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-bleed decorative gradient background used behind auth cards.
/// Wraps [AppAnimatedBackdrop] so the gradient + floating blobs sit behind
/// [child].
class AppAuthBackground extends StatelessWidget {
  final Widget child;

  const AppAuthBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: AppAnimatedBackdrop()),
        child,
      ],
    );
  }
}

/// Slowly drifting/pulsing decorative blobs over [AppColors.heroGradient] —
/// a lightweight ambient animation so the auth/welcome backdrop doesn't sit
/// perfectly static. No child slot: layer it behind content with a
/// `Positioned.fill` (see [AppAuthBackground] and welcome_screen.dart).
class AppAnimatedBackdrop extends StatefulWidget {
  const AppAnimatedBackdrop({super.key});

  @override
  State<AppAnimatedBackdrop> createState() => _AppAnimatedBackdropState();
}

class _AppAnimatedBackdropState extends State<AppAnimatedBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Stack(
            children: [
              Positioned(
                top: -80 + (t * 24),
                right: -60 - (t * 18),
                child: _blob(220 + (t * 20), Colors.white.withValues(alpha: 0.08)),
              ),
              Positioned(
                bottom: -100 - (t * 20),
                left: -80 + (t * 26),
                child: _blob(260 - (t * 16), AppColors.accent.withValues(alpha: 0.16 + t * 0.05)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _blob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Shimmer-style placeholder card used while a Firestore snapshot is still
/// loading (facility/organization pickers, etc.) — reads as "content is
/// coming" rather than a bare spinner, so pages feel faster even before
/// data arrives.
class AppSkeletonCard extends StatefulWidget {
  final double height;

  const AppSkeletonCard({super.key, this.height = 96});

  @override
  State<AppSkeletonCard> createState() => _AppSkeletonCardState();
}

class _AppSkeletonCardState extends State<AppSkeletonCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            gradient: LinearGradient(
              begin: Alignment(-1 + t * 3, 0),
              end: Alignment(0 + t * 3, 0),
              colors: const [
                AppColors.surfaceAlt,
                Colors.white,
                AppColors.surfaceAlt,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A short column of [AppSkeletonCard]s for list/grid loading states.
class AppSkeletonList extends StatelessWidget {
  final int count;
  final double itemHeight;

  const AppSkeletonList({super.key, this.count = 4, this.itemHeight = 96});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // shrinkWrap + NeverScrollableScrollPhysics: this is used inside
      // Columns/SingleChildScrollViews that give it unbounded height (not
      // just bounded Expanded slots) — without these a bare ListView
      // throws "Vertical viewport was given unbounded height".
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => AppSkeletonCard(height: itemHeight),
    );
  }
}
