/// Calendar-accurate date math for preventive maintenance scheduling, shared by every place
/// that turns a frequency (in months) into a due date — previously duplicated as a crude
/// `+ frequency * 30 days` approximation in the Scope of Work manual-add flow, while the
/// notification service had its own more correct but separate implementation.
class PmSchedulingService {
  const PmSchedulingService._();

  /// Adds [months] to [from], handling year rollover and clamping the day to the target
  /// month's actual length (e.g. Jan 31 + 1 month -> Feb 28/29, not Mar 3).
  static DateTime addMonths(DateTime from, int months) {
    var next = DateTime(from.year, from.month + months, from.day);

    while (next.month > 12) {
      next = DateTime(next.year + 1, next.month - 12, next.day);
    }

    final daysInTargetMonth = DateTime(next.year, next.month + 1, 0).day;
    if (next.day > daysInTargetMonth) {
      next = DateTime(next.year, next.month, daysInTargetMonth);
    }

    return next;
  }

  /// If [date] falls on a Saturday or Sunday, moves it back to the preceding Friday — due
  /// dates, notification dates, and alert dates are all business-day-only.
  static DateTime shiftOffWeekend(DateTime date) {
    switch (date.weekday) {
      case DateTime.saturday:
        return date.subtract(const Duration(days: 1));
      case DateTime.sunday:
        return date.subtract(const Duration(days: 2));
      default:
        return date;
    }
  }

  static DateTime computeDueDate({required DateTime from, required int frequencyMonths}) {
    return shiftOffWeekend(addMonths(from, frequencyMonths));
  }

  static DateTime computeNotificationDate(DateTime dueDate) => shiftOffWeekend(dueDate.subtract(const Duration(days: 5)));

  static DateTime computeAlertDate(DateTime dueDate) => shiftOffWeekend(dueDate.subtract(const Duration(days: 1)));

  /// The full annual plan for a given frequency, anchored to January 1st: occurrences fall on
  /// the last day of month [frequencyMonths], 2×, 3×, etc. within [year] — e.g. a 6-month
  /// frequency pairs up as end-of-June and end-of-December; quarterly (3 months) lands on
  /// Mar/Jun/Sep/Dec; monthly (1 month) lands at the end of every month. A frequency longer
  /// than a year (e.g. 18 months) has no occurrence within a single calendar year, so it falls
  /// back to one occurrence [frequencyMonths] after January 1st.
  static List<DateTime> generateYearlyOccurrences({required int year, required int frequencyMonths}) {
    final occurrences = <DateTime>[];
    var month = frequencyMonths;
    while (month <= 12) {
      final lastDayOfMonth = DateTime(year, month + 1, 0);
      occurrences.add(shiftOffWeekend(lastDayOfMonth));
      month += frequencyMonths;
    }

    if (occurrences.isEmpty) {
      occurrences.add(computeDueDate(from: DateTime(year, 1, 1), frequencyMonths: frequencyMonths));
    }

    return occurrences;
  }

  /// The first occurrence of the year's plan — used to (re)seed a task's due date onto the
  /// calendar-aligned schedule, including retroactively for existing tasks: if that first
  /// occurrence has already passed this year, the due date correctly comes back as overdue
  /// rather than silently skipping ahead to a later slot.
  static DateTime firstOccurrenceOfYear({required int year, required int frequencyMonths}) {
    return generateYearlyOccurrences(year: year, frequencyMonths: frequencyMonths).first;
  }

  /// The next occurrence on the annual plan at or after [from] — used to seed a *new* task's
  /// due date without immediately flagging it overdue, unlike [firstOccurrenceOfYear].
  static DateTime nextUpcomingOccurrence({required DateTime from, required int frequencyMonths}) {
    var year = from.year;
    while (true) {
      final occurrences = generateYearlyOccurrences(year: year, frequencyMonths: frequencyMonths);
      for (final occurrence in occurrences) {
        if (!occurrence.isBefore(from)) return occurrence;
      }
      year += 1;
    }
  }

  /// Walks forward from [anchor] in [frequencyMonths] steps until reaching a date that isn't
  /// before [notBefore] — used to regenerate a facility's schedule around a user-chosen
  /// maintenance start date (which may fall mid-month or mid-year) without ever landing on a
  /// past date, unlike [firstOccurrenceOfYear] which deliberately can. Each task still follows
  /// its own frequency pairing; only the anchor date differs from the Jan-1 annual plan.
  static DateTime nextOccurrenceFromAnchor({
    required DateTime anchor,
    required int frequencyMonths,
    required DateTime notBefore,
  }) {
    var candidate = computeDueDate(from: anchor, frequencyMonths: frequencyMonths);
    while (candidate.isBefore(notBefore)) {
      candidate = computeDueDate(from: candidate, frequencyMonths: frequencyMonths);
    }
    return candidate;
  }

  /// Whether a task's due date has passed without it being completed — used to show an
  /// "Overdue" badge without needing a separate scheduled job to flip a stored status.
  static bool isOverdue({required DateTime? dueDate, required bool isCompleted}) {
    if (dueDate == null || isCompleted) return false;
    final today = DateTime.now();
    return dueDate.isBefore(DateTime(today.year, today.month, today.day));
  }
}
