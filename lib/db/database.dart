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
      version: 1,
      onCreate: _onCreate,
    );
    return _db!;
  }

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
}
