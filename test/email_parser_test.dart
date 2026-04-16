import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/email/parser.dart';
import 'package:expense_tracker/email/sender_registry.dart';

void main() {
  group('EmailParser.parse', () {
    test('parses Amazon order confirmation with largest-amount heuristic', () {
      final r = EmailParser.parse(
        'Amazon.in <auto-confirm@amazon.in>',
        'Your Amazon.in order of Noise Smartwatch has been placed',
        '''
        <html><body>
          <p>Thank you for your order.</p>
          <p>Item total: ₹1,899.00</p>
          <p>Shipping: ₹0.00</p>
          <p>GST: ₹189.00</p>
          <p>Order total: ₹2,088.00</p>
          <p>Order ID: 407-1234567-1234567</p>
        </body></html>
        ''',
      );
      expect(r, isNotNull);
      expect(r!.amount, 2088);
      expect(r.type, 'debit');
      expect(r.merchant, 'Amazon');
      expect(r.categoryHint, 'Shopping');
      expect(r.orderId, '407-1234567-1234567');
    });

    test('parses Swiggy plain text receipt', () {
      final r = EmailParser.parse(
        'orders@swiggy.in',
        'Swiggy Order Confirmation',
        'Your Swiggy order has been placed. You paid Rs.485 for your order from Meghana Foods.',
      );
      expect(r, isNotNull);
      expect(r!.amount, 485);
      expect(r.merchant, 'Swiggy');
      expect(r.categoryHint, 'Food & Dining');
    });

    test('CRED payment email parses as Transfer', () {
      final r = EmailParser.parse(
        'noreply@cred.club',
        'Payment successful',
        'Your payment of ₹12,500 to HDFC Credit Card was successful.',
      );
      expect(r, isNotNull);
      expect(r!.amount, 12500);
      expect(r.merchant, 'CRED');
      expect(r.categoryHint, 'Transfer');
    });

    test('ignores OTP emails', () {
      final r = EmailParser.parse(
        'no-reply@somebank.in',
        'Your OTP is 345678',
        'Your OTP for login is 345678. Amount: Rs.500. Do not share.',
      );
      expect(r, isNull);
    });

    test('ignores shipped-only notification without paid verb', () {
      final r = EmailParser.parse(
        'ship-confirm@amazon.in',
        'Your Amazon.in order has shipped',
        'Your order has shipped. Track your package.',
      );
      expect(r, isNull);
    });

    test('skips unknown sender for sub-₹50 amounts', () {
      final r = EmailParser.parse(
        'random@unknown.co',
        'Your subscription',
        'You paid Rs.5 for convenience fee.',
      );
      expect(r, isNull);
    });

    test('accepts unknown sender when amount is substantial', () {
      final r = EmailParser.parse(
        'noreply@somemerchant.co.in',
        'Payment receipt',
        'Payment of ₹899 received. Thank you for your purchase.',
      );
      expect(r, isNotNull);
      expect(r!.amount, 899);
    });

    test('detects refund as credit', () {
      final r = EmailParser.parse(
        'refunds@amazon.in',
        'Your refund has been processed',
        'We have refunded ₹1,599 to your original payment method.',
      );
      expect(r, isNotNull);
      expect(r!.type, 'credit');
      expect(r.amount, 1599);
    });

    test('rejects redBus promo with embedded amount', () {
      // Real case: historical reference inside promotional copy.
      final r = EmailParser.parse(
        'promo@redbus.in',
        'Traveller, book your tickets on the redBus app!',
        '''
        Explore amazing deals on bus and train tickets.
        Starting at ₹99 only. Save up to ₹500 on your first booking!
        Amount - of 500000 (equivalent to 71.3 million or US\$18,000 in 2019).
        Book now. Unsubscribe from promotional emails.
        ''',
      );
      expect(r, isNull);
    });

    test('rejects Amazon deal newsletter', () {
      final r = EmailParser.parse(
        'deals@amazon.in',
        'Deal of the day: Noise smartwatch',
        '''
        Best price. Flat 40% off. Grab it before it's gone.
        ₹1,999 now ₹999. Shop now. Unsubscribe.
        ''',
      );
      expect(r, isNull);
    });

    test('rejects promotional email without a transaction verb', () {
      final r = EmailParser.parse(
        'offers@swiggy.in',
        'Exclusive offer for you',
        'Get ₹200 off on orders above ₹499. Limited time offer. Unsubscribe.',
      );
      expect(r, isNull);
    });

    test('large amount requires strong transaction verb', () {
      // Amount ≥ ₹1,00,000 with only weak "paid" verb should be rejected —
      // belt-and-braces against marketing copy.
      final r = EmailParser.parse(
        'noreply@somesite.com',
        'Update',
        'You paid ₹5,00,000 for the apartment in Mumbai in 2019.',
      );
      expect(r, isNull);
    });

    test('large amount accepted with strong signal', () {
      final r = EmailParser.parse(
        'noreply@hdfcbank.com',
        'Payment confirmation',
        'Payment successful. Your payment of ₹2,00,000 has been debited to your account.',
      );
      expect(r, isNotNull);
      expect(r!.amount, 200000);
      expect(r.type, 'debit');
    });

    test('rejects email with amount but no transaction verb', () {
      // A non-promo email that just mentions an amount shouldn't become
      // a transaction.
      final r = EmailParser.parse(
        'friend@somedomain.com',
        'Hey, question',
        'Do you remember when that thing cost ₹5,000? Good times.',
      );
      expect(r, isNull);
    });
  });

  group('EmailParser.looksFinancial', () {
    test('true for a Swiggy receipt', () {
      expect(
        EmailParser.looksFinancial('Your Swiggy order', 'You paid ₹485 for your meal'),
        true,
      );
    });
    test('false for delivery updates', () {
      expect(
        EmailParser.looksFinancial('Your package has shipped', 'Track your package here.'),
        false,
      );
    });
    test('false for OTP emails', () {
      expect(
        EmailParser.looksFinancial('Your OTP', 'OTP is 123456 for ₹500 transaction'),
        false,
      );
    });
  });

  group('SenderRegistry (seed fallback)', () {
    // Tests hit the static-seed fallback since load() isn't called.
    final r = SenderRegistry.instance;

    test('matches by domain suffix', () {
      expect(r.match('orders@swiggy.in'.split('@').last)?.displayName, 'Swiggy');
      expect(r.match('auto-confirm@amazon.in'.split('@').last)?.displayName, 'Amazon');
      expect(r.match('ship.amazon.in')?.displayName, 'Amazon');
    });
    test('longest suffix wins', () {
      // hdfcbank.com vs hdfcbank.net — a "xyz.hdfcbank.net" sender should
      // match the .net rule, not the shorter .com one.
      expect(r.match('alerts@hdfcbank.net')?.displayName, 'HDFC Bank');
      expect(r.match('notify.sbicard.com')?.displayName, 'SBI Card');
    });
    test('unknown domain returns null', () {
      expect(r.match('foo@bar.com'.split('@').last), isNull);
    });
    test('gmailQuery contains all senders', () {
      final q = r.gmailQuery();
      expect(q.contains('from:swiggy.in'), true);
      expect(q.contains('from:amazon.in'), true);
      expect(q.contains('from:hdfcbank.net'), true);
      expect(q.contains('from:npci.org.in'), true);
      expect(q.contains('-subject:otp'), true);
    });
  });
}
