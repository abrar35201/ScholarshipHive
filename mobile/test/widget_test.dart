import 'package:flutter_test/flutter_test.dart';

import 'package:scholarshiphive/main.dart';

void main() {
  testWidgets('App boots to splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ScholarshipHiveApp());
    await tester.pump();

    expect(find.text('ScholarshipHive'), findsOneWidget);
  });
}
