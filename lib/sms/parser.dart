import '../db/models.dart';

class ParsedSms {
  final double amount;
  final String type;
  final String? merchant;
  final String? account;
  final String? refNo;
  final bool isBillDue;
  final DateTime? dueDate;

  ParsedSms({
    required this.amount,
    required this.type,
    this.merchant,
    this.account,
    this.refNo,
    this.isBillDue = false,
    this.dueDate,
  });
}

class SmsParser {
  // Senders we care about — Indian banks + UPI apps. The senders come through
  // as e.g. "VM-HDFCBK", "JD-SBIUPI", "AX-PAYTM". We just look for these tokens
  // anywhere in the sender string.
  static final _knownSenderTokens = <String>[
    'HDFC', 'SBI', 'ICICI', 'AXIS', 'KOTAK', 'YESBNK', 'IDFC', 'IDBIBK',
    'PNBSMS', 'BOB', 'INDBNK', 'CITIBK', 'CITIBK', 'RBLBNK', 'AUFBNK',
    'PAYTM', 'PHONPE', 'PHONEPE', 'GPAY', 'GOOGLPAY', 'AMZPAY', 'BHIMPE',
    'CRED', 'SLICE', 'FREECHG', 'MOBIKWK',
    'HDFCCC', 'SBICRD', 'AMEX', 'ONECARD', 'HSBC', 'AMZNPAY',
  ];

  static bool isFinancialSender(String sender) {
    final s = sender.toUpperCase();
    return _knownSenderTokens.any((t) => s.contains(t));
  }

  // Amount in Indian bank SMS: "Rs.1,234.56" / "INR 1234" / "Rs 500.00".
  static final _amountRe = RegExp(
    r'(?:rs\.?|inr)\s*([0-9][0-9,]*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // Debit keywords
  static final _debitRe = RegExp(
    r'\b(debited|spent|paid|purchase|withdrawn|sent|trf|transferred(?:\s+to)?|debit|dr)\b',
    caseSensitive: false,
  );

  // Credit keywords
  static final _creditRe = RegExp(
    r'\b(credited|received|deposit|credit|cr)\b',
    caseSensitive: false,
  );

  // Merchant after "to " / "at " / "VPA " / "@"
  static final _merchantRe = RegExp(
    r'(?:to|at|towards|from)\s+([A-Za-z0-9&@._\-\*\s]{3,40}?)(?:\s+on|\s+for|\s+ref|\s+upi|\s+via|\.|,|$)',
    caseSensitive: false,
  );

  // UPI VPA: something@bank
  static final _vpaRe = RegExp(r'([a-z0-9.\-_]+@[a-z]{3,})', caseSensitive: false);

  // Account last 4
  static final _accountRe = RegExp(
    r'(?:a/c|ac|account|card)\s*(?:no\.?\s*)?(?:x+|\*+)?(\d{4})',
    caseSensitive: false,
  );

  // Ref number
  static final _refRe = RegExp(
    r'(?:ref(?:erence)?(?:\s*no\.?)?|utr|txn(?:\s*id)?)\s*[:\-]?\s*([A-Za-z0-9]{6,})',
    caseSensitive: false,
  );

  // Credit card bill due — strong signals specific to statements.
  static final _billDueRe = RegExp(
    r'(?:statement|amount\s+due|total\s+due|min(?:imum)?\s+(?:amount\s+)?due|outstanding\s+(?:amount|balance))',
    caseSensitive: false,
  );
  static final _dueDateRe = RegExp(
    r'due\s+(?:date|on|by)?\s*[:\-]?\s*(\d{1,2}[\-/\.\s](?:\d{1,2}|[A-Za-z]{3})[\-/\.\s]\d{2,4})',
    caseSensitive: false,
  );

  // OTP/info SMS we want to ignore
  static final _otpRe = RegExp(r'\botp\b|one\s*time\s*password|verification\s*code',
      caseSensitive: false);
  static final _balanceOnlyRe = RegExp(
    r'(?:avl\s*bal|available\s*balance|bal\s*is|balance\s*is)',
    caseSensitive: false,
  );

  static ParsedSms? parse(String sender, String body) {
    if (!isFinancialSender(sender)) return null;
    if (_otpRe.hasMatch(body)) return null;

    final amtMatch = _amountRe.firstMatch(body);
    if (amtMatch == null) return null;

    final amount = double.tryParse(amtMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;

    // Bill due SMS — not a transaction, it's a future obligation.
    // Don't require absence of credit/debit words: "Credit Card statement"
    // will trip the credit regex even though it's a bill.
    if (_billDueRe.hasMatch(body) && !_debitRe.hasMatch(body)) {
      return ParsedSms(
        amount: amount,
        type: TxnType.debit,
        merchant: _guessBillMerchant(sender, body),
        isBillDue: true,
        dueDate: _parseDueDate(body),
        refNo: _refRe.firstMatch(body)?.group(1),
      );
    }

    final isDebit = _debitRe.hasMatch(body);
    final isCredit = _creditRe.hasMatch(body);

    // If it's a balance-only message and neither debit/credit is explicit, skip.
    if (!isDebit && !isCredit && _balanceOnlyRe.hasMatch(body)) return null;
    if (!isDebit && !isCredit) return null;

    final type = isDebit && !isCredit ? TxnType.debit : (isCredit && !isDebit ? TxnType.credit : (isDebit ? TxnType.debit : TxnType.credit));

    String? merchant;
    final vpa = _vpaRe.firstMatch(body);
    if (vpa != null) merchant = vpa.group(1);
    merchant ??= _merchantRe.firstMatch(body)?.group(1)?.trim();
    merchant = _cleanMerchant(merchant);

    final account = _accountRe.firstMatch(body)?.group(1);
    final ref = _refRe.firstMatch(body)?.group(1);

    return ParsedSms(
      amount: amount,
      type: type,
      merchant: merchant,
      account: account,
      refNo: ref,
    );
  }

  static String? _cleanMerchant(String? s) {
    if (s == null) return null;
    var out = s.trim();
    out = out.replaceAll(RegExp(r'\s+'), ' ');
    out = out.replaceAll(RegExp(r'[\*]+'), '');
    if (out.length > 40) out = out.substring(0, 40);
    if (out.isEmpty) return null;
    return out;
  }

  static String? _guessBillMerchant(String sender, String body) {
    final s = sender.toUpperCase();
    if (s.contains('HDFC')) return 'HDFC Card';
    if (s.contains('SBICRD') || s.contains('SBI')) return 'SBI Card';
    if (s.contains('ICICI')) return 'ICICI Card';
    if (s.contains('AXIS')) return 'Axis Card';
    if (s.contains('AMEX')) return 'Amex';
    if (s.contains('ONECARD')) return 'OneCard';
    return null;
  }

  static DateTime? _parseDueDate(String body) {
    final m = _dueDateRe.firstMatch(body);
    if (m == null) return null;
    final raw = m.group(1)!.replaceAll(RegExp(r'\s+'), '-').replaceAll('/', '-').replaceAll('.', '-');
    final parts = raw.split('-');
    if (parts.length != 3) return null;
    try {
      final day = int.parse(parts[0]);
      final monthPart = parts[1];
      final year = int.parse(parts[2].length == 2 ? '20${parts[2]}' : parts[2]);
      int month;
      if (RegExp(r'^\d+$').hasMatch(monthPart)) {
        month = int.parse(monthPart);
      } else {
        const months = {
          'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
          'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
        };
        month = months[monthPart.toLowerCase().substring(0, 3)] ?? 1;
      }
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }
}
