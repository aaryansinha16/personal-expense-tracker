import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/sms/parser.dart';

void main() {
  group('SmsParser.parse', () {
    test('parses HDFC debit SMS', () {
      final r = SmsParser.parse(
        'VM-HDFCBK',
        'Rs.450.00 debited from a/c XX1234 on 12-04-26 to SWIGGY BANGALORE via UPI Ref 123456789. Avl bal Rs.10,000',
      );
      expect(r, isNotNull);
      expect(r!.amount, 450.0);
      expect(r.type, 'debit');
      expect(r.account, '1234');
      expect(r.isCardPayment, false);
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

    test('parses Amazon Pay debit SMS', () {
      final r = SmsParser.parse(
        'VM-ATMZN',
        'You paid Rs.1299 to SELLER via Amazon Pay UPI on 16-04-26. Ref 445566778899.',
      );
      expect(r, isNotNull);
      expect(r!.amount, 1299);
      expect(r.type, 'debit');
    });

    test('flags CC payment-received as card payment', () {
      final r = SmsParser.parse(
        'VM-HDFCCC',
        'Thank you for your payment of Rs.15000 received on your HDFC Credit Card XX1234 on 16-04-26.',
      );
      expect(r, isNotNull);
      expect(r!.isCardPayment, true);
      expect(r.amount, 15000);
    });

    test('CC statement SMS not confused with card payment', () {
      final r = SmsParser.parse(
        'VM-HDFCCC',
        'Your HDFC Credit Card statement: Total amount due Rs.15,000. Due date: 25-04-2026.',
      );
      expect(r, isNotNull);
      expect(r!.isBillDue, true);
      expect(r.isCardPayment, false);
    });
  });

  group('SmsParser.looksFinancial', () {
    test('true when amount and a verb are present', () {
      expect(
        SmsParser.looksFinancial('Rs.500 debited on 16-04-26. Thanks!'),
        true,
      );
    });

    test('false for delivery updates without amounts', () {
      expect(
        SmsParser.looksFinancial('Your order has been shipped and will arrive tomorrow.'),
        false,
      );
    });

    test('false for amount-only balance SMS', () {
      // Only has "Rs." + no debit/credit verb
      expect(
        SmsParser.looksFinancial('Rs.50000 is your current balance.'),
        false,
      );
    });
  });
}
