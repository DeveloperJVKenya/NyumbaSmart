// Widget smoke tests for app UI that renders without Firebase.
// (The full app, MyApp, needs Firebase initialised, so it is exercised by running the app instead.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cmms/screens/bim/bim_widgets.dart';
import 'package:cmms/theme/app_widgets.dart';
import 'package:cmms/widgets/equipment_picker_field.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('formatBytes uses readable units', () {
    expect(formatBytes(null), '—');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(300 * 1024 * 1024), '300.0 MB');
  });

  testWidgets('BimStat and BimPill show their labels', (tester) async {
    await tester.pumpWidget(_host(const Column(children: [
      BimStat(icon: Icons.layers_rounded, label: 'Floors', value: '4'),
      BimPill(label: 'Imported', color: Colors.green),
    ])));
    expect(find.text('Floors'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Imported'), findsOneWidget);
  });

  testWidgets('AppErrorBanner shows its message', (tester) async {
    await tester.pumpWidget(_host(const AppErrorBanner(message: 'Something went wrong')));
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('EquipmentPickerField shows the chosen equipment and can be cleared', (tester) async {
    EquipmentRef? value = const EquipmentRef(id: 'e1', name: 'Pump P-01');
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setState) => EquipmentPickerField(
        facilityId: 'f1',
        value: value,
        onChanged: (v) => setState(() => value = v),
      ),
    )));
    expect(find.text('Pump P-01'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(value, isNull);
    expect(find.text('Pump P-01'), findsNothing);
  });
}
