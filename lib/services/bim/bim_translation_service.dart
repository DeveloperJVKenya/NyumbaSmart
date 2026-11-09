import 'package:cmms/services/bim/cobie_parser.dart';
import 'package:cmms/services/bim/italian_bim_glossary.dart';

/// Translates a [CobiePreview] from Italian to English using the built-in
/// [ItalianBimGlossary].  No network calls, no API key required.
///
/// Fields translated:
///   • Space names and descriptions
///   • Equipment names, typeNames, systemNames, notes
///   • Job names, categories, components, interventions, notes
///   • System names and categories
///   • Spare part names, typeNames, descriptions
///
/// Fields left untranslated:
///   • Equipment `type` (IFC category — matches PM template library keys)
///   • Contact names (proper nouns)
///   • Serial numbers, model numbers, part numbers
class BimTranslationService {
  BimTranslationService._();

  /// Returns a new [CobiePreview] with Italian strings translated to English.
  /// Progress is reported via [onProgress] (0.0 → 1.0).
  static Future<CobiePreview> translateAndApply(
    CobiePreview preview, {
    void Function(String stage, double fraction)? onProgress,
  }) async {
    // Translation is synchronous (pure local map lookups), but we keep
    // async so callers can await it and the signature is forward-compatible
    // if a network fallback is added later.
    onProgress?.call('Translating names…', 0.0);
    final result = _applyGlossary(preview);
    onProgress?.call('Translation complete', 1.0);
    return result;
  }

  // ── Core rebuild ──────────────────────────────────────────────────────────

  static CobiePreview _applyGlossary(CobiePreview p) {
    final tr = ItalianBimGlossary.translate;
    final trOpt = ItalianBimGlossary.translateOrNull;

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
            // `type` is an IFC category code used as PM template key — keep as-is
            type: e.type,
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
      contacts: p.contacts, // proper nouns — do not translate
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
