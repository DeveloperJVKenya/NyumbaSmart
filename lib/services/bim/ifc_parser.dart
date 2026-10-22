import 'dart:convert' show latin1, utf8;
import 'dart:typed_data';

import 'package:cmms/services/bim/cobie_parser.dart';

/// Pure Dart (no Flutter/Firebase imports) so it is easy to unit test and can run in an isolate
/// via `compute(parseIfcBytes, bytes)`.
///
/// Reads the *data* side of an IFC (ISO 10303-21 / STEP) file — storeys, spaces and maintainable
/// equipment with their manufacturer, model, serial, system and classification — and produces the
/// same [CobiePreview] the COBie importer does, so both go through one review screen and one import
/// service. Geometry is skipped entirely; only the handful of entity types listed below are decoded.
///
/// Supports IFC2X3, IFC4 and IFC4X3. In IFC2X3 equipment is exported as generic classes
/// (IfcFlowTerminal, IfcFlowMovingDevice, …); the specific kind is then taken from the type object
/// (IfcPumpType, IfcAirTerminalType, …) assigned through IfcRelDefinesByType.
class IfcParseResult {
  final CobiePreview preview;

  /// 'IFC2X3' | 'IFC4' | 'IFC4X3' (as written in FILE_SCHEMA), or null if the header had none.
  final String? schemaVersion;

  /// IfcBuilding name, when present. Shown on the review screen so staff can confirm the file.
  final String? buildingName;

  IfcParseResult({required this.preview, this.schemaVersion, this.buildingName});
}

/// Top-level so it can be passed to `compute()`.
IfcParseResult parseIfcBytes(Uint8List bytes) => IfcParser.parse(bytes);

/// IFC occurrence class -> (friendly name, CMMS equipment category).
/// Categories match the Type options already used by the equipment screen.
const Map<String, (String, String)> _equipmentClasses = {
  // HVAC
  'IFCAIRTERMINAL': ('Air Terminal', 'HVAC'),
  'IFCAIRTERMINALBOX': ('Air Terminal Box', 'HVAC'),
  'IFCAIRTOAIRHEATRECOVERY': ('Heat Recovery Unit', 'HVAC'),
  'IFCBOILER': ('Boiler', 'HVAC'),
  'IFCBURNER': ('Burner', 'HVAC'),
  'IFCCHILLER': ('Chiller', 'HVAC'),
  'IFCCOIL': ('Coil', 'HVAC'),
  'IFCCOMPRESSOR': ('Compressor', 'HVAC'),
  'IFCCONDENSER': ('Condenser', 'HVAC'),
  'IFCCOOLEDBEAM': ('Chilled Beam', 'HVAC'),
  'IFCCOOLINGTOWER': ('Cooling Tower', 'HVAC'),
  'IFCDAMPER': ('Damper', 'HVAC'),
  'IFCEVAPORATIVECOOLER': ('Evaporative Cooler', 'HVAC'),
  'IFCEVAPORATOR': ('Evaporator', 'HVAC'),
  'IFCFAN': ('Fan', 'HVAC'),
  'IFCFILTER': ('Filter', 'HVAC'),
  'IFCHEATEXCHANGER': ('Heat Exchanger', 'HVAC'),
  'IFCHUMIDIFIER': ('Humidifier', 'HVAC'),
  'IFCSPACEHEATER': ('Space Heater', 'HVAC'),
  'IFCTUBEBUNDLE': ('Tube Bundle', 'HVAC'),
  'IFCUNITARYEQUIPMENT': ('Unitary Equipment', 'HVAC'),
  // Plumbing
  'IFCSANITARYTERMINAL': ('Sanitary Fixture', 'Plumbing'),
  'IFCWASTETERMINAL': ('Waste Terminal', 'Plumbing'),
  'IFCSTACKTERMINAL': ('Stack Terminal', 'Plumbing'),
  'IFCINTERCEPTOR': ('Interceptor', 'Plumbing'),
  'IFCTANK': ('Tank', 'Plumbing'),
  'IFCVALVE': ('Valve', 'Plumbing'),
  'IFCFLOWMETER': ('Flow Meter', 'Plumbing'),
  // Mechanical
  'IFCPUMP': ('Pump', 'Mechanical'),
  'IFCENGINE': ('Engine', 'Mechanical'),
  'IFCTRANSPORTELEMENT': ('Lift / Escalator', 'Mechanical'),
  'IFCMEDICALDEVICE': ('Medical Device', 'Mechanical'),
  'IFCACTUATOR': ('Actuator', 'Mechanical'),
  'IFCCONTROLLER': ('Controller', 'Mechanical'),
  'IFCUNITARYCONTROLELEMENT': ('Control Panel', 'Mechanical'),
  'IFCFLOWINSTRUMENT': ('Instrument', 'Mechanical'),
  'IFCSENSOR': ('Sensor', 'Mechanical'), // smoke/heat/gas sensors are moved to Safety below
  // Electrical
  'IFCELECTRICAPPLIANCE': ('Electric Appliance', 'Electrical'),
  'IFCELECTRICDISTRIBUTIONBOARD': ('Distribution Board', 'Electrical'),
  'IFCELECTRICDISTRIBUTIONPOINT': ('Distribution Point', 'Electrical'),
  'IFCELECTRICFLOWSTORAGEDEVICE': ('Battery / UPS', 'Electrical'),
  'IFCELECTRICGENERATOR': ('Generator', 'Electrical'),
  'IFCELECTRICMOTOR': ('Electric Motor', 'Electrical'),
  'IFCELECTRICTIMECONTROL': ('Time Control', 'Electrical'),
  'IFCLAMP': ('Lamp', 'Electrical'),
  'IFCLIGHTFIXTURE': ('Light Fixture', 'Electrical'),
  'IFCOUTLET': ('Outlet', 'Electrical'),
  'IFCPROTECTIVEDEVICE': ('Protective Device', 'Electrical'),
  'IFCPROTECTIVEDEVICETRIPPINGUNIT': ('Tripping Unit', 'Electrical'),
  'IFCSWITCHINGDEVICE': ('Switch', 'Electrical'),
  'IFCTRANSFORMER': ('Transformer', 'Electrical'),
  'IFCSOLARDEVICE': ('Solar Device', 'Electrical'),
  'IFCMOTORCONNECTION': ('Motor Connection', 'Electrical'),
  // Safety
  'IFCALARM': ('Alarm', 'Safety'),
  'IFCFIRESUPPRESSIONTERMINAL': ('Fire Suppression Terminal', 'Safety'),
  // IT
  'IFCCOMMUNICATIONSAPPLIANCE': ('Communications Appliance', 'IT Equipment'),
  'IFCAUDIOVISUALAPPLIANCE': ('Audio-Visual Appliance', 'IT Equipment'),
  // IFC2X3 generic occurrence classes. The specific kind comes from the assigned type object.
  'IFCFLOWTERMINAL': ('Flow Terminal', 'Mechanical'),
  'IFCFLOWCONTROLLER': ('Flow Controller', 'Mechanical'),
  'IFCFLOWMOVINGDEVICE': ('Flow Moving Device', 'Mechanical'),
  'IFCFLOWSTORAGEDEVICE': ('Storage Device', 'Mechanical'),
  'IFCFLOWTREATMENTDEVICE': ('Treatment Device', 'Mechanical'),
  'IFCENERGYCONVERSIONDEVICE': ('Energy Conversion Device', 'Mechanical'),
  'IFCDISTRIBUTIONCONTROLELEMENT': ('Control Element', 'Mechanical'),
};

/// IFC2X3-style generic classes whose specific kind is taken from the assigned type object.
const Set<String> _genericClasses = {
  'IFCFLOWTERMINAL',
  'IFCFLOWCONTROLLER',
  'IFCFLOWMOVINGDEVICE',
  'IFCFLOWSTORAGEDEVICE',
  'IFCFLOWTREATMENTDEVICE',
  'IFCENERGYCONVERSIONDEVICE',
  'IFCDISTRIBUTIONCONTROLELEMENT',
};

const Set<String> _systemClasses = {
  'IFCSYSTEM',
  'IFCDISTRIBUTIONSYSTEM',
  'IFCDISTRIBUTIONCIRCUIT',
  'IFCBUILDINGSYSTEM',
};

const Set<String> _otherKeptClasses = {
  'IFCBUILDING',
  'IFCBUILDINGSTOREY',
  'IFCSPACE',
  'IFCRELAGGREGATES',
  'IFCRELCONTAINEDINSPATIALSTRUCTURE',
  'IFCRELREFERENCEDINSPATIALSTRUCTURE',
  'IFCRELDEFINESBYTYPE',
  'IFCRELDEFINESBYPROPERTIES',
  'IFCPROPERTYSET',
  'IFCPROPERTYSINGLEVALUE',
  'IFCRELASSOCIATESCLASSIFICATION',
  'IFCCLASSIFICATIONREFERENCE',
  'IFCRELASSIGNSTOGROUP',
  'IFCSIUNIT',
  'IFCCONVERSIONBASEDUNIT',
};

class _Ref {
  const _Ref(this.id);
  final int id;
}

class _Enum {
  const _Enum(this.value);
  final String value;
}

class _Entity {
  _Entity(this.type, this.args);
  final String type;
  final List<Object?> args;

  Object? at(int i) => i < args.length ? args[i] : null;

  String? str(int i) {
    final v = at(i);
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  int? ref(int i) {
    final v = at(i);
    return v is _Ref ? v.id : null;
  }

  List<int> refs(int i) {
    final v = at(i);
    if (v is _Ref) return [v.id];
    if (v is! List) return const [];
    return [for (final e in v) if (e is _Ref) e.id];
  }

  String? enumValue(int i) {
    final v = at(i);
    return v is _Enum ? v.value : null;
  }

  double? number(int i) {
    final v = at(i);
    return v is num ? v.toDouble() : null;
  }
}

class IfcParser {
  static IfcParseResult parse(Uint8List bytes) {
    final warnings = <String>[];
    final entities = <int, _Entity>{};
    String? schema;
    var failed = 0;

    _forEachStatement(bytes, (start, end) {
      var i = _skipWs(bytes, start, end);
      if (i >= end) return;
      final first = bytes[i];

      if (first == 0x23 /* # */) {
        i++;
        var id = 0;
        while (i < end && bytes[i] >= 0x30 && bytes[i] <= 0x39) {
          id = id * 10 + (bytes[i] - 0x30);
          i++;
        }
        i = _skipWs(bytes, i, end);
        if (i >= end || bytes[i] != 0x3D /* = */) return;
        i = _skipWs(bytes, i + 1, end);
        final nameStart = i;
        while (i < end && _isIdentChar(bytes[i])) {
          i++;
        }
        final type = String.fromCharCodes(bytes, nameStart, i).toUpperCase();
        if (!_keep(type)) return;
        i = _skipWs(bytes, i, end);
        if (i >= end || bytes[i] != 0x28 /* ( */) return;
        try {
          final text = _decode(bytes, i, end);
          entities[id] = _Entity(type, _ArgParser(text).parseList());
        } catch (_) {
          failed++;
        }
      } else if (first == 0x46 /* F */ && schema == null) {
        final text = _decode(bytes, i, end);
        if (text.startsWith('FILE_SCHEMA')) {
          schema = RegExp(r"'(IFC[0-9A-Z_]*)'", caseSensitive: false).firstMatch(text)?.group(1)?.toUpperCase();
        }
      }
    });

    if (schema == null) {
      warnings.add('The file header has no FILE_SCHEMA. Is this an IFC (.ifc) file?');
    } else if (!schema!.startsWith('IFC2X3') && !schema!.startsWith('IFC4')) {
      warnings.add('Schema $schema is not one of IFC2X3 / IFC4 / IFC4X3; some data may be missed.');
    }
    if (failed > 0) {
      warnings.add('$failed entities could not be read and were skipped.');
    }

    return _build(entities, schema, warnings);
  }

  static bool _keep(String type) =>
      _equipmentClasses.containsKey(type) ||
      _otherKeptClasses.contains(type) ||
      _systemClasses.contains(type) ||
      // Type objects (IfcPumpType, IfcFlowTerminalType, …) carry the type name and type-level psets.
      (type.endsWith('TYPE') && !type.startsWith('IFCREL'));

  static IfcParseResult _build(Map<int, _Entity> e, String? schema, List<String> warnings) {
    Iterable<MapEntry<int, _Entity>> ofType(String t) => e.entries.where((x) => x.value.type == t);

    // ---- Units: storey elevations are stored in metres ----
    var lengthScale = 1.0;
    for (final u in e.values) {
      if (u.type == 'IFCSIUNIT' && u.enumValue(1) == 'LENGTHUNIT') {
        lengthScale = switch (u.enumValue(2)) {
          'MILLI' => 0.001,
          'CENTI' => 0.01,
          'DECI' => 0.1,
          'KILO' => 1000.0,
          _ => 1.0,
        };
        break;
      }
      if (u.type == 'IFCCONVERSIONBASEDUNIT' && u.enumValue(1) == 'LENGTHUNIT') {
        final n = (u.str(2) ?? '').toUpperCase();
        if (n.contains('FOOT') || n.contains('FEET')) lengthScale = 0.3048;
        if (n.contains('INCH')) lengthScale = 0.0254;
        break;
      }
    }

    // ---- Relationships ----
    final aggregateParent = <int, int>{}; // child -> parent
    for (final r in ofType('IFCRELAGGREGATES')) {
      final parent = r.value.ref(4);
      if (parent == null) continue;
      for (final c in r.value.refs(5)) {
        aggregateParent[c] = parent;
      }
    }

    final containedIn = <int, int>{}; // element -> storey/space
    for (final r in ofType('IFCRELCONTAINEDINSPATIALSTRUCTURE')) {
      final structure = r.value.ref(5);
      if (structure == null) continue;
      for (final c in r.value.refs(4)) {
        containedIn[c] = structure;
      }
    }
    // Some exporters contain equipment in the storey and *reference* it in the room it serves.
    // A room is the more useful location, so a space reference wins over a storey containment.
    for (final r in ofType('IFCRELREFERENCEDINSPATIALSTRUCTURE')) {
      final structure = r.value.ref(5);
      if (structure == null || e[structure]?.type != 'IFCSPACE') continue;
      for (final c in r.value.refs(4)) {
        if (e[containedIn[c]]?.type != 'IFCSPACE') containedIn[c] = structure;
      }
    }

    final typeOf = <int, int>{}; // occurrence -> type object
    for (final r in ofType('IFCRELDEFINESBYTYPE')) {
      final t = r.value.ref(5);
      if (t == null) continue;
      for (final c in r.value.refs(4)) {
        typeOf[c] = t;
      }
    }

    final psetsOf = <int, List<int>>{}; // object -> property sets
    for (final r in ofType('IFCRELDEFINESBYPROPERTIES')) {
      final p = r.value.ref(5);
      if (p == null) continue;
      for (final c in r.value.refs(4)) {
        (psetsOf[c] ??= []).add(p);
      }
    }

    final classificationOf = <int, String>{};
    for (final r in ofType('IFCRELASSOCIATESCLASSIFICATION')) {
      final ref = e[r.value.ref(5)];
      if (ref == null || ref.type != 'IFCCLASSIFICATIONREFERENCE') continue;
      // IFC2X3: (Location, ItemReference, Name, …)   IFC4: (Location, Identification, Name, …)
      final label = [ref.str(1), ref.str(2)].whereType<String>().join(' ');
      if (label.isEmpty) continue;
      for (final c in r.value.refs(4)) {
        classificationOf.putIfAbsent(c, () => label);
      }
    }

    final systemOf = <int, String>{};
    for (final r in ofType('IFCRELASSIGNSTOGROUP')) {
      final group = e[r.value.ref(6)];
      if (group == null || !_systemClasses.contains(group.type)) continue;
      final name = group.str(2);
      if (name == null) continue;
      for (final c in r.value.refs(4)) {
        systemOf.putIfAbsent(c, () => name);
      }
    }

    // Property lookup: lower-case property name -> value, per property set.
    final psetCache = <int, Map<String, String>>{};
    Map<String, String> pset(int id) => psetCache.putIfAbsent(id, () {
          final ps = e[id];
          final out = <String, String>{};
          if (ps == null || ps.type != 'IFCPROPERTYSET') return out;
          for (final pid in ps.refs(4)) {
            final p = e[pid];
            if (p == null || p.type != 'IFCPROPERTYSINGLEVALUE') continue;
            final name = p.str(0);
            final value = _valueText(p.at(2));
            if (name != null && value != null) out[name.toLowerCase()] = value;
          }
          return out;
        });

    String? prop(int element, List<String> names) {
      final typeId = typeOf[element];
      final sets = <int>[
        ...?psetsOf[element],
        ...?e[typeId]?.refs(5), // IfcTypeObject.HasPropertySets
        ...?psetsOf[typeId],
      ];
      for (final n in names) {
        for (final s in sets) {
          final v = pset(s)[n];
          if (v != null) return v;
        }
      }
      return null;
    }

    // ---- Spatial structure ----
    final spaces = <CobieSpaceDraft>[];
    final docIdOf = <int, String>{}; // IFC id -> Firestore doc id (storeys + spaces)
    final nameOf = <int, String>{};
    final seenSpaceDocIds = <String>{};

    final storeys = ofType('IFCBUILDINGSTOREY').toList()
      ..sort((a, b) => (a.value.number(9) ?? 0).compareTo(b.value.number(9) ?? 0));
    for (final s in storeys) {
      final ent = s.value;
      final name = ent.str(2) ?? ent.str(7) ?? 'Storey #${s.key}';
      final gid = validIfcGlobalId(ent.str(0) ?? '');
      final docId = bimDocId('floor', gid, name);
      if (!seenSpaceDocIds.add(docId)) continue;
      docIdOf[s.key] = docId;
      nameOf[s.key] = name;
      final longName = ent.str(7);
      final elevation = ent.number(9);
      spaces.add(CobieSpaceDraft(
        docId: docId,
        isStorey: true,
        name: name,
        description: (longName != null && longName != name) ? longName : ent.str(3),
        elevation: elevation == null ? null : _round(elevation * lengthScale),
        globalId: gid,
      ));
    }

    for (final s in ofType('IFCSPACE')) {
      final ent = s.value;
      final longName = ent.str(7);
      final name = ent.str(2) ?? longName ?? 'Space #${s.key}';
      final gid = validIfcGlobalId(ent.str(0) ?? '');
      final docId = bimDocId('space', gid, name);
      if (!seenSpaceDocIds.add(docId)) continue;
      docIdOf[s.key] = docId;
      nameOf[s.key] = name;

      // Walk up IfcRelAggregates to the storey (spaces can be nested in zones/other spaces).
      int? parent = aggregateParent[s.key];
      var guard = 0;
      while (parent != null && e[parent]?.type != 'IFCBUILDINGSTOREY' && guard++ < 8) {
        parent = aggregateParent[parent];
      }
      final storeyId = (parent != null && e[parent]?.type == 'IFCBUILDINGSTOREY') ? parent : null;

      spaces.add(CobieSpaceDraft(
        docId: docId,
        isStorey: false,
        name: name,
        description: (longName != null && longName != name) ? longName : ent.str(3),
        floorName: storeyId == null ? null : nameOf[storeyId],
        parentDocId: storeyId == null ? null : docIdOf[storeyId],
        globalId: gid,
      ));
    }

    // ---- Equipment ----
    final equipment = <CobieEquipmentDraft>[];
    final seenEquipmentIds = <String>{};
    var withoutLocation = 0;

    for (final x in e.entries) {
      final cls = _equipmentClasses[x.value.type];
      if (cls == null) continue;
      final ent = x.value;
      final id = x.key;

      // The type object refines generic IFC2X3 classes: IfcFlowMovingDevice + IfcPumpType -> Pump.
      final typeEnt = typeOf[id] == null ? null : e[typeOf[id]!];
      var (friendly, category) = cls;
      final fromType = typeEnt == null ? null : _equipmentClasses[typeEnt.type.replaceFirst(RegExp(r'TYPE$'), '')];
      if (fromType != null && _genericClasses.contains(ent.type)) {
        (friendly, category) = fromType;
      }
      final predefined = (ent.enumValue(8) ?? typeEnt?.enumValue(9) ?? '').toUpperCase();
      if (friendly == 'Sensor' && RegExp(r'SMOKE|HEAT|FIRE|GAS|FLAME|^CO2?SENSOR$').hasMatch(predefined)) {
        category = 'Safety';
      }

      final gid = validIfcGlobalId(ent.str(0) ?? '');
      final typeName = typeEnt?.str(2) ?? ent.str(4) ?? friendly;
      final name = ent.str(2) ?? typeName;
      final docId = bimDocId('ifc', gid, '$name ${ent.str(7) ?? id}');
      if (!seenEquipmentIds.add(docId)) continue;

      final container = containedIn[id];
      final spaceDocId = container == null ? null : docIdOf[container];
      if (spaceDocId == null) withoutLocation++;

      final tag = prop(id, const ['tagnumber', 'assetidentifier', 'assettag', 'mark']) ?? ent.str(7);

      equipment.add(CobieEquipmentDraft(
        docId: docId,
        name: name,
        equipmentId: tag ?? name,
        type: category,
        typeName: typeName,
        manufacturer: prop(id, const ['manufacturer']),
        modelNumber: prop(id, const ['modelnumber', 'modellabel', 'modelreference', 'articlenumber']),
        classification: classificationOf[id] ?? (typeOf[id] == null ? null : classificationOf[typeOf[id]!]),
        systemName: systemOf[id],
        spaceName: container == null ? null : nameOf[container],
        spaceDocId: spaceDocId,
        serialNumber: prop(id, const ['serialnumber']) ?? '',
        warrantyMonths: _warrantyMonths(prop, id),
        notes: ent.str(3) ?? '',
        globalId: gid,
      ));
    }

    // ---- Warnings ----
    final storeyCount = spaces.where((s) => s.isStorey).length;
    if (storeyCount == 0) {
      warnings.add('No building storeys (IfcBuildingStorey) were found.');
    }
    if (spaces.length == storeyCount) {
      warnings.add('No rooms (IfcSpace) were found. Equipment will be linked to floors only. '
          'In Revit, export with "Export rooms/spaces" enabled to include them.');
    }
    if (equipment.isEmpty) {
      warnings.add('No maintainable equipment (pumps, fans, boards, terminals, fixtures…) was found. '
          'Architectural-only models usually contain none; ask for the MEP model.');
    } else if (withoutLocation > 0) {
      warnings.add('$withoutLocation of ${equipment.length} equipment items are not placed on a floor or room.');
    }

    final buildings = ofType('IFCBUILDING').map((b) => b.value.str(2) ?? b.value.str(7)).whereType<String>();

    return IfcParseResult(
      preview: CobiePreview(spaces: spaces, equipment: equipment, warnings: warnings),
      schemaVersion: schema,
      buildingName: buildings.isEmpty ? null : buildings.first,
    );
  }

  /// COBie-style WarrantyDurationParts/Unit, else Pset_Warranty.WarrantyPeriod (IfcTimeMeasure, seconds).
  static int _warrantyMonths(String? Function(int, List<String>) prop, int id) {
    final parts = double.tryParse(prop(id, const ['warrantydurationparts']) ?? '');
    if (parts != null && parts > 0) {
      final unit = (prop(id, const ['warrantydurationunit']) ?? '').toLowerCase();
      if (unit.contains('year')) return (parts * 12).round();
      if (unit.contains('month')) return parts.round();
    }
    final seconds = double.tryParse(prop(id, const ['warrantyperiod']) ?? '');
    if (seconds != null && seconds > 0) {
      final months = (seconds / (30.4375 * 86400)).round();
      if (months > 0 && months <= 600) return months;
    }
    return 0;
  }

  static double _round(double v) => (v * 1000).roundToDouble() / 1000;

  static String? _valueText(Object? v) {
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      if (t.isEmpty || t.toLowerCase() == 'n/a' || t == '-') return null;
      return t;
    }
    if (v is _Enum) return v.value == 'T' ? 'true' : (v.value == 'F' ? 'false' : v.value);
    if (v is num) return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return null;
  }

  // ---------------------------------------------------------------------------------------------
  // STEP tokenising
  // ---------------------------------------------------------------------------------------------

  /// Calls [onStatement] with the byte range of each `…;` statement, honouring quoted strings
  /// (which may contain ';') and /* comments */.
  static void _forEachStatement(Uint8List b, void Function(int start, int end) onStatement) {
    final n = b.length;
    var start = 0;
    var i = 0;
    while (i < n) {
      final c = b[i];
      if (c == 0x27 /* ' */) {
        i++;
        while (i < n) {
          if (b[i] == 0x27) {
            if (i + 1 < n && b[i + 1] == 0x27) {
              i += 2;
              continue;
            }
            break;
          }
          i++;
        }
      } else if (c == 0x2F /* / */ && i + 1 < n && b[i + 1] == 0x2A /* * */) {
        final commentStart = i;
        i += 2;
        while (i + 1 < n && !(b[i] == 0x2A && b[i + 1] == 0x2F)) {
          i++;
        }
        i++;
        // A comment before a statement shouldn't become part of it.
        if (_skipWs(b, start, commentStart) == commentStart) start = i + 1;
      } else if (c == 0x3B /* ; */) {
        onStatement(start, i);
        start = i + 1;
      }
      i++;
    }
  }

  static int _skipWs(Uint8List b, int i, int end) {
    while (i < end && (b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09)) {
      i++;
    }
    return i;
  }

  static bool _isIdentChar(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x5F;

  /// IFC files are meant to be 7-bit ASCII (non-ASCII is escaped as \X2\…), but some exporters write
  /// raw UTF-8. Try UTF-8 first and fall back to Latin-1, which never fails.
  static String _decode(Uint8List b, int start, int end) {
    final slice = Uint8List.sublistView(b, start, end);
    try {
      return utf8.decode(slice);
    } on FormatException {
      return latin1.decode(slice);
    }
  }
}

/// Parses one STEP argument list: `('abc',#12,$,*,.T.,1.5,(#1,#2),IFCLABEL('x'))`.
class _ArgParser {
  _ArgParser(this.s);
  final String s;
  int i = 0;

  List<Object?> parseList() {
    _ws();
    if (s.codeUnitAt(i) != 0x28) throw const FormatException('Expected (');
    i++;
    final out = <Object?>[];
    _ws();
    if (i < s.length && s.codeUnitAt(i) == 0x29) {
      i++;
      return out;
    }
    while (i < s.length) {
      out.add(_value());
      _ws();
      if (i >= s.length) break;
      final c = s.codeUnitAt(i++);
      if (c == 0x29 /* ) */) break;
      if (c != 0x2C /* , */) throw const FormatException('Expected , or )');
    }
    return out;
  }

  void _ws() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c != 0x20 && c != 0x0A && c != 0x0D && c != 0x09) break;
      i++;
    }
  }

  Object? _value() {
    _ws();
    final c = s.codeUnitAt(i);
    if (c == 0x27) return _string();
    if (c == 0x23) {
      final start = ++i;
      while (i < s.length && _digit(s.codeUnitAt(i))) {
        i++;
      }
      return _Ref(int.parse(s.substring(start, i)));
    }
    if (c == 0x24 /* $ */ || c == 0x2A /* * */) {
      i++;
      return null;
    }
    if (c == 0x28) return parseList();
    if (c == 0x2E /* . */ && i + 1 < s.length && _letter(s.codeUnitAt(i + 1))) {
      final start = ++i;
      while (i < s.length && s.codeUnitAt(i) != 0x2E) {
        i++;
      }
      return _Enum(s.substring(start, i++).toUpperCase());
    }
    if (c == 0x22 /* " binary */) {
      i = s.indexOf('"', i + 1) + 1;
      return null;
    }
    if (_letter(c)) {
      // Typed value, e.g. IFCLABEL('Pump') or IFCREAL(2.5): unwrap to the inner value.
      while (i < s.length && s.codeUnitAt(i) != 0x28) {
        i++;
      }
      final inner = parseList();
      return inner.isEmpty ? null : inner.first;
    }
    final start = i;
    while (i < s.length) {
      final d = s.codeUnitAt(i);
      if (d == 0x2C || d == 0x29 || d == 0x20) break;
      i++;
    }
    return num.tryParse(s.substring(start, i).replaceFirst(RegExp(r'\.$'), '').replaceFirst(RegExp(r'\.E'), 'E'));
  }

  String _string() {
    i++; // opening quote
    final buf = StringBuffer();
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x27) {
        if (i + 1 < s.length && s.codeUnitAt(i + 1) == 0x27) {
          buf.writeCharCode(0x27);
          i += 2;
          continue;
        }
        i++;
        break;
      }
      buf.writeCharCode(c);
      i++;
    }
    return _unescape(buf.toString());
  }

  static bool _digit(int c) => c >= 0x30 && c <= 0x39;
  static bool _letter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

  /// ISO 10303-21 string escapes: \X2\…\X0\ (UTF-16), \X4\…\X0\ (UTF-32), \X\HH, \S\c, \P?\, \\.
  static String _unescape(String v) {
    if (!v.contains(r'\')) return v;
    return v
        .replaceAllMapped(RegExp(r'\\X2\\((?:[0-9A-Fa-f]{4})+)\\X0\\'), (m) {
          final h = m.group(1)!;
          return String.fromCharCodes([
            for (var k = 0; k < h.length; k += 4) int.parse(h.substring(k, k + 4), radix: 16),
          ]);
        })
        .replaceAllMapped(RegExp(r'\\X4\\((?:[0-9A-Fa-f]{8})+)\\X0\\'), (m) {
          final h = m.group(1)!;
          return String.fromCharCodes([
            for (var k = 0; k < h.length; k += 8) int.parse(h.substring(k, k + 8), radix: 16),
          ]);
        })
        .replaceAllMapped(RegExp(r'\\X\\([0-9A-Fa-f]{2})'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
        .replaceAllMapped(RegExp(r'\\S\\(.)'), (m) => String.fromCharCode(m.group(1)!.codeUnitAt(0) + 128))
        .replaceAll(RegExp(r'\\P[A-I]\\'), '')
        .replaceAll(r'\\', r'\');
  }
}
