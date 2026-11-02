/// Pure Dart (no Flutter/Firebase imports) so it is easy to unit test.
///
/// Input: a COBie workbook already reduced to plain strings:
///   sheet name (lowercase) -> rows, each row a map of normalised header -> cell text.
/// Headers are normalised by the reader (lowercase, letters/digits only), e.g. "FloorName" -> "floorname".
///
/// Output: a [CobiePreview] to show on a review screen BEFORE anything is written.
///
/// [CobiePreview] and its drafts are also the shared review format for IFC imports (see
/// ifc_parser.dart), so both file types go through the same review screen and import service.
typedef CobieWorkbook = Map<String, List<Map<String, String>>>;

final RegExp _globalIdPattern = RegExp(r'^[0-9A-Za-z_$]{22}$');
final RegExp _uuidPattern = RegExp(
    r'^\{?[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}\}?$');

/// IFC GlobalId encoding alphabet (base-64, not standard base64url).
const _ifcBase64 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_\$';

/// Converts a 32-hex-char UUID (no braces/hyphens) to a 22-char IFC GlobalId.
String? _hexToIfcGuid(String hex) {
  try {
    var n = BigInt.parse(hex, radix: 16);
    final chars = List<String>.filled(22, '0');
    final base = BigInt.from(64);
    for (var i = 21; i >= 0; i--) {
      chars[i] = _ifcBase64[(n % base).toInt()];
      n ~/= base;
    }
    return chars.join();
  } catch (_) {
    return null;
  }
}

/// Validates and normalises an IFC GlobalId from any source format:
/// - 22-char base64 IFC format (standard): returned as-is.
/// - UUID format `{xxxxxxxx-xxxx-...}` (some COBie exporters): converted to IFC base64.
/// Returns null when the value cannot be recognised.
String? validIfcGlobalId(String raw) {
  final s = raw.trim();
  if (_globalIdPattern.hasMatch(s)) return s;
  if (_uuidPattern.hasMatch(s)) {
    final hex = s.replaceAll(RegExp(r'[{}\-]'), '').toLowerCase();
    return _hexToIfcGuid(hex);
  }
  return null;
}

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Deterministic Firestore document id, so re-importing a revised file updates the same
/// documents instead of duplicating them. Prefers the IFC GlobalId; falls back to the COBie name.
String bimDocId(String prefix, String? globalId, String name) {
  if (globalId != null) return 'bim_$globalId';
  final slug = _slug(name);
  return '${prefix}_${slug.isEmpty ? _stableHash(name) : slug}';
}

/// FNV-1a over UTF-16 code units. String.hashCode differs between the Dart VM and web builds, so it
/// can't be used for ids that must match when the same file is re-imported from another platform.
String _stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16);
}

class CobieSpaceDraft {
  final String docId;
  final bool isStorey;
  final String name;
  final String? description;
  final String? floorName; // spaces only
  final double? elevation; // storeys only
  final String? globalId;

  /// Gross floor area in m² from Qto_SpaceBaseQuantities or COBie Space.GrossArea.
  final double? grossArea;

  /// IFC IfcSpace PredefinedType or COBie Space.UsageType.
  final String? usageType;

  /// Exact storey doc id when the source states the link directly (IFC IfcRelAggregates).
  /// COBie leaves this null and the import service resolves [floorName] instead.
  final String? parentDocId;

  CobieSpaceDraft({
    required this.docId,
    required this.isStorey,
    required this.name,
    this.description,
    this.floorName,
    this.elevation,
    this.globalId,
    this.grossArea,
    this.usageType,
    this.parentDocId,
  });
}

class CobieEquipmentDraft {
  final String docId;
  final String name;
  final String equipmentId;
  final String type;
  final String typeName;
  final String? manufacturer;
  final String? modelNumber;
  final String? classification;
  final String? systemName;
  final String? spaceName;
  final String serialNumber;
  final int warrantyMonths;
  final String notes;
  final String? globalId;

  // Lifecycle dates: set when available from the source file.
  final DateTime? installationDate;
  final DateTime? warrantyStart;
  final DateTime? warrantyEnd;

  /// Expected service life in years (COBie Type.ExpectedLife or IFC Pset).
  final int? expectedLifeYears;

  /// Exact storey/room doc id when the source states the link directly
  /// (IFC IfcRelContainedInSpatialStructure). COBie leaves this null and [spaceName] is used.
  final String? spaceDocId;

  CobieEquipmentDraft({
    required this.docId,
    required this.name,
    required this.equipmentId,
    required this.type,
    required this.typeName,
    this.manufacturer,
    this.modelNumber,
    this.classification,
    this.systemName,
    this.spaceName,
    required this.serialNumber,
    required this.warrantyMonths,
    required this.notes,
    this.globalId,
    this.installationDate,
    this.warrantyStart,
    this.warrantyEnd,
    this.expectedLifeYears,
    this.spaceDocId,
  });
}

/// A COBie Job row: a recurring maintenance activity. Becomes a preventive_maintenance task.
class CobieJobDraft {
  final String docId;
  final String name;
  final String category;
  final String component; // COBie TypeName
  final String intervention;
  final int frequencyMonths;
  final String? notes;

  CobieJobDraft({
    required this.docId,
    required this.name,
    required this.category,
    required this.component,
    required this.intervention,
    required this.frequencyMonths,
    this.notes,
  });
}

/// An MEP system (HVAC circuit, electrical distribution circuit, plumbing loop, etc.).
/// Sourced from COBie System sheet or IFC IfcSystem/IfcDistributionSystem.
/// Stored in facilities/{facilityId}/bimSystems/{docId}.
class CobieMepSystemDraft {
  final String docId;
  final String name;

  /// IFC PredefinedType or COBie System.Category.
  final String? category;

  /// Doc ids of all [CobieEquipmentDraft]s assigned to this system.
  final List<String> equipmentDocIds;

  CobieMepSystemDraft({
    required this.docId,
    required this.name,
    this.category,
    required this.equipmentDocIds,
  });
}

/// A manufacturer or contractor contact from the COBie Contact sheet.
/// Stored in facilities/{facilityId}/bimContacts/{docId}.
class CobieContactDraft {
  final String docId;
  final String name;
  final String? company;
  final String? email;
  final String? phone;

  /// Category: Manufacturer, Installer, Contractor, Operator, Supplier, etc.
  final String? category;
  final String? description;

  CobieContactDraft({
    required this.docId,
    required this.name,
    this.company,
    this.email,
    this.phone,
    this.category,
    this.description,
  });
}

/// A spare part record from the COBie Spare/Resource sheet.
/// Stored in facilities/{facilityId}/bimSpares/{docId}.
class CobieSparesDraft {
  final String docId;
  final String name;

  /// COBie Type name this spare part belongs to.
  final String? typeName;
  final String? category;
  final String? partNumber;
  final String? supplier;
  final String? description;
  final int? setNumber;

  CobieSparesDraft({
    required this.docId,
    required this.name,
    this.typeName,
    this.category,
    this.partNumber,
    this.supplier,
    this.description,
    this.setNumber,
  });
}

class CobiePreview {
  final List<CobieSpaceDraft> spaces;
  final List<CobieEquipmentDraft> equipment;
  final List<CobieJobDraft> jobs;
  final List<CobieMepSystemDraft> systems;
  final List<CobieContactDraft> contacts;
  final List<CobieSparesDraft> spares;
  final List<String> warnings;

  CobiePreview({
    required this.spaces,
    required this.equipment,
    this.jobs = const [],
    this.systems = const [],
    this.contacts = const [],
    this.spares = const [],
    required this.warnings,
  });

  int get storeyCount => spaces.where((s) => s.isStorey).length;
  int get roomCount => spaces.where((s) => !s.isStorey).length;
  bool get isEmpty => spaces.isEmpty && equipment.isEmpty && jobs.isEmpty;
}

class _TypeInfo {
  final String name;
  final String? manufacturer;
  final String? modelNumber;
  final String? category;
  final int warrantyMonths;
  final int? expectedLifeYears;
  final DateTime? warrantyStart;
  final DateTime? warrantyEnd;
  _TypeInfo(this.name, this.manufacturer, this.modelNumber, this.category,
      this.warrantyMonths, this.expectedLifeYears, this.warrantyStart, this.warrantyEnd);
}

class CobieParser {
  static String _v(Map<String, String> row, String key) => (row[key] ?? '').trim();
  static String? _opt(Map<String, String> row, String key) {
    final s = _v(row, key);
    return s.isEmpty ? null : s;
  }

  static List<Map<String, String>> _sheet(CobieWorkbook wb, String name) => wb[name] ?? const [];

  static int _warrantyMonths(Map<String, String> row) {
    final n = double.tryParse(_v(row, 'warrantydurationparts'));
    if (n == null || n <= 0) return 0;
    final unit = _v(row, 'warrantydurationunit').toLowerCase();
    if (unit.contains('year')) return (n * 12).round();
    if (unit.contains('month')) return n.round();
    if (unit.contains('week')) return (n / 4.345).round();
    if (unit.contains('day')) return (n / 30).round();
    return 0; // unit missing/unknown: don't guess
  }

  /// Converts COBie Frequency + FrequencyUnit to whole months. Returns 0 when it can't be determined.
  static int _frequencyMonths(Map<String, String> row) {
    final n = double.tryParse(_v(row, 'frequency'));
    if (n == null || n <= 0) return 0;
    final unit = _v(row, 'frequencyunit').toLowerCase();
    double months;
    if (unit.contains('year')) {
      months = n * 12;
    } else if (unit.contains('month')) {
      months = n;
    } else if (unit.contains('week')) {
      months = n / 4.345;
    } else if (unit.contains('day')) {
      months = n / 30;
    } else {
      return 0; // hours/minutes/unknown: not a calendar PM interval
    }
    final rounded = months.round();
    return rounded < 1 ? 1 : rounded;
  }

  /// Parses an ISO 8601 date string to DateTime (UTC midnight). Returns null for empty or unparseable.
  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    // ISO 8601 date or datetime
    final dt = DateTime.tryParse(s);
    if (dt != null) return DateTime.utc(dt.year, dt.month, dt.day);
    // Some exporters write DD/MM/YYYY or MM/DD/YYYY - try common patterns
    final parts = s.split(RegExp(r'[/\-.]'));
    if (parts.length == 3) {
      final ints = parts.map(int.tryParse).toList();
      if (ints.every((v) => v != null)) {
        // Heuristic: if first part > 31 it's a year
        final y = ints[0]! > 31 ? ints[0]! : ints[2]!;
        final m = ints[1]!;
        final d = ints[0]! > 31 ? ints[2]! : ints[0]!;
        if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          return DateTime.tryParse('$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}');
        }
      }
    }
    return null;
  }

  static int? _expectedLifeYears(Map<String, String> row) {
    final n = double.tryParse(_v(row, 'expectedlife'));
    if (n == null || n <= 0) return null;
    final unit = _v(row, 'durationunit').toLowerCase();
    if (unit.contains('year') || unit.isEmpty) return n.round();
    if (unit.contains('month')) return (n / 12).round();
    if (unit.contains('week')) return (n / 52).round();
    if (unit.contains('day')) return (n / 365).round();
    return n.round();
  }

  static CobiePreview parse(CobieWorkbook wb) {
    final warnings = <String>[];

    for (final required in const ['floor', 'space', 'component']) {
      if (!wb.containsKey(required)) {
        warnings.add('Sheet "${required[0].toUpperCase()}${required.substring(1)}" was not found in the workbook.');
      }
    }

    final spaces = <CobieSpaceDraft>[];
    final seenSpaceIds = <String>{};
    final floorNames = <String>{};

    // Floors -> storeys
    for (final row in _sheet(wb, 'floor')) {
      final name = _v(row, 'name');
      if (name.isEmpty) {
        warnings.add('A Floor row has no Name and was skipped.');
        continue;
      }
      final gid = validIfcGlobalId(_v(row, 'extidentifier'));
      final id = bimDocId('floor', gid, name);
      if (floorNames.contains(name.toLowerCase()) || !seenSpaceIds.add(id)) {
        warnings.add('Duplicate Floor "$name" was skipped.');
        continue;
      }
      floorNames.add(name.toLowerCase());
      spaces.add(CobieSpaceDraft(
        docId: id,
        isStorey: true,
        name: name,
        description: _opt(row, 'description'),
        elevation: double.tryParse(_v(row, 'elevation')),
        globalId: gid,
      ));
    }

    // Spaces -> rooms
    final spaceNames = <String>{};
    for (final row in _sheet(wb, 'space')) {
      final name = _v(row, 'name');
      if (name.isEmpty) {
        warnings.add('A Space row has no Name and was skipped.');
        continue;
      }
      final floorName = _opt(row, 'floorname');
      if (floorName != null && !floorNames.contains(floorName.toLowerCase())) {
        warnings.add('Space "$name" refers to Floor "$floorName", which is not in the Floor sheet.');
      }
      final gid = validIfcGlobalId(_v(row, 'extidentifier'));
      final id = bimDocId('space', gid, name);
      if (spaceNames.contains(name.toLowerCase()) || !seenSpaceIds.add(id)) {
        warnings.add('Duplicate Space "$name" was skipped.');
        continue;
      }
      spaceNames.add(name.toLowerCase());

      // Area: GrossArea column (m²). Some exporters use 'grossarea', others 'netarea'.
      final grossAreaStr = _opt(row, 'grossarea') ?? _opt(row, 'area');
      final grossArea = grossAreaStr == null ? null : double.tryParse(grossAreaStr);

      spaces.add(CobieSpaceDraft(
        docId: id,
        isStorey: false,
        name: name,
        description: _opt(row, 'description'),
        floorName: floorName,
        globalId: gid,
        grossArea: grossArea,
        usageType: _opt(row, 'usagetype') ?? _opt(row, 'roomtype'),
      ));
    }

    // Types
    final types = <String, _TypeInfo>{};
    for (final row in _sheet(wb, 'type')) {
      final name = _v(row, 'name');
      if (name.isEmpty) continue;
      types[name.toLowerCase()] = _TypeInfo(
        name,
        _opt(row, 'manufacturer'),
        _opt(row, 'modelnumber'),
        _opt(row, 'category'),
        _warrantyMonths(row),
        _expectedLifeYears(row),
        _parseDate(_opt(row, 'warrantystartdate')),
        _parseDate(_opt(row, 'warrantyenddate')),
      );
    }

    // Systems: component name -> system info
    final systemNameOf = <String, String>{}; // component name -> system name
    final systemCategoryOf = <String, String>{}; // system name -> category
    final systemComponents = <String, List<String>>{}; // system name -> component doc ids (filled after components)
    for (final row in _sheet(wb, 'system')) {
      final sysName = _v(row, 'name');
      if (sysName.isEmpty) continue;
      final cat = _opt(row, 'category');
      if (cat != null) systemCategoryOf[sysName] = cat;
      for (final c in _v(row, 'componentnames').split(',')) {
        final key = c.trim().toLowerCase();
        if (key.isNotEmpty) systemNameOf.putIfAbsent(key, () => sysName);
      }
    }

    // Components -> equipment
    final equipment = <CobieEquipmentDraft>[];
    final seenEquipmentIds = <String>{};
    final seenComponentNames = <String>{}; // COBie names are unique per sheet
    for (final row in _sheet(wb, 'component')) {
      final name = _v(row, 'name');
      if (name.isEmpty) {
        warnings.add('A Component row has no Name and was skipped.');
        continue;
      }
      final typeName = _v(row, 'typename');
      final info = types[typeName.toLowerCase()];
      if (typeName.isNotEmpty && info == null) {
        warnings.add('Component "$name" refers to Type "$typeName", which is not in the Type sheet.');
      }
      final spaceName = _opt(row, 'space');
      if (spaceName != null && !spaceNames.contains(spaceName.toLowerCase())) {
        warnings.add('Component "$name" refers to Space "$spaceName", which is not in the Space sheet.');
      }
      final gid = validIfcGlobalId(_v(row, 'extidentifier'));
      final id = bimDocId('cobie', gid, name);
      if (!seenComponentNames.add(name.toLowerCase()) || !seenEquipmentIds.add(id)) {
        warnings.add('Duplicate Component "$name" was skipped.');
        continue;
      }
      final tag = _v(row, 'tagnumber');
      final assetId = _v(row, 'assetidentifier');

      final sysName = systemNameOf[name.toLowerCase()];
      if (sysName != null) (systemComponents[sysName] ??= []).add(id);

      // Lifecycle dates: Component sheet columns take priority over Type sheet
      final installDate = _parseDate(_opt(row, 'installationdate')) ??
          _parseDate(_opt(row, 'installeddate'));
      final wStart = _parseDate(_opt(row, 'warrantystartdate')) ?? info?.warrantyStart;
      final wEnd = _parseDate(_opt(row, 'warrantyenddate')) ?? info?.warrantyEnd;

      equipment.add(CobieEquipmentDraft(
        docId: id,
        name: name,
        equipmentId: tag.isNotEmpty ? tag : (assetId.isNotEmpty ? assetId : name),
        type: typeName.isNotEmpty ? typeName : 'Imported',
        typeName: typeName,
        manufacturer: info?.manufacturer,
        modelNumber: info?.modelNumber,
        classification: info?.category,
        systemName: sysName,
        spaceName: spaceName,
        serialNumber: _v(row, 'serialnumber'),
        warrantyMonths: info?.warrantyMonths ?? 0,
        notes: _v(row, 'description'),
        globalId: gid,
        installationDate: installDate,
        warrantyStart: wStart,
        warrantyEnd: wEnd,
        expectedLifeYears: info?.expectedLifeYears,
      ));
    }

    // Systems -> CobieMepSystemDraft
    final systems = <CobieMepSystemDraft>[];
    final seenSystemIds = <String>{};
    for (final row in _sheet(wb, 'system')) {
      final name = _v(row, 'name');
      if (name.isEmpty) continue;
      final id = bimDocId('system', null, name);
      if (!seenSystemIds.add(id)) continue;
      systems.add(CobieMepSystemDraft(
        docId: id,
        name: name,
        category: _opt(row, 'category'),
        equipmentDocIds: systemComponents[name] ?? const [],
      ));
    }

    // Jobs -> preventive maintenance tasks
    final jobs = <CobieJobDraft>[];
    final seenJobIds = <String>{};
    for (final row in _sheet(wb, 'job')) {
      final name = _v(row, 'name');
      if (name.isEmpty) {
        warnings.add('A Job row has no Name and was skipped.');
        continue;
      }
      final typeName = _v(row, 'typename');
      if (typeName.isNotEmpty && !types.containsKey(typeName.toLowerCase())) {
        warnings.add('Job "$name" refers to Type "$typeName", which is not in the Type sheet.');
      }
      final months = _frequencyMonths(row);
      if (months == 0) {
        warnings.add('Job "$name" has no usable Frequency/FrequencyUnit and was skipped.');
        continue;
      }
      final id = bimDocId('cobie_job', null, '$typeName $name');
      if (!seenJobIds.add(id)) {
        warnings.add('Duplicate Job "$name" for Type "$typeName" was skipped.');
        continue;
      }
      final category = _v(row, 'category');
      final desc = _v(row, 'description');
      jobs.add(CobieJobDraft(
        docId: id,
        name: name,
        category: category.isNotEmpty ? category : 'COBie',
        component: typeName.isNotEmpty ? typeName : 'General',
        intervention: desc.isNotEmpty ? '$name: $desc' : name,
        frequencyMonths: months,
        notes: desc.isEmpty ? null : desc,
      ));
    }

    // Contacts (COBie Contact sheet)
    final contacts = <CobieContactDraft>[];
    final seenContactIds = <String>{};
    for (final row in _sheet(wb, 'contact')) {
      final name = _opt(row, 'firstname') != null || _opt(row, 'lastname') != null
          ? '${_v(row, 'firstname')} ${_v(row, 'lastname')}'.trim()
          : _opt(row, 'name') ?? _opt(row, 'email') ?? '';
      if (name.isEmpty) continue;
      final id = bimDocId('contact', null, name);
      if (!seenContactIds.add(id)) continue;
      contacts.add(CobieContactDraft(
        docId: id,
        name: name,
        company: _opt(row, 'company') ?? _opt(row, 'organization'),
        email: _opt(row, 'email'),
        phone: _opt(row, 'phone') ?? _opt(row, 'phonenumber'),
        category: _opt(row, 'category') ?? _opt(row, 'role'),
        description: _opt(row, 'description'),
      ));
    }

    // Spares / Resources (COBie Spare sheet — sometimes also called Resource)
    final spares = <CobieSparesDraft>[];
    final seenSpareIds = <String>{};
    for (final sheetName in const ['spare', 'resource']) {
      for (final row in _sheet(wb, sheetName)) {
        final name = _v(row, 'name');
        if (name.isEmpty) continue;
        final typeName = _opt(row, 'typename') ?? _opt(row, 'type');
        final id = bimDocId('spare', null, '${typeName ?? ''}/$name');
        if (!seenSpareIds.add(id)) continue;
        final setNumStr = _opt(row, 'setnumber');
        spares.add(CobieSparesDraft(
          docId: id,
          name: name,
          typeName: typeName,
          category: _opt(row, 'category'),
          partNumber: _opt(row, 'partnumber') ?? _opt(row, 'articlenumber'),
          supplier: _opt(row, 'suppliers') ?? _opt(row, 'supplier'),
          description: _opt(row, 'description'),
          setNumber: setNumStr == null ? null : int.tryParse(setNumStr),
        ));
      }
    }

    final withoutGuid = equipment.where((e) => e.globalId == null).length;
    if (equipment.isNotEmpty && withoutGuid > 0) {
      warnings.add('$withoutGuid of ${equipment.length} components have no valid IFC GlobalId in ExtIdentifier. '
          'They will be matched by name on re-import.');
    }

    return CobiePreview(
      spaces: spaces,
      equipment: equipment,
      jobs: jobs,
      systems: systems,
      contacts: contacts,
      spares: spares,
      warnings: warnings,
    );
  }
}
