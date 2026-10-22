import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:cmms/services/bim/cobie_parser.dart';

/// Thin adapter over the `excel` package. Reads .xlsx only (the package cannot read legacy .xls).
///
/// Version note: this is the one place that depends on the `excel` package API. In excel 4.x a cell's
/// `value` is a CellValue object whose `toString()` returns the plain text (TextCellValue -> its
/// TextSpan text, Int/Double -> the number, Date -> ISO 8601; verified against excel 4.0.6).
/// Formula cells return the formula, not its cached result.
class CobieWorkbookReader {
  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _text(Data? cell) => cell?.value?.toString() ?? '';

  static CobieWorkbook read(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final out = <String, List<Map<String, String>>>{};

    for (final entry in excel.tables.entries) {
      final sheet = entry.value;
      if (sheet.rows.isEmpty) continue;

      final rawHeader = sheet.rows.first.map(_text).toList();
      // Fail fast if a future excel version stringifies text cells as objects instead of their text.
      // If this fires after an upgrade, change _text() to read the text from the value directly.
      if (rawHeader.any((h) => h.contains('TextSpan') || h.contains('Instance of'))) {
        throw const FormatException(
            'The excel package returned cell objects instead of text. Adjust CobieWorkbookReader._text().');
      }
      final header = rawHeader.map(_norm).toList();
      final rows = <Map<String, String>>[];

      for (final r in sheet.rows.skip(1)) {
        final m = <String, String>{};
        var hasData = false;
        for (var i = 0; i < header.length && i < r.length; i++) {
          if (header[i].isEmpty) continue;
          final t = _text(r[i]).trim();
          if (t.isNotEmpty) hasData = true;
          m[header[i]] = t;
        }
        if (hasData) rows.add(m);
      }
      out[entry.key.trim().toLowerCase()] = rows;
    }
    return out;
  }
}
