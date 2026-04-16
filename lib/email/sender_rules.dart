class SenderRule {
  final String domainSuffix;
  final String displayName;
  final String? category; // display name of a default category

  const SenderRule(this.domainSuffix, this.displayName, {this.category});
}

/// Known email senders we can categorize automatically.
/// Matched by domain suffix (e.g. "swiggy.in" matches "orders@swiggy.in").
class SenderRules {
  static const _rules = <SenderRule>[
    SenderRule('swiggy.in', 'Swiggy', category: 'Food & Dining'),
    SenderRule('zomato.com', 'Zomato', category: 'Food & Dining'),
    SenderRule('eatsure.com', 'EatSure', category: 'Food & Dining'),
    SenderRule('dominos.co.in', "Domino's", category: 'Food & Dining'),
    SenderRule('mcdonaldsindia.com', "McDonald's", category: 'Food & Dining'),

    SenderRule('amazon.in', 'Amazon', category: 'Shopping'),
    SenderRule('amazon.com', 'Amazon', category: 'Shopping'),
    SenderRule('flipkart.com', 'Flipkart', category: 'Shopping'),
    SenderRule('myntra.com', 'Myntra', category: 'Shopping'),
    SenderRule('ajio.com', 'Ajio', category: 'Shopping'),
    SenderRule('meesho.com', 'Meesho', category: 'Shopping'),
    SenderRule('nykaa.com', 'Nykaa', category: 'Shopping'),
    SenderRule('croma.com', 'Croma', category: 'Shopping'),

    SenderRule('bigbasket.com', 'BigBasket', category: 'Groceries'),
    SenderRule('blinkit.com', 'Blinkit', category: 'Groceries'),
    SenderRule('grofers.com', 'Blinkit', category: 'Groceries'),
    SenderRule('zeptonow.com', 'Zepto', category: 'Groceries'),
    SenderRule('dmart.in', 'DMart', category: 'Groceries'),

    SenderRule('uber.com', 'Uber', category: 'Transport'),
    SenderRule('olacabs.com', 'Ola', category: 'Transport'),
    SenderRule('rapido.bike', 'Rapido', category: 'Transport'),
    SenderRule('irctc.co.in', 'IRCTC', category: 'Transport'),
    SenderRule('redbus.in', 'RedBus', category: 'Transport'),
    SenderRule('goindigo.in', 'IndiGo', category: 'Transport'),
    SenderRule('airindia.com', 'Air India', category: 'Transport'),

    SenderRule('netflix.com', 'Netflix', category: 'Entertainment'),
    SenderRule('spotify.com', 'Spotify', category: 'Entertainment'),
    SenderRule('hotstar.com', 'Hotstar', category: 'Entertainment'),
    SenderRule('primevideo.com', 'Prime Video', category: 'Entertainment'),
    SenderRule('youtube.com', 'YouTube', category: 'Entertainment'),
    SenderRule('jiosaavn.com', 'JioSaavn', category: 'Entertainment'),

    SenderRule('airtel.in', 'Airtel', category: 'Bills & Utilities'),
    SenderRule('jio.com', 'Jio', category: 'Bills & Utilities'),
    SenderRule('vi.com', 'Vi', category: 'Bills & Utilities'),
    SenderRule('tatapower.com', 'Tata Power', category: 'Bills & Utilities'),
    SenderRule('bescom.org', 'BESCOM', category: 'Bills & Utilities'),
    SenderRule('adanielectricity.com', 'Adani Electricity', category: 'Bills & Utilities'),

    SenderRule('1mg.com', 'Tata 1mg', category: 'Health'),
    SenderRule('pharmeasy.in', 'PharmEasy', category: 'Health'),
    SenderRule('apollo247.com', 'Apollo 24|7', category: 'Health'),
    SenderRule('practo.com', 'Practo', category: 'Health'),
    SenderRule('medplusmart.com', 'MedPlus', category: 'Health'),

    SenderRule('cred.club', 'CRED', category: 'Transfer'),
    SenderRule('paytm.com', 'Paytm', category: 'Transfer'),
    SenderRule('phonepe.com', 'PhonePe', category: 'Transfer'),
    SenderRule('razorpay.com', 'Razorpay'),
    SenderRule('payu.in', 'PayU'),

    SenderRule('hdfcbank.com', 'HDFC Bank'),
    SenderRule('icicibank.com', 'ICICI Bank'),
    SenderRule('axisbank.com', 'Axis Bank'),
    SenderRule('sbi.co.in', 'SBI'),
    SenderRule('kotak.com', 'Kotak'),
    SenderRule('yesbank.in', 'Yes Bank'),
  ];

  static SenderRule? match(String domain) {
    final d = domain.toLowerCase();
    for (final r in _rules) {
      if (d == r.domainSuffix || d.endsWith('.${r.domainSuffix}') || d.endsWith(r.domainSuffix)) {
        return r;
      }
    }
    return null;
  }

  /// Gmail search query matching financial senders — used by the Gmail scanner.
  static String gmailQuery() {
    final fromClauses = _rules.map((r) => 'from:${r.domainSuffix}').join(' OR ');
    return '($fromClauses) -subject:otp -subject:"verification code"';
  }

  static List<SenderRule> get all => List.unmodifiable(_rules);
}
