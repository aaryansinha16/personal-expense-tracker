import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/sms/parser.dart';

void main() {
  test('parses HDFC debit SMS', () {
    final r = SmsParser.parse(
      'VM-HDFCBK',
      'Rs.450.00 debited from a/c XX1234 on 12-04-26 to SWIGGY BANGALORE via UPI Ref 123456789. Avl bal Rs.10,000',
    );
    expect(r, isNotNull);
    expect(r!.amount, 450.0);
    expect(r.type, 'debit');
    expect(r.account, '1234');
  });

  test('ignores OTP', () {
    final r = SmsParser.parse('VM-HDFCBK', 'OTP for txn of Rs.500 is 123456. Do not share.');
    expect(r, isNull);
  });

  test('parses credit SMS', () {
    final r = SmsParser.parse(
      'JD-SBIINB',
      'Rs 25,000 credited to A/c no. XX9012 on 01-04-26 by NEFT from ACME CORP. Avl bal Rs 1,00,000.',
    );
    expect(r, isNotNull);
    expect(r!.amount, 25000);
    expect(r.type, 'credit');
  });

  test('detects bill due', () {
    final r = SmsParser.parse(
      'VM-HDFCCC',
      'Your HDFC Credit Card statement: Total amount due Rs.15,000. Due date: 25-04-2026. Min amount due Rs.1,500.',
    );
    expect(r, isNotNull);
    expect(r!.isBillDue, true);
    expect(r.amount, 15000);
  });
}
