import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/history_entry.dart';
import '../models/notification_entry.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  // Lịch sử phiên bản CSDL:
  //   1 -> bảng history
  //   2 -> thêm bảng notifications
  //   3 -> thêm cột image_crop        (ảnh bằng chứng — đã bỏ ở bản 5)
  //   4 -> thêm cột evidence_caption  (chú thích ảnh — đã bỏ ở bản 5)
  //   5 -> bỏ hẳn ảnh bằng chứng: xoá dữ liệu ảnh/chú thích đã lưu. Hai cột cũ vẫn còn ở máy
  //        nâng cấp từ bản cũ (luôn rỗng, mã không đọc/ghi nữa); máy cài mới không có hai cột này.
  //        Không dùng DROP COLUMN vì SQLite của Android đời cũ không hỗ trợ.
  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'microart.db');
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            result TEXT NOT NULL,
            confidence REAL NOT NULL,
            description TEXT NOT NULL,
            timestamp TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            is_read INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE notifications (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              body TEXT NOT NULL,
              timestamp TEXT NOT NULL,
              is_read INTEGER NOT NULL DEFAULT 0
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE history ADD COLUMN image_crop TEXT');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE history ADD COLUMN evidence_caption TEXT');
        }
        if (oldVersion < 5) {
          // Bỏ hẳn ảnh bằng chứng: xoá ảnh và chú thích đã lưu ở các phiên cũ.
          await db.execute('UPDATE history SET image_crop = NULL, evidence_caption = NULL');
        }
      },
    );
  }

  Future<int> insertHistory(HistoryEntry entry) async {
    final db = await database;
    return db.insert('history', entry.toMap());
  }

  Future<List<HistoryEntry>> getAllHistory() async {
    final db = await database;
    final maps = await db.query('history', orderBy: 'timestamp DESC');
    return maps.map((m) => HistoryEntry.fromMap(m)).toList();
  }

  Future<void> deleteAllHistory() async {
    final db = await database;
    await db.delete('history');
  }

  Future<int> insertNotification(NotificationEntry entry) async {
    final db = await database;
    return db.insert('notifications', entry.toMap());
  }

  Future<List<NotificationEntry>> getAllNotifications() async {
    final db = await database;
    final maps = await db.query('notifications', orderBy: 'timestamp DESC');
    return maps.map((m) => NotificationEntry.fromMap(m)).toList();
  }

  Future<void> markNotificationRead(int id) async {
    final db = await database;
    await db.update('notifications', {'is_read': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markAllNotificationsRead() async {
    final db = await database;
    await db.update('notifications', {'is_read': 1});
  }
}
