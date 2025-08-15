import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

class TimezoneUtils {
  static final Logger _logger = Logger();
  
  /// Parse Firestore date string format: "Aug 28, 2025 at 12:00:00 AM UTC+3"
  static DateTime? parseFirestoreDate(dynamic dateValue) {
    try {
      if (dateValue == null) return null;
      
      // If it's already a DateTime, return it
      if (dateValue is DateTime) return dateValue;
      
      // If it's a Timestamp, convert it
      if (dateValue.runtimeType.toString().contains('Timestamp')) {
        return (dateValue as dynamic).toDate();
      }
      
      // If it's a string, parse it
      if (dateValue is String) {
        return _parseFirestoreDateString(dateValue);
      }
      
      return null;
    } catch (e) {
      _logger.e('Error parsing Firestore date: $e');
      return null;
    }
  }
  
  static DateTime? _parseFirestoreDateString(String dateString) {
    try {
      // Handle format: "Aug 28, 2025 at 12:00:00 AM UTC+3"
      final regex = RegExp(r'(\w{3}) (\d{1,2}), (\d{4}) at (\d{1,2}):(\d{2}):(\d{2}) (AM|PM) UTC([+-]\d+)');
      final match = regex.firstMatch(dateString);
      
      if (match != null) {
        final monthStr = match.group(1)!;
        final day = int.parse(match.group(2)!);
        final year = int.parse(match.group(3)!);
        final hour = int.parse(match.group(4)!);
        final minute = int.parse(match.group(5)!);
        final second = int.parse(match.group(6)!);
        final amPm = match.group(7)!;
        final timezoneOffset = int.parse(match.group(8)!);
        
        // Convert month name to number
        final monthMap = {
          'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
          'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
        };
        final month = monthMap[monthStr] ?? 1;
        
        // Convert to 24-hour format
        int hour24 = hour;
        if (amPm == 'PM' && hour != 12) hour24 += 12;
        if (amPm == 'AM' && hour == 12) hour24 = 0;
        
        // Create DateTime with timezone offset
        final utcDateTime = DateTime.utc(year, month, day, hour24, minute, second);
        final offsetDateTime = utcDateTime.subtract(Duration(hours: timezoneOffset));
        
        return offsetDateTime.toLocal();
      }
      
      // Fallback: try standard DateTime.parse
      return DateTime.parse(dateString);
    } catch (e) {
      _logger.e('Error parsing date string "$dateString": $e');
      return null;
    }
  }
  
  /// Get current date in user's timezone
  static DateTime getCurrentDate() {
    return DateTime.now();
  }
  
  /// Get today at midnight in user's timezone
  static DateTime getTodayMidnight() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
  
  /// Check if a date is today
  static bool isToday(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkDate = DateTime(date.year, date.month, date.day);
    return checkDate.isAtSameMomentAs(today);
  }
  
  /// Check if a date is due (today or in the past)
  static bool isDue(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkDate = DateTime(date.year, date.month, date.day);
    return checkDate.isBefore(today) || checkDate.isAtSameMomentAs(today);
  }
  
  /// Format date for display
  static String formatForDisplay(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }
  
  /// Format date for Firestore storage
  static String formatForFirestore(DateTime date) {
    return DateFormat('MMM dd, yyyy \'at\' hh:mm:ss a \'UTC\'Z').format(date.toUtc());
  }
}
