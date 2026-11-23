import 'package:intl/intl.dart';

/// Global date-formatting utility that respects the user's date-format preference
/// (set in Settings → Display & Language). Call [setPref] when the preference
/// changes; all subsequent [format] / [formatShort] calls reflect the new choice.
class AppDateFormat {
  AppDateFormat._();

  static String _pref = 'DD/MM/YYYY';

  static void setPref(String pref) => _pref = pref;
  static String get currentPref => _pref;

  /// Full date, e.g. "12 Jan 2025" / "Jan 12, 2025" / "2025-01-12".
  static String format(DateTime dt) {
    switch (_pref) {
      case 'MM/DD/YYYY':
        return DateFormat('MMM dd, yyyy').format(dt);
      case 'YYYY-MM-DD':
        return DateFormat('yyyy-MM-dd').format(dt);
      case 'DD/MM/YYYY':
      default:
        return DateFormat('dd MMM yyyy').format(dt);
    }
  }

  /// Compact date, e.g. "12 Jan 25" / "Jan 12, 25" / "2025-01-12".
  static String formatShort(DateTime dt) {
    switch (_pref) {
      case 'MM/DD/YYYY':
        return DateFormat('MMM d, yy').format(dt);
      case 'YYYY-MM-DD':
        return DateFormat('yyyy-MM-dd').format(dt);
      case 'DD/MM/YYYY':
      default:
        return DateFormat('d MMM yy').format(dt);
    }
  }
}
