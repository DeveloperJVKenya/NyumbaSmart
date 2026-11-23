import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central color palette for NyumbaSmart.
///
/// Deep indigo conveys trust/software while the warm amber accent gives the
/// UI some warmth so it doesn't read as cold/corporate. Replaces the old
/// ad hoc `Colors.blueGrey` literals scattered across screens.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF4F46E5); // indigo-600
  static const Color primaryDark = Color(0xFF3730A3); // indigo-800
  static const Color primaryLight = Color(0xFF818CF8); // indigo-400

  static const Color accent = Color(0xFFF59E0B); // amber-500
  static const Color accentLight = Color(0xFFFBBF24); // amber-400

  static const Color surface = Color(0xFFF8FAFC); // slate-50
  static const Color surfaceAlt = Color(0xFFEEF2FF); // indigo-50
  static const Color card = Colors.white;

  static const Color textPrimary = Color(0xFF1E1B4B); // indigo-950
  static const Color textSecondary = Color(0xFF64748B); // slate-500

  static const Color error = Color(0xFFDC2626);
  static const Color errorBg = Color(0xFFFEF2F2);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight],
  );

  /// Indigo backdrop used behind the welcome/auth screens — same family as
  /// [primary]/[primaryDark], lightened a step so it doesn't read as heavy
  /// behind the foreground card/buttons.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4338CA), Color(0xFF6366F1), primaryLight],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [surfaceAlt, surface],
  );
}

/// Shared radius/spacing constants so "curvy" stays consistent app-wide.
class AppRadius {
  AppRadius._();

  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double pill = 999;
}

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppPlatform {
  AppPlatform._();

  /// `google_maps_flutter` only ships Android/iOS/Web implementations — no
  /// desktop (Windows/macOS/Linux) backend exists. `defaultTargetPlatform`
  /// reflects the host OS even on web, so the `kIsWeb` check must come first.
  static bool get mapsSupported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
}

/// Responsive breakpoints used across the auth/dashboard shell.
class AppBreakpoints {
  AppBreakpoints._();

  static const double mobile = 600;
  static const double tablet = 1024;

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < tablet;
  static bool isDesktop(double width) => width >= tablet;
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primaryLight,
      secondary: AppColors.accentLight,
      surface: const Color(0xFF1E293B),
      // surfaceContainer* slots are used by Material 3 menus and dropdowns.
      // Without explicit values they are auto-generated from the seed and may
      // be unintentionally light, making dropdown text invisible in dark mode.
      surfaceContainer: const Color(0xFF1E293B),
      surfaceContainerLow: const Color(0xFF162032),
      surfaceContainerHigh: const Color(0xFF263548),
      surfaceContainerHighest: const Color(0xFF2E3F54),
      onSurface: const Color(0xFFF1F5F9),
      onSurfaceVariant: const Color(0xFF94A3B8),
      error: AppColors.error,
    );

    final textTheme = GoogleFonts.poppinsTextTheme().apply(
      bodyColor: const Color(0xFFF1F5F9),
      displayColor: const Color(0xFFF1F5F9),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1E293B),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        prefixIconColor: AppColors.primaryLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        labelStyle: GoogleFonts.poppins(color: const Color(0xFF94A3B8)),
      ),
      dividerColor: const Color(0xFF334155),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Color(0xFF1E293B),
      ),
    );
  }

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      error: AppColors.error,
    );

    final textTheme = GoogleFonts.poppinsTextTheme().apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surface,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        // A visible resting border (not just fill color) so fields read as
        // distinct, fillable inputs before the user types anything.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.textSecondary.withValues(alpha: 0.35), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: AppColors.textSecondary.withValues(alpha: 0.35), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        labelStyle: GoogleFonts.poppins(color: AppColors.textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      dividerColor: const Color(0xFFE5E7EB),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.card,
      ),
    );
  }
}

/// Adaptive color helpers — use these instead of hardcoded AppColors constants
/// so elements stay correct in both light and dark themes.
extension ThemeAdaptive on BuildContext {
  Color get textPrimary => Theme.of(this).colorScheme.onSurface;
  Color get textSecondary => Theme.of(this).colorScheme.onSurfaceVariant;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Page / scaffold background — slate-50 light, near-black dark.
  Color get surfaceColor => Theme.of(this).colorScheme.surface;

  /// Alternate tinted surface — indigo-50 light, dark card dark.
  Color get surfaceAltColor =>
      isDark ? const Color(0xFF1E293B) : AppColors.surfaceAlt;

  /// Card / sheet surface — white light, dark card dark.
  Color get cardColor =>
      Theme.of(this).cardTheme.color ?? AppColors.card;

  /// Sidebar / drawer panel background.
  Color get panelColor =>
      Theme.of(this).drawerTheme.backgroundColor ?? AppColors.card;

  /// Subtle separator line.
  Color get dividerColor => Theme.of(this).dividerColor;
}
