import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cmms/models/ai_pm_analysis.dart';

class PmAnalysisExportRow {
  final String equipment;
  final String category;
  final int frequencyMonths;
  final double estimatedHours;
  final String reason;
  final List<String> tools;
  final List<String> spares;

  const PmAnalysisExportRow({
    required this.equipment,
    required this.category,
    required this.frequencyMonths,
    required this.estimatedHours,
    required this.reason,
    required this.tools,
    required this.spares,
  });
}

String _frequencyLabel(int months) {
  if (months == 1) return 'Monthly';
  if (months == 3) return 'Quarterly';
  if (months == 6) return 'Semi-annual';
  if (months == 12) return 'Annual';
  if (months % 12 == 0) return 'Every ${months ~/ 12} years';
  return 'Every $months months';
}

List<PmAnalysisExportRow> _toRows(List<AiPmAnalysisItem> items) {
  return items.map((item) => PmAnalysisExportRow(
    equipment: item.typeName.isNotEmpty ? item.typeName : item.equipmentName,
    category: item.effectiveCategory,
    frequencyMonths: item.frequencyMonths,
    estimatedHours: item.estimatedHours,
    reason: item.reason,
    tools: item.tools,
    spares: item.spares,
  )).toList();
}

class PmAnalysisExportService {
  PmAnalysisExportService._();

  static Uint8List toCsv(List<AiPmAnalysisItem> items) {
    final rows = _toRows(items);
    final buf = StringBuffer();
    buf.writeln('Element Type,Category,Maintenance Interval,Est. Hours,Reason for Maintenance,Tools Required,Spare Parts');
    for (final r in rows) {
      String q(String s) => '"${s.replaceAll('"', '""')}"';
      buf.writeln([
        q(r.equipment),
        q(r.category),
        q(_frequencyLabel(r.frequencyMonths)),
        q('${r.estimatedHours % 1 == 0 ? r.estimatedHours.toInt() : r.estimatedHours}'),
        q(r.reason),
        q(r.tools.join('; ')),
        q(r.spares.join('; ')),
      ].join(','));
    }
    return Uint8List.fromList(utf8.encode(buf.toString()));
  }

  static Uint8List toXlsx(List<AiPmAnalysisItem> items) {
    final excel = Excel.createExcel();
    final sheet = excel['PM Analysis'];
    // Remove default sheet if present
    excel.delete('Sheet1');

    final headers = ['Element Type', 'Category', 'Maintenance Interval', 'Est. Hours', 'Reason for Maintenance', 'Tools Required', 'Spare Parts'];
    for (var c = 0; c < headers.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).value =
          TextCellValue(headers[c]);
    }

    final rows = _toRows(items);
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final estStr = row.estimatedHours % 1 == 0
          ? '${row.estimatedHours.toInt()}'
          : '${row.estimatedHours}';
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r + 1)).value = TextCellValue(row.equipment);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r + 1)).value = TextCellValue(row.category);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r + 1)).value = TextCellValue(_frequencyLabel(row.frequencyMonths));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r + 1)).value = TextCellValue(estStr);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r + 1)).value = TextCellValue(row.reason);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1)).value = TextCellValue(row.tools.join('; '));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r + 1)).value = TextCellValue(row.spares.join('; '));
    }

    final bytes = excel.encode();
    return bytes != null ? Uint8List.fromList(bytes) : Uint8List(0);
  }

  static Future<Uint8List> toPdf(
    List<AiPmAnalysisItem> items, {
    String facilityName = 'Facility',
  }) async {
    final doc = pw.Document();
    final rows = _toRows(items);
    final dateStr = DateFormat('d MMMM yyyy').format(DateTime.now());

    const colWidths = [120.0, 60.0, 55.0, 35.0, 150.0, 90.0, 90.0];
    const headers = ['Element Type', 'Category', 'Maint. Interval', 'Hrs', 'Reason for Maintenance', 'Tools', 'Spare Parts'];

    final headerStyle = pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      fontSize: 9,
      color: PdfColors.white,
    );
    final cellStyle = const pw.TextStyle(fontSize: 8);
    final altBg = PdfColors.grey100;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '$facilityName — Preventive Maintenance Schedule',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('Generated $dateStr', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) {
          final chunks = <List<PmAnalysisExportRow>>[];
          for (var i = 0; i < rows.length; i += 30) {
            chunks.add(rows.sublist(i, i + 30 > rows.length ? rows.length : i + 30));
          }
          return [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1565C0)),
                  children: List.generate(7, (i) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: pw.Text(headers[i], style: headerStyle),
                  )),
                ),
                ...rows.asMap().entries.map((entry) {
                  final r = entry.value;
                  final bg = entry.key.isOdd ? altBg : PdfColors.white;
                  final estStr = r.estimatedHours % 1 == 0
                      ? '${r.estimatedHours.toInt()}h'
                      : '${r.estimatedHours}h';
                  final cells = [
                    r.equipment,
                    r.category,
                    _frequencyLabel(r.frequencyMonths),
                    estStr,
                    r.reason,
                    r.tools.join(', '),
                    r.spares.join(', '),
                  ];
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: bg),
                    children: cells.asMap().entries
                        .map((e) => pw.ConstrainedBox(
                              constraints: pw.BoxConstraints(maxWidth: colWidths[e.key]),
                              child: pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                child: pw.Text(e.value, style: cellStyle),
                              ),
                            ))
                        .toList(),
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    return doc.save();
  }

  /// Minimal DOCX (Office Open XML) with a table. No external package needed —
  /// the .docx format is a zip archive of XML files; we build it with dart:io on
  /// mobile/desktop and return the raw bytes for web download.
  static Future<Uint8List> toDocx(
    List<AiPmAnalysisItem> items, {
    String facilityName = 'Facility',
  }) async {
    // Build the document.xml content with a simple table.
    final rows = _toRows(items);
    final dateStr = DateFormat('d MMMM yyyy').format(DateTime.now());

    String escXml(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    final rowsXml = rows.map((r) {
      final estStr = r.estimatedHours % 1 == 0
          ? '${r.estimatedHours.toInt()}h'
          : '${r.estimatedHours}h';
      final cells = [
        r.equipment,
        r.category,
        _frequencyLabel(r.frequencyMonths),
        estStr,
        r.reason,
        r.tools.join('; '),
        r.spares.join('; '),
      ].map((text) {
        final escaped = escXml(text);
        return '<w:tc><w:p><w:r><w:t>$escaped</w:t></w:r></w:p></w:tc>';
      }).join();
      return '<w:tr>$cells</w:tr>';
    }).join();

    final headerCells = ['Element Type', 'Category', 'Maint. Interval', 'Est. Hrs', 'Reason for Maintenance', 'Tools Required', 'Spare Parts']
        .map((h) =>
            '<w:tc><w:tcPr><w:shd w:fill="1565C0"/></w:tcPr>'
            '<w:p><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr>'
            '<w:t>$h</w:t></w:r></w:p></w:tc>')
        .join();

    final docXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>
<w:p><w:r><w:rPr><w:b/><w:sz w:val="28"/></w:rPr>
<w:t>$facilityName — Preventive Maintenance Schedule</w:t></w:r></w:p>
<w:p><w:r><w:t>Generated $dateStr</w:t></w:r></w:p>
<w:tbl>
<w:tblPr><w:tblBorders>
<w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/>
<w:bottom w:val="single" w:sz="4"/><w:right w:val="single" w:sz="4"/>
<w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/>
</w:tblBorders></w:tblPr>
<w:tr>$headerCells</w:tr>
$rowsXml
</w:tbl>
</w:body></w:document>''';

    // Build a minimal .docx zip. On web we can't use dart:io Archive, so we
    // build it manually with a simple ZIP builder.
    return _buildDocx(docXml);
  }

  static Uint8List _buildDocx(String documentXml) {
    // Minimal OOXML package files.
    const relsXml = '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';

    const wordRelsXml = '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>';

    const contentTypesXml = '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>';

    final files = <String, Uint8List>{
      '[Content_Types].xml': Uint8List.fromList(utf8.encode(contentTypesXml)),
      '_rels/.rels': Uint8List.fromList(utf8.encode(relsXml)),
      'word/document.xml': Uint8List.fromList(utf8.encode(documentXml)),
      'word/_rels/document.xml.rels': Uint8List.fromList(utf8.encode(wordRelsXml)),
    };

    return _buildZip(files);
  }

  static Uint8List _buildZip(Map<String, Uint8List> files) {
    // Minimal ZIP archive builder (no compression — stored only).
    final buf = BytesBuilder();
    final centralDirectory = <Uint8List>[];
    var offset = 0;

    for (final entry in files.entries) {
      final nameBytes = utf8.encode(entry.key);
      final data = entry.value;
      final localHeader = _zipLocalFileHeader(nameBytes, data, offset);
      buf.add(localHeader);
      buf.add(data);
      centralDirectory.add(_zipCentralDirEntry(nameBytes, data, offset));
      offset += localHeader.length + data.length;
    }

    final cdBytes = centralDirectory.fold<Uint8List>(
        Uint8List(0), (a, b) => Uint8List.fromList([...a, ...b]));
    buf.add(cdBytes);
    buf.add(_zipEndOfCentralDir(files.length, cdBytes.length, offset));
    return buf.toBytes();
  }

  static Uint8List _zipLocalFileHeader(List<int> nameBytes, Uint8List data, int offset) {
    final buf = ByteData(30 + nameBytes.length);
    var i = 0;
    buf.setUint32(i, 0x04034b50, Endian.little); i += 4; // local file header signature
    buf.setUint16(i, 20, Endian.little); i += 2;  // version needed
    buf.setUint16(i, 0, Endian.little); i += 2;   // flags
    buf.setUint16(i, 0, Endian.little); i += 2;   // compression: stored
    buf.setUint16(i, 0, Endian.little); i += 2;   // mod time
    buf.setUint16(i, 0, Endian.little); i += 2;   // mod date
    buf.setUint32(i, _crc32(data), Endian.little); i += 4;
    buf.setUint32(i, data.length, Endian.little); i += 4;
    buf.setUint32(i, data.length, Endian.little); i += 4;
    buf.setUint16(i, nameBytes.length, Endian.little); i += 2;
    buf.setUint16(i, 0, Endian.little); // extra field len
    return Uint8List.fromList([...buf.buffer.asUint8List(), ...nameBytes]);
  }

  static Uint8List _zipCentralDirEntry(List<int> nameBytes, Uint8List data, int offset) {
    final buf = ByteData(46 + nameBytes.length);
    var i = 0;
    buf.setUint32(i, 0x02014b50, Endian.little); i += 4;
    buf.setUint16(i, 20, Endian.little); i += 2;
    buf.setUint16(i, 20, Endian.little); i += 2;
    buf.setUint16(i, 0, Endian.little); i += 2;
    buf.setUint16(i, 0, Endian.little); i += 2;
    buf.setUint16(i, 0, Endian.little); i += 2;
    buf.setUint16(i, 0, Endian.little); i += 2;
    buf.setUint32(i, _crc32(data), Endian.little); i += 4;
    buf.setUint32(i, data.length, Endian.little); i += 4;
    buf.setUint32(i, data.length, Endian.little); i += 4;
    buf.setUint16(i, nameBytes.length, Endian.little); i += 2;
    buf.setUint16(i, 0, Endian.little); i += 2;
    buf.setUint16(i, 0, Endian.little); i += 2;
    buf.setUint16(i, 0, Endian.little); i += 2;
    buf.setUint16(i, 0, Endian.little); i += 2;
    buf.setUint32(i, 0, Endian.little); i += 4;
    buf.setUint32(i, offset, Endian.little);
    return Uint8List.fromList([...buf.buffer.asUint8List(), ...nameBytes]);
  }

  static Uint8List _zipEndOfCentralDir(int count, int cdSize, int cdOffset) {
    final buf = ByteData(22);
    var i = 0;
    buf.setUint32(i, 0x06054b50, Endian.little); i += 4;
    buf.setUint16(i, 0, Endian.little); i += 2;
    buf.setUint16(i, 0, Endian.little); i += 2;
    buf.setUint16(i, count, Endian.little); i += 2;
    buf.setUint16(i, count, Endian.little); i += 2;
    buf.setUint32(i, cdSize, Endian.little); i += 4;
    buf.setUint32(i, cdOffset, Endian.little); i += 4;
    buf.setUint16(i, 0, Endian.little);
    return buf.buffer.asUint8List();
  }

  static int _crc32(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (var j = 0; j < 8; j++) {
        if (crc & 1 == 1) {
          crc = (crc >>> 1) ^ 0xEDB88320;
        } else {
          crc >>>= 1;
        }
      }
    }
    return (~crc) & 0xFFFFFFFF;
  }
}

// Download helpers are handled at the UI layer:
// • Web: build a Blob URL via dart:js_interop / 'web' package and click an anchor.
// • Mobile: path_provider to get the downloads/documents directory, then open_file.
// The export service's job is only to produce the bytes.
