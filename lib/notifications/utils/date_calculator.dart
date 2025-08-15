import 'package:cmms/notifications/utils/timezone_utils.dart';

class NotificationDateCalculator {
  /// Calculate notification dates for a given frequency
  static Map<String, DateTime> calculateNotificationDates({
    required DateTime lastInspectionDate,
    required int frequencyMonths,
  }) {
    // Calculate next inspection date considering leap years
    DateTime nextInspectionDate = DateTime(
      lastInspectionDate.year,
      lastInspectionDate.month + frequencyMonths,
      lastInspectionDate.day,
    );

    // Handle month overflow
    while (nextInspectionDate.month > 12) {
      nextInspectionDate = DateTime(
        nextInspectionDate.year + 1,
        nextInspectionDate.month - 12,
        nextInspectionDate.day,
      );
    }

    // Handle day overflow for months with different day counts
    final daysInMonth = DateTime(nextInspectionDate.year, nextInspectionDate.month + 1, 0).day;
    if (nextInspectionDate.day > daysInMonth) {
      nextInspectionDate = DateTime(
        nextInspectionDate.year,
        nextInspectionDate.month,
        daysInMonth,
      );
    }

    // Notification date: 5 days before next inspection
    final notificationDate = nextInspectionDate.subtract(const Duration(days: 5));

    // Alert date: 1 day before next inspection
    final alertDate = nextInspectionDate.subtract(const Duration(days: 1));

    return {
      'nextInspectionDate': nextInspectionDate,
      'notificationDate': notificationDate,
      'alertDate': alertDate,
    };
  }

  /// Get next schedule for a specific frequency in a year
  static Map<String, DateTime> getNextScheduleForFrequency({
    required int frequencyMonths,
    required int year,
  }) {
    //final yearStart = DateTime(year, 1, 1);
    
    // Calculate the next occurrence based on frequency
    final nextInspectionDate = DateTime(year, frequencyMonths, 1);
    final notificationDate = nextInspectionDate.subtract(const Duration(days: 5));
    final alertDate = nextInspectionDate.subtract(const Duration(days: 1));

    return {
      'nextInspectionDate': nextInspectionDate,
      'notificationDate': notificationDate,
      'alertDate': alertDate,
    };
  }

  /// Get year start date
  static DateTime getYearStartDate(int year) {
    return DateTime(year, 1, 1);
  }

  /// Check if date is in future
  static bool isDateInFuture(DateTime date) {
    return date.isAfter(TimezoneUtils.getCurrentDate());
  }

  /// Format date for display
  static String formatDateForDisplay(DateTime date) {
    return TimezoneUtils.formatForDisplay(date);
  }

  /// Get relative date string
  static String getRelativeDateString(DateTime date) {
    final now = TimezoneUtils.getCurrentDate();
    final difference = date.difference(now).inDays;

    if (difference < 0) {
      return '${difference.abs()} days overdue';
    } else if (difference == 0) {
      return 'Due today';
    } else if (difference == 1) {
      return 'Due tomorrow';
    } else if (difference <= 7) {
      return 'Due in $difference days';
    } else if (difference <= 30) {
      final weeks = (difference / 7).round();
      return 'Due in $weeks week${weeks > 1 ? 's' : ''}';
    } else {
      final months = (difference / 30).round();
      return 'Due in $months month${months > 1 ? 's' : ''}';
    }
  }
}
