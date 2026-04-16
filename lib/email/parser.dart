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

    // Obvious noise we never parse.
    if (_otpRe.hasMatch(searchText)) return null;
    if (_shippedOnlyRe.hasMatch(subject) && !_paidVerbRe.hasMatch(searchText)) return null;

    // HARD REQUIREMENT: there must be a transactional signal anywhere in
    // the text. A bare amount is not enough — promotional emails include
    // amounts without being transactions, and we'd falsely import them.
    final hasPaid = _paidVerbRe.hasMatch(searchText);
    final hasCredit = _creditRe.hasMatch(searchText);
    final hasStrongVerb = _strongTxnVerbRe.hasMatch(searchText);
    if (!hasPaid && !hasCredit && !hasStrongVerb) return null;

    // Promo filter: marketing footer + no STRONG verb → skip. Weak verbs
    // alone (e.g. "payment options" / "your account") aren't enough to
    // override marketing indicators.
    final hasUnsubscribe = _unsubscribeRe.hasMatch(searchText);
    final hasMarketingWords = _marketingHintRe.hasMatch(searchText);
    if ((hasUnsubscribe || hasMarketingWords) && !hasStrongVerb) return null;

    // Amount — take the LARGEST monetary value. Receipts usually have several
    // numbers (items, taxes, shipping, discounts, grand total); the largest
    // tends to be the grand total.
    double? amount;
    for (final m in _amountRe.allMatches(searchText)) {
      final raw = m.group(1)!.replaceAll(',', '');
      final v = double.tryParse(raw);
      if (v == null || v <= 0) continue;
      if (amount == null || v > amount) amount = v;
    }
    if (amount == null) return null;

    // Unrealistically large amounts (₹1,00,000+) must have a VERY strong
    // signal. Guards against marketing copy that quotes historical or
    // comparative figures.
    if (amount >= 100000 && !_strongTxnVerbRe.hasMatch(searchText)) return null;

    final type = hasCredit && !hasPaid ? TxnType.credit : TxnType.debit;

    final senderDomain = _extractDomain(sender);
    final senderRule = SenderRules.match(senderDomain);
    final merchant = senderRule?.displayName ?? _merchantFromSubject(subject) ?? senderDomain;
    final categoryHint = senderRule?.category;
    final refNo = _refRe.firstMatch(searchText)?.group(1);
    final orderId = _orderRe.firstMatch(searchText)?.group(1);

    // Sanity check — unknown-sender + tiny amount: almost always noise.
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

  /// Quick pre-filter used by the Gmail scanner.
  static bool looksFinancial(String subject, String body) {
    final combined = '$subject\n${_stripHtml(body)}';
    if (_otpRe.hasMatch(combined)) return false;
    if (!_amountRe.hasMatch(combined)) return false;
    return _paidVerbRe.hasMatch(combined) || _creditRe.hasMatch(combined);
  }

  // --- Patterns ---

  static final _amountRe = RegExp(
    r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// Any indication that money changed hands. Broad.
  static final _paidVerbRe = RegExp(
    r'\b(paid|payment\s+(?:successful|received|made|of|confirmation)|charged|debited|you\s+spent|you\s+bought|order\s+placed|purchase(?:d)?|successfully\s+paid|has\s+been\s+(?:paid|charged|debited))\b',
    caseSensitive: false,
  );

  /// Inbound money wording.
  static final _creditRe = RegExp(
    r'\b(refund(?:ed)?|credited|money\s+received|cashback|you\s+received|has\s+been\s+(?:refunded|credited))\b',
    caseSensitive: false,
  );

  /// Strong transactional signals — used to overrule promo filters and to
  /// authorize large amounts. Must be a phrase that *cannot* appear in a
  /// promotional email.
  static final _strongTxnVerbRe = RegExp(
    r'(payment\s+successful|payment\s+confirmation|payment\s+received|order\s+confirmation|successfully\s+paid|has\s+been\s+(?:paid|debited|credited|charged|refunded)|thank\s+you\s+for\s+(?:your\s+)?(?:order|payment|purchase)|transaction\s+successful|invoice\s+for\s+your\s+order|receipt\s+for|booking\s+confirmed)',
    caseSensitive: false,
  );

  static final _otpRe = RegExp(
    r'\b(otp|one\s*time\s*password|verification\s*code|security\s*code|login\s*code)\b',
    caseSensitive: false,
  );

  static final _unsubscribeRe = RegExp(r'\bunsubscribe\b', caseSensitive: false);

  /// Words that strongly suggest marketing/promotional content. When present
  /// we require a strong transactional verb to accept the email.
  static final _marketingHintRe = RegExp(
    r'\b(deals?|offer|discount|sale|save\s+up\s+to|flat\s+\d+%|upto\s+\d+%|limited\s+time|flash\s+sale|best\s+price|explore\s+(?:now|deals)|starts?\s+(?:at|from)|book\s+now|shop\s+now|browse\s+our|newsletter|promotional)\b',
    caseSensitive: false,
  );

  static final _shippedOnlyRe = RegExp(
    r'\b(shipped|out\s+for\s+delivery|delivered)\b',
    caseSensitive: false,
  );

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
    var out = s
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
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
    final m = RegExp(r'^[Yy]our\s+([A-Za-z][A-Za-z0-9\.\-]+)').firstMatch(subject);
    if (m != null) return m.group(1);
    final m2 = RegExp(r'^([A-Z][A-Za-z0-9\.]+)').firstMatch(subject.trim());
    if (m2 != null) return m2.group(1);
    return null;
  }
}
