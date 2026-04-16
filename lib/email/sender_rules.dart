class SenderRule {
  final String domainSuffix;
  final String displayName;
  final String? category;

  const SenderRule(this.domainSuffix, this.displayName, {this.category});
}

/// Seed data — the built-in list of merchants + banks we recognize by
/// email domain. `SenderRegistry` copies these into the DB on first run
/// and uses the DB as the source of truth thereafter (so the user can
/// toggle defaults, add their own, etc.).
class SenderRules {
  static const defaults = <SenderRule>[
    // --- Food & Dining ---
    SenderRule('swiggy.in', 'Swiggy', category: 'Food & Dining'),
    SenderRule('zomato.com', 'Zomato', category: 'Food & Dining'),
    SenderRule('eatsure.com', 'EatSure', category: 'Food & Dining'),
    SenderRule('dominos.co.in', "Domino's", category: 'Food & Dining'),
    SenderRule('mcdonaldsindia.com', "McDonald's", category: 'Food & Dining'),
    SenderRule('licious.com', 'Licious', category: 'Food & Dining'),

    // --- Shopping ---
    SenderRule('amazon.in', 'Amazon', category: 'Shopping'),
    SenderRule('amazon.com', 'Amazon', category: 'Shopping'),
    SenderRule('flipkart.com', 'Flipkart', category: 'Shopping'),
    SenderRule('myntra.com', 'Myntra', category: 'Shopping'),
    SenderRule('ajio.com', 'Ajio', category: 'Shopping'),
    SenderRule('meesho.com', 'Meesho', category: 'Shopping'),
    SenderRule('nykaa.com', 'Nykaa', category: 'Shopping'),
    SenderRule('croma.com', 'Croma', category: 'Shopping'),
    SenderRule('tatadigital.com', 'Tata Neu', category: 'Shopping'),
    SenderRule('lenskart.com', 'Lenskart', category: 'Shopping'),
    SenderRule('decathlon.in', 'Decathlon', category: 'Shopping'),
    SenderRule('purplle.com', 'Purplle', category: 'Shopping'),
    SenderRule('firstcry.com', 'FirstCry', category: 'Shopping'),
    SenderRule('uniqlo.com', 'Uniqlo', category: 'Shopping'),

    // --- Groceries ---
    SenderRule('bigbasket.com', 'BigBasket', category: 'Groceries'),
    SenderRule('blinkit.com', 'Blinkit', category: 'Groceries'),
    SenderRule('grofers.com', 'Blinkit', category: 'Groceries'),
    SenderRule('zeptonow.com', 'Zepto', category: 'Groceries'),
    SenderRule('dmart.in', 'DMart', category: 'Groceries'),
    SenderRule('countrydelight.in', 'Country Delight', category: 'Groceries'),

    // --- Transport ---
    SenderRule('uber.com', 'Uber', category: 'Transport'),
    SenderRule('olacabs.com', 'Ola', category: 'Transport'),
    SenderRule('rapido.bike', 'Rapido', category: 'Transport'),
    SenderRule('irctc.co.in', 'IRCTC', category: 'Transport'),
    SenderRule('redbus.in', 'RedBus', category: 'Transport'),
    SenderRule('goindigo.in', 'IndiGo', category: 'Transport'),
    SenderRule('airindia.com', 'Air India', category: 'Transport'),

    // --- Entertainment ---
    SenderRule('netflix.com', 'Netflix', category: 'Entertainment'),
    SenderRule('spotify.com', 'Spotify', category: 'Entertainment'),
    SenderRule('hotstar.com', 'Hotstar', category: 'Entertainment'),
    SenderRule('primevideo.com', 'Prime Video', category: 'Entertainment'),
    SenderRule('youtube.com', 'YouTube', category: 'Entertainment'),
    SenderRule('jiosaavn.com', 'JioSaavn', category: 'Entertainment'),

    // --- Bills & Utilities ---
    SenderRule('airtel.in', 'Airtel', category: 'Bills & Utilities'),
    SenderRule('jio.com', 'Jio', category: 'Bills & Utilities'),
    SenderRule('vi.com', 'Vi', category: 'Bills & Utilities'),
    SenderRule('tatapower.com', 'Tata Power', category: 'Bills & Utilities'),
    SenderRule('bescom.org', 'BESCOM', category: 'Bills & Utilities'),
    SenderRule('adanielectricity.com', 'Adani Electricity', category: 'Bills & Utilities'),

    // --- Health ---
    SenderRule('1mg.com', 'Tata 1mg', category: 'Health'),
    SenderRule('pharmeasy.in', 'PharmEasy', category: 'Health'),
    SenderRule('apollo247.com', 'Apollo 24|7', category: 'Health'),
    SenderRule('practo.com', 'Practo', category: 'Health'),
    SenderRule('medplusmart.com', 'MedPlus', category: 'Health'),
    SenderRule('cult.fit', 'Cult.fit', category: 'Health'),
    SenderRule('urban-company.com', 'Urban Company', category: 'Health'),

    // --- Transfer / payment aggregators ---
    SenderRule('cred.club', 'CRED', category: 'Transfer'),
    SenderRule('paytm.com', 'Paytm', category: 'Transfer'),
    SenderRule('phonepe.com', 'PhonePe', category: 'Transfer'),
    SenderRule('razorpay.com', 'Razorpay'),
    SenderRule('payu.in', 'PayU'),
    SenderRule('juspay.in', 'Juspay'),
    SenderRule('billdesk.com', 'BillDesk'),
    SenderRule('npci.org.in', 'NPCI / UPI'),
    SenderRule('magicpin.com', 'Magicpin', category: 'Shopping'),

    // --- Banks (primary domains) ---
    SenderRule('hdfcbank.com', 'HDFC Bank'),
    SenderRule('icicibank.com', 'ICICI Bank'),
    SenderRule('axisbank.com', 'Axis Bank'),
    SenderRule('sbi.co.in', 'SBI'),
    SenderRule('kotak.com', 'Kotak'),
    SenderRule('yesbank.in', 'Yes Bank'),
    SenderRule('pnbindia.in', 'PNB'),
    SenderRule('bankofbaroda.co.in', 'Bank of Baroda'),
    SenderRule('rblbank.com', 'RBL Bank'),
    SenderRule('aubank.in', 'AU Bank'),
    SenderRule('indusind.com', 'IndusInd Bank'),
    SenderRule('idfcfirstbank.com', 'IDFC First'),
    SenderRule('idbi.com', 'IDBI Bank'),
    SenderRule('federalbank.co.in', 'Federal Bank'),
    SenderRule('canarabank.com', 'Canara Bank'),
    SenderRule('unionbankofindia.co.in', 'Union Bank'),

    // --- Bank sibling / transactional domains ---
    // UPI confirmations and card statements often come from these, not the
    // main `.com` / `.co.in` domain.
    SenderRule('hdfcbank.net', 'HDFC Bank'),
    SenderRule('icicibank.net', 'ICICI Bank'),
    SenderRule('axisbank.net', 'Axis Bank'),
    SenderRule('sbicard.com', 'SBI Card'),
    SenderRule('kotak.net', 'Kotak'),
    SenderRule('hdfcsec.com', 'HDFC Securities'),
  ];
}
