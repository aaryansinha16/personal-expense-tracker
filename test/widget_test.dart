import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/main.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    await tester.pumpWidget(const ExpenseApp());
    expect(find.text('Expense Tracker'), findsOneWidget);
  });
}
