import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cmms/services/bim/ifc_parser.dart';

Uint8List _ifc(String schema, String data) => Uint8List.fromList(utf8.encode('''
ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('ViewDefinition [CoordinationView]'),'2;1');
FILE_NAME('test.ifc','2026-10-21T10:00:00',(''),(''),'','','');
FILE_SCHEMA(('$schema'));
ENDSEC;
DATA;
$data
ENDSEC;
END-ISO-10303-21;
'''));

void main() {
  group('IfcParser (IFC4)', () {
    // Building -> Level 1 (3000 mm) -> Plant Room 101 containing a pump with type, psets, system and
    // classification; a light fixture on the storey; a wall (ignored); a ';' inside a string.
    final bytes = _ifc('IFC4', r'''
#1=IFCSIUNIT(*,.LENGTHUNIT.,.MILLI.,.METRE.);
#10=IFCBUILDING('2O2Fr$t4X7Zf8NOew3FLOH',$,'Main Block',$,$,$,$,$,.ELEMENT.,$,$,$);
#20=IFCBUILDINGSTOREY('0K2wbkpBz9eQXb7ldUQkgh',$,'Level 1','Ground; main',$,$,$,'Ground Floor',.ELEMENT.,3000.);
#21=IFCRELAGGREGATES('1aK2wbkpBz9eQXb7ldUQka',$,$,$,#10,(#20));
#30=IFCSPACE('3cUkl32yn9qRSPvBJVyWYp',$,'101',$,$,$,$,'Plant Room',.ELEMENT.,.SPACE.,$);
#31=IFCRELAGGREGATES('1bK2wbkpBz9eQXb7ldUQkb',$,$,$,#20,(#30));
#40=IFCPUMP('1CZILmCaHETO8tf3SgGEXu',$,'Pump P-01','Chilled water',$,$,$,'P-01',.CIRCULATOR.);
#41=IFCPUMPTYPE('2CZILmCaHETO8tf3SgGEXa',$,'Grundfos CR 10',$,$,(#50),$,$,$,.CIRCULATOR.);
#42=IFCRELDEFINESBYTYPE('3CZILmCaHETO8tf3SgGEXb',$,$,$,(#40),#41);
#43=IFCRELCONTAINEDINSPATIALSTRUCTURE('0DZILmCaHETO8tf3SgGEXc',$,$,$,(#40),#30);
#50=IFCPROPERTYSET('0EZILmCaHETO8tf3SgGEXd',$,'Pset_ManufacturerTypeInformation',$,(#51,#52));
#51=IFCPROPERTYSINGLEVALUE('Manufacturer',$,IFCLABEL('Grundfos'),$);
#52=IFCPROPERTYSINGLEVALUE('ModelLabel',$,IFCLABEL('CR 10-3'),$);
#60=IFCPROPERTYSET('0FZILmCaHETO8tf3SgGEXe',$,'Pset_ManufacturerOccurrence',$,(#61));
#61=IFCPROPERTYSINGLEVALUE('SerialNumber',$,IFCIDENTIFIER('SN-9921'),$);
#62=IFCRELDEFINESBYPROPERTIES('0GZILmCaHETO8tf3SgGEXf',$,$,$,(#40),#60);
#70=IFCDISTRIBUTIONSYSTEM('0HZILmCaHETO8tf3SgGEXg',$,'Chilled Water',$,$,$,.CHILLEDWATER.);
#71=IFCRELASSIGNSTOGROUP('0IZILmCaHETO8tf3SgGEXh',$,$,$,(#40),$,#70);
#80=IFCCLASSIFICATIONREFERENCE($,'Pr_65_53_59','Pumps',$,$,$);
#81=IFCRELASSOCIATESCLASSIFICATION('0JZILmCaHETO8tf3SgGEXi',$,$,$,(#41),#80);
#90=IFCLIGHTFIXTURE('0KZILmCaHETO8tf3SgGEXj',$,'Downlight \X2\00E9\X0\',$,$,$,$,$,$);
#91=IFCRELCONTAINEDINSPATIALSTRUCTURE('0LZILmCaHETO8tf3SgGEXk',$,$,$,(#90,#95),#20);
#95=IFCWALL('0MZILmCaHETO8tf3SgGEXl',$,'Wall',$,$,$,$,$,$);
/* a comment; with a semicolon */
#99=IFCCARTESIANPOINT((0.,0.,0.));
''');

    final result = IfcParser.parse(bytes);
    final p = result.preview;

    test('reads schema and building', () {
      expect(result.schemaVersion, 'IFC4');
      expect(result.buildingName, 'Main Block');
    });

    test('storeys use metres and keep long name / description', () {
      final storey = p.spaces.singleWhere((s) => s.isStorey);
      expect(storey.name, 'Level 1');
      expect(storey.elevation, 3.0);
      expect(storey.description, 'Ground Floor');
      expect(storey.docId, 'bim_0K2wbkpBz9eQXb7ldUQkgh');
    });

    test('rooms link to their storey', () {
      final room = p.spaces.singleWhere((s) => !s.isStorey);
      expect(room.name, '101');
      expect(room.description, 'Plant Room');
      expect(room.parentDocId, 'bim_0K2wbkpBz9eQXb7ldUQkgh');
      expect(room.floorName, 'Level 1');
    });

    test('equipment gets type, psets, system, classification and room', () {
      final pump = p.equipment.singleWhere((e) => e.name == 'Pump P-01');
      expect(pump.type, 'Mechanical');
      expect(pump.typeName, 'Grundfos CR 10');
      expect(pump.manufacturer, 'Grundfos');
      expect(pump.modelNumber, 'CR 10-3');
      expect(pump.serialNumber, 'SN-9921');
      expect(pump.systemName, 'Chilled Water');
      expect(pump.classification, 'Pr_65_53_59 Pumps');
      expect(pump.equipmentId, 'P-01');
      expect(pump.spaceDocId, 'bim_3cUkl32yn9qRSPvBJVyWYp');
      expect(pump.spaceName, '101');
      expect(pump.globalId, '1CZILmCaHETO8tf3SgGEXu');
      expect(pump.docId, 'bim_1CZILmCaHETO8tf3SgGEXu');
    });

    test('decodes IFC unicode escapes and links storey-level equipment', () {
      final light = p.equipment.singleWhere((e) => e.type == 'Electrical');
      expect(light.name, 'Downlight é');
      expect(light.spaceDocId, 'bim_0K2wbkpBz9eQXb7ldUQkgh');
    });

    test('ignores non-equipment elements', () {
      expect(p.equipment.length, 2);
    });
  });

  test('IFC2X3 generic classes take their kind from the type object', () {
    final bytes = _ifc('IFC2X3', r'''
#20=IFCBUILDINGSTOREY('0K2wbkpBz9eQXb7ldUQkgh',$,'L2',$,$,$,$,$,.ELEMENT.,6.5);
#40=IFCFLOWTERMINAL('1CZILmCaHETO8tf3SgGEXu',$,'Supply Diffuser',$,$,$,$,'348572');
#41=IFCAIRTERMINALTYPE('2CZILmCaHETO8tf3SgGEXa',$,'600x600 Diffuser',$,$,$,$,$,$,.DIFFUSER.);
#42=IFCRELDEFINESBYTYPE('3CZILmCaHETO8tf3SgGEXb',$,$,$,(#40),#41);
#43=IFCRELCONTAINEDINSPATIALSTRUCTURE('0DZILmCaHETO8tf3SgGEXc',$,$,$,(#40),#20);
''');
    final result = IfcParser.parse(bytes);
    final diffuser = result.preview.equipment.single;
    expect(result.schemaVersion, 'IFC2X3');
    expect(diffuser.type, 'HVAC');
    expect(diffuser.typeName, '600x600 Diffuser');
    expect(result.preview.spaces.single.elevation, 6.5);
    expect(result.preview.warnings.any((w) => w.contains('No rooms')), isTrue);
  });

  test('a non-IFC file produces a clear warning and nothing else', () {
    final result = IfcParser.parse(Uint8List.fromList(utf8.encode('hello; world;')));
    expect(result.preview.isEmpty, isTrue);
    expect(result.preview.warnings.first, contains('FILE_SCHEMA'));
  });
}
