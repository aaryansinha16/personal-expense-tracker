import '../db/models.dart';
import 'sender_rules.dart';

class ParsedEmail {
  final double amount;
  final String type;
  final String? merchant;
  final String? refNo;
  final String? orderId;
  final String? categoryHint;

  ParsedEmail({
    required this.amount,
    required this.type,
    this.merchant,
    this.refNo,
    this.orderId,
    this.categoryHint,
  });
}

class EmailParser {
  /// Try to turn a (sender, subject, body) triple into a transaction.
  /// `sender` can be an email address, display name, or both — e.g.
  /// `"Amazon.in <auto-confirm@amazon.in>"` or just `"orders@swiggy.in"`.
  /// `body` can be HTML or plain text.
  static ParsedEmail? parse(String sender, String subject, String body) {
    final plainBody = _stripHtml(body);
    final searchText = '$subject\n$plainBody';

    // Skip obvious noise.
    if (_otpRe.hasMatch(searchText)) return null;
    if (_unsubscribeOnlyRe.hasMatch(searchText) && !_amountRe.hasMatch(searchText)) return null;
    // Order-confirmation emails often precede payment — accept them only if
    // they explicitly include a paid/charged verb.
    if (_shippedOnlyRe.hasMatch(subject) && !_paidVerbRe.hasMatch(searchText)) return null;

    // Amount — take the LARGEST monetary value in the body. Receipts usually
    // have several numbers (item totals, taxes, shipping, discounts, grand
    // total). Largest tends to be the grand total.
    double? amount;
    for (final m in _amountRe.allMatches(searchText)) {
      final raw = m.group(1)!.replaceAll(',', '');
      final v = double.tryParse(raw);
      if (v == null || v <= 0) continue;
      if (amount == null || v > amount) amount = v;
    }
    if (amount == null) return null;

    final type = _creditRe.hasMatch(searchText) && !_paidVerbRe.hasMatch(searchText)
        ? TxnType.credit
        : TxnType.debit;

    final senderDomain = _extractDomain(sender);
    final senderRule = SenderRules.match(senderDomain);
    final merchant = senderRule?.displayName ?? _merchantFromSubject(subject) ?? senderDomain;
    final categoryHint = senderRule?.category;
    final refNo = _refRe.firstMatch(searchText)?.group(1);
    final orderId = _orderRe.firstMatch(searchText)?.group(1);

    // Sanity check — emails with tiny amounts are usually subscription expiry
    // warnings, OTP receipts, etc. If merchant is unknown AND amount < 50, skip.
    if (senderRule == null && amount < 50) return null;

    return ParsedEmail(
      amount: amount,
      type: type,
      merchant: merchant,
      refNo: refNo,
      orderId: orderId,
      categoryHint: categoryHint,
    );
  }

  /// Quick pre-filter used by the Gmail scanner to skip obviously irrelevant
  /// threads without paying the cost of full parsing.
  static bool looksFinancial(String subject, String body) {
    final combined = '$subject\n${_stripHtml(body)}';
    if (_otpRe.hasMatch(combined)) return false;
    if (!_amountRe.hasMatch(combined)) return false;
    return _paidVerbRe.hasMatch(combined) || _creditRe.hasMatch(combined) ||
        _orderRe.hasMatch(combined);
  }

  // --- Patterns ---

  // Amount: "Rs.1,234.56" / "INR 1234" / "₹500.00" / "Rs 500".
  static final _amountRe = RegExp(
    r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // Explicit paid/charged wording.
  static final _paidVerbRe = RegExp(
    r'\b(paid|payment\s+(?:successful|received|made|of|confirmation)|charged|debited|you\s+spent|you\s+bought|order\s+placed|purchase(?:d)?|successfully\s+paid)\b',
    caseSensitive: false,
  );

  // Inbound money wording.
  static final _creditRe = RegExp(
    r'\b(refund(?:ed)?|credited|money\s+received|cashback|you\s+received)\b',
    caseSensitive: false,
  );

  static final _otpRe = RegExp(
    r'\b(otp|one\s*time\s*password|verification\s*code|security\s*code|login\s*code)\b',
    caseSensitive: false,
  );

  // Subscribe/marketing footer only — skip if no amount.
  static final _unsubscribeOnlyRe = RegExp(
    r'\bunsubscribe\b',
    caseSensitive: false,
  );

  // "Shipped" emails without a paid verb — defer to payment email.
  static final _shippedOnlyRe = RegExp(
    r'\b(shipped|out\s+for\s+delivery|delivered)\b',
    caseSensitive: false,
  );

  // Order ID / reference number.
  static final _refRe = RegExp(
    r'(?:ref(?:erence)?(?:\s*no\.?)?|utr|txn(?:\s*id)?|transaction\s*id)\s*[:\-#]?\s*([A-Za-z0-9]{6,})',
    caseSensitive: false,
  );
  static final _orderRe = RegExp(
    r'(?:order(?:\s*id|\s*#)?|order\s*number)\s*[:\-#]?\s*([A-Za-z0-9\-]{6,})',
    caseSensitive: false,
  );

  // --- Helpers ---

  static String _stripHtml(String s) {
    if (!s.contains('<')) return s;
    // Kill script/style blocks then all tags.
    var out = s
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    // Decode the most common HTML entities.
    const entities = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&rsquo;': "'",
      '&lsquo;': "'",
      '&rupee;': '₹',
      '&#8377;': '₹',
    };
    entities.forEach((k, v) => out = out.replaceAll(k, v));
    // Collapse whitespace.
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  static String _extractDomain(String sender) {
    final m = RegExp(r'<([^>]+@([^>]+))>').firstMatch(sender);
    if (m != null) return m.group(2)!.trim().toLowerCase();
    final m2 = RegExp(r'([A-Za-z0-9._%+\-]+)@([A-Za-z0-9.\-]+)').firstMatch(sender);
    if (m2 != null) return m2.group(2)!.trim().toLowerCase();
    return sender.toLowerCase();
  }

  static String? _merchantFromSubject(String subject) {
    // "Your Swiggy order ...", "Amazon.in order confirmation" — pick the
    // capitalized noun phrase at the start.
    final m = RegExp(r'^[Yy]our\s+([A-Za-z][A-Za-z0-9\.\-]+)').firstMatch(subject);
    if (m != null) return m.group(1);
    final m2 = RegExp(r'^([A-Z][A-Za-z0-9\.]+)').firstMatch(subject.trim());
    if (m2 != null) return m2.group(1);
    return null;
  }
}
