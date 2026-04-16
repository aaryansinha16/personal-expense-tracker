import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class AppDb {
  static final AppDb instance = AppDb._();
  AppDb._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'expense_tracker.db');
    _db = await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(_recurringExpensesSchema);
    }
    if (oldVersion < 3) {
      await db.execute(_processedEmailsSchema);
    }
    if (oldVersion < 4) {
      await db.execute(_emailSendersSchema);
    }
  }

  static const _recurringExpensesSchema = '''
    CREATE TABLE recurring_expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      amount REAL NOT NULL,
      category_id INTEGER,
      day_of_month INTEGER NOT NULL,
      active INTEGER NOT NULL DEFAULT 1,
      FOREIGN KEY(category_id) REFERENCES categories(id)
    )
  ''';

  static const _processedEmailsSchema = '''
    CREATE TABLE processed_emails (
      message_id TEXT PRIMARY KEY,
      processed_at INTEGER NOT NULL
    )
  ''';

  static const _emailSendersSchema = '''
    CREATE TABLE email_senders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      domain_suffix TEXT NOT NULL UNIQUE,
      display_name TEXT NOT NULL,
      category_hint TEXT,
      is_default INTEGER NOT NULL DEFAULT 0,
      enabled INTEGER NOT NULL DEFAULT 1
    )
  ''';

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        icon INTEGER NOT NULL,
        color INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        category_id INTEGER,
        merchant TEXT,
        date INTEGER NOT NULL,
        source TEXT NOT NULL,
        raw_sms TEXT,
        account TEXT,
        note TEXT,
        FOREIGN KEY(category_id) REFERENCES categories(id)
      )
    ''');
    await db.execute('CREATE INDEX idx_txn_date ON transactions(date)');
    await db.execute('CREATE INDEX idx_txn_type ON transactions(type)');
    await db.execute('''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL UNIQUE,
        monthly_limit REAL NOT NULL,
        FOREIGN KEY(category_id) REFERENCES categories(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE merchant_map (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pattern TEXT NOT NULL UNIQUE,
        category_id INTEGER NOT NULL,
        FOREIGN KEY(category_id) REFERENCES categories(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE pending_sms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender TEXT NOT NULL,
        body TEXT NOT NULL,
        received_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE processed_sms (
        hash TEXT PRIMARY KEY,
        processed_at INTEGER NOT NULL
      )
    ''');
    await db.execute(_recurringExpensesSchema);
    await db.execute(_processedEmailsSchema);
    await db.execute(_emailSendersSchema);

    await _seedCategories(db);
  }

  Future<void> _seedCategories(Database db) async {
    final defaults = [
      {'name': 'Food & Dining', 'icon': Icons.restaurant.codePoint, 'color': 0xFFE57373},
      {'name': 'Groceries', 'icon': Icons.shopping_basket.codePoint, 'color': 0xFF81C784},
      {'name': 'Transport', 'icon': Icons.directions_car.codePoint, 'color': 0xFF64B5F6},
      {'name': 'Shopping', 'icon': Icons.shopping_bag.codePoint, 'color': 0xFFBA68C8},
      {'name': 'Bills & Utilities', 'icon': Icons.receipt_long.codePoint, 'color': 0xFFFFB74D},
      {'name': 'Entertainment', 'icon': Icons.movie.codePoint, 'color': 0xFFF06292},
      {'name': 'Health', 'icon': Icons.local_hospital.codePoint, 'color': 0xFF4DB6AC},
      {'name': 'Rent', 'icon': Icons.home.codePoint, 'color': 0xFF9575CD},
      {'name': 'Investments', 'icon': Icons.trending_up.codePoint, 'color': 0xFF4FC3F7},
      {'name': 'Transfer', 'icon': Icons.swap_horiz.codePoint, 'color': 0xFF90A4AE},
      {'name': 'Income', 'icon': Icons.payments.codePoint, 'color': 0xFF66BB6A},
      {'name': 'Other', 'icon': Icons.category.codePoint, 'color': 0xFFBDBDBD},
    ];
    for (final c in defaults) {
      await db.insert('categories', c);
    }
  }

  // Categories
  Future<List<Category>> listCategories() async {
    final d = await db;
    final rows = await d.query('categories', orderBy: 'name');
    return rows.map(Category.fromMap).toList();
  }

  Future<int> insertCategory(Category c) async =>
      (await db).insert('categories', c.toMap());

  Future<int> updateCategory(Category c) async =>
      (await db).update('categories', c.toMap(), where: 'id=?', whereArgs: [c.id]);

  Future<int> deleteCategory(int id) async =>
      (await db).delete('categories', where: 'id=?', whereArgs: [id]);

  // Transactions
  Future<int> insertTxn(Txn t) async => (await db).insert('transactions', t.toMap());

  Future<int> updateTxn(Txn t) async =>
      (await db).update('transactions', t.toMap(), where: 'id=?', whereArgs: [t.id]);

  Future<int> deleteTxn(int id) async =>
      (await db).delete('transactions', where: 'id=?', whereArgs: [id]);

  Future<List<Txn>> listTxns({DateTime? from, DateTime? to, int? categoryId, String? type, int? limit}) async {
    final d = await db;
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('date >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(to.millisecondsSinceEpoch);
    }
    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type);
    }
    final rows = await d.query(
      'transactions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC',
      limit: limit,
    );
    return rows.map(Txn.fromMap).toList();
  }

  // Budgets
  Future<List<Budget>> listBudgets() async {
    final rows = await (await db).query('budgets');
    return rows.map(Budget.fromMap).toList();
  }

  Future<int> upsertBudget(Budget b) async {
    final d = await db;
    return d.insert('budgets', b.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> deleteBudget(int categoryId) async =>
      (await db).delete('budgets', where: 'category_id=?', whereArgs: [categoryId]);

  // Merchant map
  Future<List<MerchantMap>> listMerchantMap() async {
    final rows = await (await db).query('merchant_map');
    return rows.map(MerchantMap.fromMap).toList();
  }

  Future<int> upsertMerchantMap(MerchantMap m) async =>
      (await db).insert('merchant_map', m.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  // Pending SMS
  Future<int> insertPendingSms(PendingSms s) async =>
      (await db).insert('pending_sms', s.toMap());

  Future<List<PendingSms>> listPendingSms() async {
    final rows = await (await db).query('pending_sms', orderBy: 'received_at DESC');
    return rows.map(PendingSms.fromMap).toList();
  }

  Future<int> deletePendingSms(int id) async =>
      (await db).delete('pending_sms', where: 'id=?', whereArgs: [id]);

  // Processed SMS dedup
  Future<bool> isSmsProcessed(String hash) async {
    final d = await db;
    final rows = await d.query('processed_sms', where: 'hash=?', whereArgs: [hash], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> markSmsProcessed(String hash) async {
    final d = await db;
    await d.insert(
      'processed_sms',
      {'hash': hash, 'processed_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // Processed Email dedup
  Future<bool> isEmailProcessed(String messageId) async {
    final d = await db;
    final rows = await d.query('processed_emails', where: 'message_id=?', whereArgs: [messageId], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> markEmailProcessed(String messageId) async {
    final d = await db;
    await d.insert(
      'processed_emails',
      {'message_id': messageId, 'processed_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<EmailResetResult> resetEmailSync({bool deleteEmailTxns = true}) async {
    final d = await db;
    return await d.transaction((txn) async {
      final processedDel = await txn.delete('processed_emails');
      int txnsDel = 0;
      if (deleteEmailTxns) {
        txnsDel = await txn.delete('transactions', where: 'source = ?', whereArgs: [TxnSource.email]);
      }
      return EmailResetResult(
        processedDeleted: processedDel,
        emailTxnsDeleted: txnsDel,
      );
    });
  }

  // Aggregates
  Future<Map<String, double>> totalsByType(DateTime from, DateTime to) async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT type, SUM(amount) as total FROM transactions WHERE date >= ? AND date <= ? GROUP BY type',
      [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );
    final out = {'debit': 0.0, 'credit': 0.0};
    for (final r in rows) {
      out[r['type'] as String] = (r['total'] as num).toDouble();
    }
    return out;
  }

  Future<List<Map<String, Object?>>> totalsByCategory(DateTime from, DateTime to, {String type = 'debit'}) async {
    final d = await db;
    return d.rawQuery(
      '''SELECT c.id as category_id, c.name, c.icon, c.color, SUM(t.amount) as total, COUNT(*) as count
         FROM transactions t
         LEFT JOIN categories c ON c.id = t.category_id
         WHERE t.date >= ? AND t.date <= ? AND t.type = ?
         GROUP BY c.id
         ORDER BY total DESC''',
      [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch, type],
    );
  }

  Future<List<Map<String, Object?>>> dailyTotals(DateTime from, DateTime to, {String type = 'debit'}) async {
    final d = await db;
    return d.rawQuery(
      '''SELECT date/86400000 as day, SUM(amount) as total
         FROM transactions
         WHERE date >= ? AND date <= ? AND type = ?
         GROUP BY day
         ORDER BY day ASC''',
      [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch, type],
    );
  }

  // SMS sync reset
  Future<SmsResetResult> resetSmsSync({bool deleteSmsTxns = true, bool deletePending = true}) async {
    final d = await db;
    return await d.transaction((txn) async {
      final processedDel = await txn.delete('processed_sms');
      int txnsDel = 0;
      if (deleteSmsTxns) {
        txnsDel = await txn.delete('transactions', where: 'source = ?', whereArgs: [TxnSource.sms]);
      }
      int pendingDel = 0;
      if (deletePending) {
        pendingDel = await txn.delete('pending_sms');
      }
      return SmsResetResult(
        processedDeleted: processedDel,
        smsTxnsDeleted: txnsDel,
        pendingDeleted: pendingDel,
      );
    });
  }

  // Recurring expenses
  Future<List<RecurringExpense>> listRecurringExpenses({bool onlyActive = false}) async {
    final d = await db;
    final rows = await d.query(
      'recurring_expenses',
      where: onlyActive ? 'active = 1' : null,
      orderBy: 'day_of_month ASC',
    );
    return rows.map(RecurringExpense.fromMap).toList();
  }

  Future<int> upsertRecurringExpense(RecurringExpense r) async {
    final d = await db;
    if (r.id == null) return d.insert('recurring_expenses', r.toMap());
    return d.update('recurring_expenses', r.toMap(), where: 'id=?', whereArgs: [r.id]);
  }

  Future<int> deleteRecurringExpense(int id) async =>
      (await db).delete('recurring_expenses', where: 'id=?', whereArgs: [id]);

  // Email senders
  Future<List<Map<String, Object?>>> listEmailSenders() async {
    final d = await db;
    return d.query('email_senders', orderBy: 'category_hint ASC, display_name ASC');
  }

  /// Insert a default sender if it doesn't exist yet. Existing rows are
  /// left alone so user toggles/renames are preserved across app updates.
  Future<void> seedDefaultSenderIfMissing({
    required String domainSuffix,
    required String displayName,
    String? categoryHint,
  }) async {
    final d = await db;
    await d.insert(
      'email_senders',
      {
        'domain_suffix': domainSuffix,
        'display_name': displayName,
        'category_hint': categoryHint,
        'is_default': 1,
        'enabled': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> upsertEmailSender({
    int? id,
    required String domainSuffix,
    required String displayName,
    String? categoryHint,
    bool isDefault = false,
    bool enabled = true,
  }) async {
    final d = await db;
    final row = {
      'domain_suffix': domainSuffix,
      'display_name': displayName,
      'category_hint': categoryHint,
      'is_default': isDefault ? 1 : 0,
      'enabled': enabled ? 1 : 0,
    };
    if (id != null) {
      return d.update('email_senders', row, where: 'id=?', whereArgs: [id]);
    }
    return d.insert('email_senders', row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> setEmailSenderEnabled(int id, bool enabled) async {
    final d = await db;
    return d.update('email_senders', {'enabled': enabled ? 1 : 0},
        where: 'id=?', whereArgs: [id]);
  }

  /// Only non-default senders can be deleted. Defaults are hidden by toggling
  /// them off instead.
  Future<int> deleteEmailSender(int id) async {
    final d = await db;
    return d.delete('email_senders',
        where: 'id=? AND is_default=0', whereArgs: [id]);
  }
}

class SmsResetResult {
  final int processedDeleted;
  final int smsTxnsDeleted;
  final int pendingDeleted;
  SmsResetResult({
    required this.processedDeleted,
    required this.smsTxnsDeleted,
    required this.pendingDeleted,
  });
}

class EmailResetResult {
  final int processedDeleted;
  final int emailTxnsDeleted;
  EmailResetResult({
    required this.processedDeleted,
    required this.emailTxnsDeleted,
  });
}
