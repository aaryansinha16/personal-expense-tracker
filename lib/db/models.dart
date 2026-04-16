class TxnType {
  static const debit = 'debit';
  static const credit = 'credit';
}

class TxnSource {
  static const sms = 'sms';
  static const email = 'email';
  static const manual = 'manual';
}

class Category {
  final int? id;
  final String name;
  final int icon;
  final int color;

  Category({this.id, required this.name, required this.icon, required this.color});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'icon': icon,
        'color': color,
      };

  factory Category.fromMap(Map<String, dynamic> m) => Category(
        id: m['id'] as int?,
        name: m['name'] as String,
        icon: m['icon'] as int,
        color: m['color'] as int,
      );
}

class Txn {
  final int? id;
  final double amount;
  final String type;
  final int? categoryId;
  final String? merchant;
  final DateTime date;
  final String source;
  final String? rawSms;
  final String? account;
  final String? note;

  Txn({
    this.id,
    required this.amount,
    required this.type,
    this.categoryId,
    this.merchant,
    required this.date,
    required this.source,
    this.rawSms,
    this.account,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'amount': amount,
        'type': type,
        'category_id': categoryId,
        'merchant': merchant,
        'date': date.millisecondsSinceEpoch,
        'source': source,
        'raw_sms': rawSms,
        'account': account,
        'note': note,
      };

  factory Txn.fromMap(Map<String, dynamic> m) => Txn(
        id: m['id'] as int?,
        amount: (m['amount'] as num).toDouble(),
        type: m['type'] as String,
        categoryId: m['category_id'] as int?,
        merchant: m['merchant'] as String?,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        source: m['source'] as String,
        rawSms: m['raw_sms'] as String?,
        account: m['account'] as String?,
        note: m['note'] as String?,
      );

  Txn copyWith({
    int? id,
    double? amount,
    String? type,
    int? categoryId,
    String? merchant,
    DateTime? date,
    String? source,
    String? rawSms,
    String? account,
    String? note,
  }) =>
      Txn(
        id: id ?? this.id,
        amount: amount ?? this.amount,
        type: type ?? this.type,
        categoryId: categoryId ?? this.categoryId,
        merchant: merchant ?? this.merchant,
        date: date ?? this.date,
        source: source ?? this.source,
        rawSms: rawSms ?? this.rawSms,
        account: account ?? this.account,
        note: note ?? this.note,
      );
}

class Budget {
  final int? id;
  final int categoryId;
  final double monthlyLimit;

  Budget({this.id, required this.categoryId, required this.monthlyLimit});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'category_id': categoryId,
        'monthly_limit': monthlyLimit,
      };

  factory Budget.fromMap(Map<String, dynamic> m) => Budget(
        id: m['id'] as int?,
        categoryId: m['category_id'] as int,
        monthlyLimit: (m['monthly_limit'] as num).toDouble(),
      );
}

class MerchantMap {
  final int? id;
  final String pattern;
  final int categoryId;

  MerchantMap({this.id, required this.pattern, required this.categoryId});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'pattern': pattern.toLowerCase(),
        'category_id': categoryId,
      };

  factory MerchantMap.fromMap(Map<String, dynamic> m) => MerchantMap(
        id: m['id'] as int?,
        pattern: m['pattern'] as String,
        categoryId: m['category_id'] as int,
      );
}

class PendingSms {
  final int? id;
  final String sender;
  final String body;
  final DateTime receivedAt;

  PendingSms({this.id, required this.sender, required this.body, required this.receivedAt});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'sender': sender,
        'body': body,
        'received_at': receivedAt.millisecondsSinceEpoch,
      };

  factory PendingSms.fromMap(Map<String, dynamic> m) => PendingSms(
        id: m['id'] as int?,
        sender: m['sender'] as String,
        body: m['body'] as String,
        receivedAt: DateTime.fromMillisecondsSinceEpoch(m['received_at'] as int),
      );
}

class RecurringExpense {
  final int? id;
  final String name;
  final double amount;
  final int? categoryId;
  final int dayOfMonth; // 1-31, clamped to last day if month is shorter
  final bool active;

  RecurringExpense({
    this.id,
    required this.name,
    required this.amount,
    this.categoryId,
    required this.dayOfMonth,
    this.active = true,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'amount': amount,
        'category_id': categoryId,
        'day_of_month': dayOfMonth,
        'active': active ? 1 : 0,
      };

  factory RecurringExpense.fromMap(Map<String, dynamic> m) => RecurringExpense(
        id: m['id'] as int?,
        name: m['name'] as String,
        amount: (m['amount'] as num).toDouble(),
        categoryId: m['category_id'] as int?,
        dayOfMonth: m['day_of_month'] as int,
        active: (m['active'] as int? ?? 1) == 1,
      );

  RecurringExpense copyWith({
    int? id,
    String? name,
    double? amount,
    int? categoryId,
    int? dayOfMonth,
    bool? active,
  }) =>
      RecurringExpense(
        id: id ?? this.id,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        active: active ?? this.active,
      );
}
