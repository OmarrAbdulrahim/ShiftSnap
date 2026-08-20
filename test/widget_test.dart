import 'package:flutter_test/flutter_test.dart';

import 'package:shiftsnap/main.dart';

void main() {
  testWidgets('shows the ShiftSnap home screen', (tester) async {
    await tester.pumpWidget(const ShiftSnapApp());

    expect(find.text('ShiftSnap'), findsOneWidget);
    expect(find.text('Import your rota in seconds'), findsOneWidget);
    expect(find.text('Scan Rota'), findsOneWidget);
    expect(find.text('My Calendar'), findsOneWidget);
  });
}
