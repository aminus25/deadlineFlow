import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

enum Priority { low, medium, high }

class Deadline {
  final int? id;
  final String title;
  final String category;
  final DateTime dueDate;
  final DateTime createdAt;
  final Priority priority;
  bool isDone;
  bool isOverdueNotified;

  Deadline({
    this.id,
    required this.title,
    required this.category,
    required this.dueDate,
    DateTime? createdAt,
    required this.priority,
    this.isDone = false,
    this.isOverdueNotified = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'due_date': dueDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'priority': priority.name,
      'is_done': isDone ? 1 : 0,
      'is_overdue_notified': isOverdueNotified ? 1 : 0,
    };
  }

  factory Deadline.fromMap(Map<String, dynamic> map) {
    return Deadline(
      id: map['id'],
      title: map['title'],
      category: map['category'] ?? map['subject'] ?? 'Без категории',
      dueDate: DateTime.parse(map['due_date']),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      priority: Priority.values.firstWhere((p) => p.name == map['priority']),
      isDone: map['is_done'] == 1,
      isOverdueNotified: map['is_overdue_notified'] == 1,
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('deadlineflow.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 3,                    // ← Увеличили версию
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE deadlines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        due_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        priority TEXT NOT NULL,
        is_done INTEGER NOT NULL DEFAULT 0,
        is_overdue_notified INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE deadlines ADD COLUMN category TEXT');
        await db.execute("UPDATE deadlines SET category = IFNULL(subject, 'Без категории')");
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE deadlines ADD COLUMN created_at TEXT');
        await db.execute("UPDATE deadlines SET created_at = due_date");
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE deadlines ADD COLUMN is_overdue_notified INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }

    if (oldVersion < 3) {
      // Удаляем старую колонку subject, если она есть
      try {
        final columns = await db.rawQuery("PRAGMA table_info(deadlines)");
        final hasSubject = columns.any((col) => col['name'] == 'subject');
        if (hasSubject) {
          // SQLite не поддерживает DROP COLUMN напрямую, поэтому создаём новую таблицу
          await _migrateToNewSchema(db);
        }
      } catch (_) {}
    }
  }

  // Полная миграция (на случай, если subject всё ещё мешает)
  Future<void> _migrateToNewSchema(Database db) async {
    await db.execute('''
      CREATE TABLE deadlines_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        due_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        priority TEXT NOT NULL,
        is_done INTEGER NOT NULL DEFAULT 0,
        is_overdue_notified INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      INSERT INTO deadlines_new 
      SELECT id, title, IFNULL(category, IFNULL(subject, 'Без категории')), 
             due_date, IFNULL(created_at, due_date), priority, 
             is_done, IFNULL(is_overdue_notified, 0)
      FROM deadlines
    ''');

    await db.execute('DROP TABLE deadlines');
    await db.execute('ALTER TABLE deadlines_new RENAME TO deadlines');
  }

  Future<Deadline> create(Deadline deadline) async {
    final db = await instance.database;
    final id = await db.insert('deadlines', deadline.toMap());
    return deadline.copyWith(id: id);
  }

  Future<List<Deadline>> readAll() async {
    final db = await instance.database;
    final result = await db.query('deadlines', orderBy: 'due_date ASC');
    return result.map((map) => Deadline.fromMap(map)).toList();
  }

  Future<int> update(Deadline deadline) async {
    final db = await instance.database;
    return db.update('deadlines', deadline.toMap(), where: 'id = ?', whereArgs: [deadline.id]);
  }

  Future<int> delete(int id) async {
    final db = await instance.database;
    return db.delete('deadlines', where: 'id = ?', whereArgs: [id]);
  }
}

// Расширение для удобства
extension DeadlineCopy on Deadline {
  Deadline copyWith({int? id}) {
    return Deadline(
      id: id ?? this.id,
      title: title,
      category: category,
      dueDate: dueDate,
      createdAt: createdAt,
      priority: priority,
      isDone: isDone,
      isOverdueNotified: isOverdueNotified,
    );
  }
}