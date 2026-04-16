import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/email/parser.dart';

void main() {
  group('EmailParser — e-mandate / upcoming payment', () {
    test('rejects upcoming e-mandate notice', () {
      final r = EmailParser.parse(
        'alerts@hdfcbank.net',
        'Upcoming E-mandate (Auto payment)',
        '''
        Dear Customer, Greetings from HDFC Bank!
        There is an upcoming E-mandate (Auto payment) of INR 500.00 for Canva Pty Ltd.
        Amount will be debited from your HDFC Bank Credit Card ending 2383 on 13/04/2026.
        ''',
      );
      expect(r, isNull);
    });

    test('rejects scheduled-debit reminder', () {
      final r = EmailParser.parse(
        'alerts@somebank.com',
        'Payment reminder',
        'Reminder: Your electricity bill payment of ₹1,200 will be debited on 20/04/2026.',
      );
      expect(r, isNull);
    });

    test('accepts e-mandate SUCCESS email (past tense + strong verb)', () {
      final r = EmailParser.parse(
        'alerts@hdfcbank.net',
        'E-mandate auto payment successful',
        '''
        Your Canva Pty Ltd bill, set up through E-mandate (Auto payment), has been
        successfully paid using your HDFC Bank Credit Card ending 2383.
        Amount: INR 500.00 Date: 13/04/2026
        ''',
      );
      expect(r, isNotNull);
      expect(r!.amount, 500);
      expect(r.type, 'debit');
    });

    test('accepts normal debit even with word "scheduled" elsewhere', () {
      // A confirmation email that happens to mention scheduling history.
      final r = EmailParser.parse(
        'alerts@hdfcbank.net',
        'Transaction Alert',
        '''
        Rs.500.00 is debited from your HDFC Bank Credit Card ending 2383
        towards CANVA* I04848-43062661 on 13 Apr, 2026 at 01:46:14.
        Thank you for banking with us.
        ''',
      );
      expect(r, isNotNull);
      expect(r!.amount, 500);
    });
  });
}
