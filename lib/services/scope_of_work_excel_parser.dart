import 'package:excel/excel.dart';

/// A single maintenance task row extracted from an uploaded Scope of Work Excel workbook,
/// ready to become a `preventive_maintenance` task once the user confirms the parse preview.
class ParsedScopeOfWorkRow {
  final String category;
  final String component;
  final String intervention;
  final int frequencyMonths;

  const ParsedScopeOfWorkRow({
    required this.category,
    required this.component,
    required this.intervention,
    required this.frequencyMonths,
  });
}

/// Thrown when a workbook has no sheet with a recognizable Category/Component/Intervention/
/// Frequency header row, or every row failed to parse.
class ScopeOfWorkParseException implements Exception {
  final String message;
  const ScopeOfWorkParseException(this.message);

  @override
  String toString() => message;
}

/// Parses a Scope of Work Excel workbook into flat maintenance-task rows.
///
/// Real workbooks (see the JV Almacis "Annual Field Inspection Checklist" template) spread
/// tasks across multiple sheets grouped by frequency (Jan-Jun, Annual, Bi-Monthly, etc.), all
/// sharing one column layout: Category | Component | Intervention | Frequency | Checked
/// (Yes/No) | Findings | Inspector's Name & Date. Only the first four columns matter for
/// scheduling — the rest are for manual field completion during an actual inspection visit.
/// The sheet name itself is discarded: it's a redundant frequency grouping already restated by
/// the Frequency column, and mixing differently-named sheets from other templates would only
/// break a sheet-name-based mapping.
class ScopeOfWorkExcelParser {
  const ScopeOfWorkExcelParser._();

  static const _requiredHeaders = ['category', 'component', 'intervention', 'frequency'];

  static List<ParsedScopeOfWorkRow> parse(List<int> bytes) {
    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (e) {
      throw ScopeOfWorkParseException('Could not read this file as an Excel workbook: $e');
    }

    final rows = <ParsedScopeOfWorkRow>[];
    var sheetsWithHeader = 0;

    for (final table in workbook.tables.values) {
      final columnIndex = _findHeaderColumns(table);
      if (columnIndex == null) continue;
      sheetsWithHeader += 1;

      for (var r = columnIndex.headerRowIndex + 1; r < table.maxRows; r++) {
        final row = table.row(r);
        final category = _cellText(row, columnIndex.category);
        final component = _cellText(row, columnIndex.component);
        final intervention = _cellText(row, columnIndex.intervention);
        final frequencyText = _cellText(row, columnIndex.frequency);

        if (category.isEmpty && component.isEmpty && intervention.isEmpty) continue;

        final frequencyMonths = _parseFrequencyMonths(frequencyText);
        if (frequencyMonths == null) continue;

        rows.add(ParsedScopeOfWorkRow(
          category: category,
          component: component,
          intervention: intervention,
          frequencyMonths: frequencyMonths,
        ));
      }
    }

    if (sheetsWithHeader == 0) {
      throw const ScopeOfWorkParseException(
        'No sheet with Category/Component/Intervention/Frequency columns was found in this workbook.',
      );
    }
    if (rows.isEmpty) {
      throw const ScopeOfWorkParseException(
        'No valid maintenance tasks were found — every row was blank or had an unreadable frequency.',
      );
    }

    return rows;
  }

  static _HeaderColumns? _findHeaderColumns(Sheet table) {
    for (var r = 0; r < table.maxRows; r++) {
      final row = table.row(r);
      final normalized = <String, int>{};
      for (var c = 0; c < row.length; c++) {
        final text = _cellText(row, c).toLowerCase();
        if (text.isNotEmpty) normalized[text] = c;
      }

      final hasAllHeaders = _requiredHeaders.every(
        (header) => normalized.keys.any((k) => k.startsWith(header)),
      );
      if (!hasAllHeaders) continue;

      int columnFor(String header) =>
          normalized.entries.firstWhere((e) => e.key.startsWith(header)).value;

      return _HeaderColumns(
        headerRowIndex: r,
        category: columnFor('category'),
        component: columnFor('component'),
        intervention: columnFor('intervention'),
        frequency: columnFor('frequency'),
      );
    }
    return null;
  }

  static String _cellText(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return '';
    final value = row[index]?.value;
    if (value == null) return '';
    return value.toString().trim();
  }

  /// Extracts the leading integer out of free-text frequency values like "6 Months",
  /// "6 Month" (inconsistent pluralization is present in real templates), or "12 Months".
  static int? _parseFrequencyMonths(String text) {
    final match = RegExp(r'\d+').firstMatch(text);
    if (match == null) return null;
    final months = int.tryParse(match.group(0)!);
    if (months == null || months <= 0) return null;
    return months;
  }
}

class _HeaderColumns {
  final int headerRowIndex;
  final int category;
  final int component;
  final int intervention;
  final int frequency;

  const _HeaderColumns({
    required this.headerRowIndex,
    required this.category,
    required this.component,
    required this.intervention,
    required this.frequency,
  });
}
