import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cmms/services/bim/cobie_parser.dart';

/// Wraps the Google Cloud Translation API v2 (REST / Simple API key auth).
///
/// Usage:
///   1. Enable the Cloud Translation API in GCP.
///   2. Create an API key restricted to that API.
///   3. Pass it via [translateAndApply].
class BimTranslationService {
  BimTranslationService._();

  static const _endpoint =
      'https://translation.googleapis.com/language/translate/v2';
  // Google recommends ≤128 strings or ≤30 kB per request; keep 100 to be safe.
  static const _batchSize = 100;

  // ── Public entry point ────────────────────────────────────────────────────

  /// Collects all translatable strings from [preview], calls Google Translate
  /// to translate them all to [target] (default English), then returns a new
  /// [CobiePreview] with the translated values substituted in.
  ///
  /// Throws a [BimTranslationException] with a readable message on API error.
  static Future<CobiePreview> translateAndApply(
    CobiePreview preview, {
    required String apiKey,
    String target = 'en',
    void Function(String stage, double fraction)? onProgress,
  }) async {
    final strings = _collectStrings(preview);
    if (strings.isEmpty) return preview;

    onProgress?.call('Translating ${strings.length} strings…', 0.0);

    final map = await _translateAll(
      strings,
      apiKey: apiKey,
      target: target,
      onProgress: onProgress,
    );

    return _applyMap(preview, map);
  }

  // ── String collection ─────────────────────────────────────────────────────

  static List<String> _collectStrings(CobiePreview p) {
    final seen = <String>{};
    void add(String? s) {
      if (s != null && s.isNotEmpty) seen.add(s);
    }

    for (final s in p.spaces) {
      add(s.name);
      add(s.description);
    }
    for (final e in p.equipment) {
      add(e.name);
      // typeName often equals type (e.g. 'HVAC') — only translate when distinct
      if (e.typeName.isNotEmpty && e.typeName != e.type) add(e.typeName);
      add(e.systemName);
      if (e.notes.isNotEmpty) add(e.notes);
    }
    for (final j in p.jobs) {
      add(j.name);
      add(j.category);
      add(j.component);
      add(j.intervention);
      add(j.notes);
    }
    for (final s in p.systems) {
      add(s.name);
      add(s.category);
    }
    for (final s in p.spares) {
      add(s.name);
      add(s.typeName);
      add(s.description);
    }

    return seen.toList();
  }

  // ── API calls ─────────────────────────────────────────────────────────────

  static Future<Map<String, String>> _translateAll(
    List<String> texts, {
    required String apiKey,
    required String target,
    void Function(String, double)? onProgress,
  }) async {
    final result = <String, String>{};
    final total = texts.length;

    for (var i = 0; i < total; i += _batchSize) {
      final batch = texts.skip(i).take(_batchSize).toList();
      final translated = await _chunk(batch, apiKey: apiKey, target: target);
      for (var j = 0; j < batch.length; j++) {
        result[batch[j]] = j < translated.length ? translated[j] : batch[j];
      }
      onProgress?.call(
        'Translating… (${(i + batch.length).clamp(0, total)}/$total)',
        (i + batch.length) / total,
      );
    }

    return result;
  }

  static Future<List<String>> _chunk(
    List<String> texts, {
    required String apiKey,
    required String target,
  }) async {
    final uri = Uri.parse('$_endpoint?key=$apiKey');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'q': texts, 'target': target, 'format': 'text'}),
    );

    if (response.statusCode != 200) {
      String detail;
      try {
        final body = jsonDecode(response.body) as Map;
        detail = (body['error']?['message'] as String?) ??
            response.body.substring(0, response.body.length.clamp(0, 200));
      } catch (_) {
        detail = response.body.substring(0, response.body.length.clamp(0, 200));
      }
      throw BimTranslationException(
        'Google Translate returned ${response.statusCode}: $detail',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final translations =
        (body['data']?['translations'] as List?) ?? [];
    return translations
        .map((t) => (t as Map<String, dynamic>)['translatedText'] as String? ?? '')
        .toList();
  }

  // ── Preview rebuild with translations ─────────────────────────────────────

  static CobiePreview _applyMap(
      CobiePreview p, Map<String, String> m) {
    String tr(String s) => m[s] ?? s;
    String? trOpt(String? s) => s == null ? null : (m[s] ?? s);

    return CobiePreview(
      warnings: p.warnings,
      spaces: p.spaces.map((s) => CobieSpaceDraft(
            docId: s.docId,
            isStorey: s.isStorey,
            name: tr(s.name),
            description: trOpt(s.description),
            floorName: s.floorName,
            elevation: s.elevation,
            globalId: s.globalId,
            grossArea: s.grossArea,
            usageType: s.usageType,
            parentDocId: s.parentDocId,
          )).toList(),
      equipment: p.equipment.map((e) => CobieEquipmentDraft(
            docId: e.docId,
            name: tr(e.name),
            equipmentId: e.equipmentId,
            type: e.type, // IFC category — keep untranslated (matches template library keys)
            typeName: (e.typeName.isNotEmpty && e.typeName != e.type)
                ? tr(e.typeName)
                : e.typeName,
            manufacturer: e.manufacturer,
            modelNumber: e.modelNumber,
            classification: e.classification,
            systemName: trOpt(e.systemName),
            spaceName: trOpt(e.spaceName),
            serialNumber: e.serialNumber,
            warrantyMonths: e.warrantyMonths,
            notes: e.notes.isEmpty ? e.notes : tr(e.notes),
            globalId: e.globalId,
            installationDate: e.installationDate,
            warrantyStart: e.warrantyStart,
            warrantyEnd: e.warrantyEnd,
            expectedLifeYears: e.expectedLifeYears,
            spaceDocId: e.spaceDocId,
          )).toList(),
      jobs: p.jobs.map((j) => CobieJobDraft(
            docId: j.docId,
            name: tr(j.name),
            category: tr(j.category),
            component: tr(j.component),
            intervention: tr(j.intervention),
            frequencyMonths: j.frequencyMonths,
            notes: trOpt(j.notes),
          )).toList(),
      systems: p.systems.map((s) => CobieMepSystemDraft(
            docId: s.docId,
            name: tr(s.name),
            category: trOpt(s.category),
            equipmentDocIds: s.equipmentDocIds,
          )).toList(),
      contacts: p.contacts, // contact names are proper nouns — don't translate
      spares: p.spares.map((s) => CobieSparesDraft(
            docId: s.docId,
            name: tr(s.name),
            typeName: trOpt(s.typeName),
            category: trOpt(s.category),
            partNumber: s.partNumber,
            supplier: s.supplier,
            description: trOpt(s.description),
            setNumber: s.setNumber,
          )).toList(),
    );
  }
}

class BimTranslationException implements Exception {
  final String message;
  const BimTranslationException(this.message);
  @override
  String toString() => 'BimTranslationException: $message';
}
