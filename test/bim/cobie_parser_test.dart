import 'package:flutter_test/flutter_test.dart';
import 'package:cmms/services/bim/cobie_parser.dart';

void main() {
  // Headers already normalised the way CobieWorkbookReader produces them.
  final workbook = <String, List<Map<String, String>>>{
    'floor': [
      {'name': 'Level 1', 'elevation': '0', 'extidentifier': '0K2wbkpBz9eQXb7ldUQkgh'},
      {'name': 'Level 1', 'elevation': '0'}, // duplicate
    ],
    'space': [
      {'name': '101', 'floorname': 'Level 1', 'description': 'Plant Room'},
      {'name': '999', 'floorname': 'Roof'}, // unknown floor
    ],
    'type': [
      {
        'name': 'Pump Type A',
        'manufacturer': 'Grundfos',
        'modelnumber': 'CR 10',
        'category': 'Pr_65_53_59',
        'warrantydurationparts': '2',
        'warrantydurationunit': 'Year',
      },
    ],
    'system': [
      {'name': 'Chilled Water', 'componentnames': 'P-01, P-02'},
    ],
    'component': [
      {'name': 'P-01', 'typename': 'Pump Type A', 'space': '101', 'serialnumber': 'SN1', 'tagnumber': 'TAG-1'},
      {'name': 'P-02', 'typename': 'Missing Type', 'space': '101'},
      {'name': ''},
    ],
    'job': [
      {'name': 'Inspect seals', 'typename': 'Pump Type A', 'frequency': '6', 'frequencyunit': 'month', 'category': 'PM'},
      {'name': 'Run test', 'typename': 'Pump Type A', 'frequency': '10', 'frequencyunit': 'hour'},
    ],
  };

  final p = CobieParser.parse(workbook);

  test('floors and spaces, with duplicates and bad references reported', () {
    expect(p.storeyCount, 1);
    expect(p.roomCount, 2);
    expect(p.spaces.first.docId, 'bim_0K2wbkpBz9eQXb7ldUQkgh');
    expect(p.warnings, contains('Duplicate Floor "Level 1" was skipped.'));
    expect(p.warnings.any((w) => w.contains('"999"') && w.contains('Roof')), isTrue);
  });

  test('components pick up type, system, warranty and tag', () {
    final pump = p.equipment.firstWhere((e) => e.name == 'P-01');
    expect(pump.manufacturer, 'Grundfos');
    expect(pump.modelNumber, 'CR 10');
    expect(pump.classification, 'Pr_65_53_59');
    expect(pump.systemName, 'Chilled Water');
    expect(pump.warrantyMonths, 24);
    expect(pump.equipmentId, 'TAG-1');
    expect(pump.docId, 'cobie_p-01');
    expect(p.warnings.any((w) => w.contains('Missing Type')), isTrue);
    expect(p.warnings, contains('A Component row has no Name and was skipped.'));
  });

  test('jobs become monthly PM tasks; non-calendar frequencies are skipped', () {
    expect(p.jobs.length, 1);
    expect(p.jobs.single.frequencyMonths, 6);
    expect(p.jobs.single.component, 'Pump Type A');
    expect(p.warnings.any((w) => w.contains('Run test')), isTrue);
  });

  test('ids are stable for names with no ASCII letters (same on web and mobile)', () {
    expect(bimDocId('space', null, '会议室'), bimDocId('space', null, '会议室'));
    expect(bimDocId('space', null, '会议室'), 'space_${bimDocId('space', null, '会议室').split('_').last}');
    expect(bimDocId('space', null, '会议室'), isNot(bimDocId('space', null, '办公室')));
  });
}
