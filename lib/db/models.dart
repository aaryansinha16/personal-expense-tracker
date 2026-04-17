class TxnType {
  static const debit = 'debit';
  static const credit = 'credit';
  /// Intra-account movement (e.g. CC cash advance to a bank account). Does
  /// NOT count in expense/income totals. Has both account_id (from) and
  /// to_account_id (to).
  static const transfer = 'transfer';
}

class AccountType {
  static const cash = 'cash';
  static const bank = 'bank';
  static const creditCard = 'credit_card';
  static const wallet = 'wallet';
}

class Account {
  final int? id;
  final String name;
  final String type;
  final String? issuer;
  final String? last4;
  final int color;
  final int icon;
  final double? creditLimit;
  final int? statementDay;
  final int? dueDay;
  final bool active;
  final int sortOrder;

  Account({
    this.id,
    required this.name,
    required this.type,
    this.issuer,
    this.last4,
    required this.color,
    required this.icon,
    this.creditLimit,
    this.statementDay,
    this.dueDay,
    this.active = true,
    this.sortOrder = 0,
  });

  bool get isCreditCard => type == AccountType.creditCard;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'type': type,
        'issuer': issuer,
        'last_4': last4,
        'color': color,
        'icon': icon,
        'credit_limit': creditLimit,
        'statement_day': statementDay,
        'due_day': dueDay,
        'active': active ? 1 : 0,
        'sort_order': sortOrder,
      };

  factory Account.fromMap(Map<String, dynamic> m) => Account(
        id: m['id'] as int?,
        name: m['name'] as String,
        type: m['type'] as String,
        issuer: m['issuer'] as String?,
        last4: m['last_4'] as String?,
        color: m['color'] as int,
        icon: m['icon'] as int,
        creditLimit: (m['credit_limit'] as num?)?.toDouble(),
        statementDay: m['statement_day'] as int?,
        dueDay: m['due_day'] as int?,
        active: ((m['active'] as int?) ?? 1) == 1,
        sortOrder: (m['sort_order'] as int?) ?? 0,
      );

  Account copyWith({
    int? id,
    String? name,
    String? type,
    String? issuer,
    String? last4,
    int? color,
    int? icon,
    double? creditLimit,
    int? statementDay,
    int? dueDay,
    bool? active,
    int? sortOrder,
  }) =>
      Account(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        issuer: issuer ?? this.issuer,
        last4: last4 ?? this.last4,
        color: color ?? this.color,
        icon: icon ?? this.icon,
        creditLimit: creditLimit ?? this.creditLimit,
        statementDay: statementDay ?? this.statementDay,
        dueDay: dueDay ?? this.dueDay,
        active: active ?? this.active,
        sortOrder: sortOrder ?? this.sortOrder,
      );
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
  /// The account this transaction came FROM. Null for legacy rows that
  /// haven't been assigned yet.
  final int? accountId;
  /// For `type: transfer`, the account the money moved TO. Null otherwise.
  final int? toAccountId;

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
    this.accountId,
    this.toAccountId,
  });

  bool get isTransfer => type == TxnType.transfer;

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
        'account_id': accountId,
        'to_account_id': toAccountId,
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
        accountId: m['account_id'] as int?,
        toAccountId: m['to_account_id'] as int?,
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
    int? accountId,
    int? toAccountId,
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
        accountId: accountId ?? this.accountId,
        toAccountId: toAccountId ?? this.toAccountId,
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

class PendingEmail {
  final int? id;
  final String? messageId;
  final String sender;
  final String? subject;
  final String body;
  final DateTime receivedAt;
  final String? reason;

  PendingEmail({
    this.id,
    this.messageId,
    required this.sender,
    this.subject,
    required this.body,
    required this.receivedAt,
    this.reason,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'message_id': messageId,
        'sender': sender,
        'subject': subject,
        'body': body,
        'received_at': receivedAt.millisecondsSinceEpoch,
        'reason': reason,
      };

  factory PendingEmail.fromMap(Map<String, dynamic> m) => PendingEmail(
        id: m['id'] as int?,
        messageId: m['message_id'] as String?,
        sender: m['sender'] as String,
        subject: m['subject'] as String?,
        body: m['body'] as String,
        receivedAt: DateTime.fromMillisecondsSinceEpoch(m['received_at'] as int),
        reason: m['reason'] as String?,
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
