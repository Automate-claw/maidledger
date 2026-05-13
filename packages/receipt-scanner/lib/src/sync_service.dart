import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:supabase/supabase.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Offline-first sync service using Timestamp-based strategy
/// Local SQLite <-> Supabase sync
class SyncService {
  final SupabaseClient _supabase;
  final _connectivity = Connectivity();

  Database? _localDb;
  StreamSubscription? _connectivitySubscription;

  SyncService(this._supabase);

  /// Initialize local SQLite database
  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'maidledger_sync.db');

    _localDb = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sync_queue (
            id TEXT PRIMARY KEY,
            table_name TEXT NOT NULL,
            record_id TEXT NOT NULL,
            action TEXT NOT NULL,
            payload TEXT NOT NULL,
            local_timestamp INTEGER NOT NULL,
            server_timestamp INTEGER,
            synced INTEGER DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE receipts (
            id TEXT PRIMARY KEY,
            raw_text TEXT NOT NULL,
            parsed_data TEXT,
            image_path TEXT,
            sync_status TEXT DEFAULT 'pending',
            local_timestamp INTEGER NOT NULL,
            server_timestamp INTEGER,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        _triggerSync();
      }
    });
  }

  /// Queue a receipt for sync (offline-first)
  Future<void> queueReceipt(Receipt receipt) async {
    await _localDb!.insert('receipts', receipt.toMap());
    await _addToSyncQueue('receipts', receipt.id, 'upsert', receipt.toJson());
  }

  /// Get all local pending receipts
  Future<List<Receipt>> getPendingReceipts() async {
    final results = await _localDb!.query(
      'receipts',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
    );
    return results.map((r) => Receipt.fromMap(r)).toList();
  }

  /// Sync pending items to Supabase
  Future<SyncResult> sync() async {
    if (_localDb == null) await init();

    final pending = await _localDb!.query(
      'sync_queue',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
    );

    int synced = 0;
    int failed = 0;

    for (final item in pending) {
      try {
        final payload = Map<String, dynamic>.from(
          (item['payload'] as String).isEmpty
              ? {}
              : (item['payload'] as String).split(',').asMap().map(
                    (k, v) => MapEntry('field_$k', v),
                  ),
        );

        if (item['table_name'] == 'receipts') {
          final response = await _supabase
              .from(item['table_name'] as String)
              .upsert(payload, onConflict: 'id');

          if (response.error != null) throw Exception(response.error!.message);
        }

        // Mark as synced
        await _localDb!.update(
          'sync_queue',
          {'synced': 1, 'server_timestamp': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [item['id']],
        );
        synced++;
      } catch (e) {
        failed++;
      }
    }

    return SyncResult(synced: synced, failed: failed);
  }

  /// Check connectivity before sync
  Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return result.isNotEmpty && result.first != ConnectivityResult.none;
  }

  Future<void> _addToSyncQueue(String table, String recordId, String action, Map<String, dynamic> payload) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _localDb!.insert('sync_queue', {
      'id': '${table}_${recordId}_$now',
      'table_name': table,
      'record_id': recordId,
      'action': action,
      'payload': payload.entries.map((e) => '${e.key}=${e.value}').join(','),
      'local_timestamp': now,
      'created_at': now,
    });
  }

  void _triggerSync() {
    sync().then((result) {
      // Log or notify about sync result
    });
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _localDb?.close();
  }
}

class Receipt {
  final String id;
  final String rawText;
  final Map<String, dynamic>? parsedData;
  final String? imagePath;
  final String syncStatus;
  final int localTimestamp;
  final int? serverTimestamp;
  final int createdAt;

  Receipt({
    required this.id,
    required this.rawText,
    this.parsedData,
    this.imagePath,
    this.syncStatus = 'pending',
    required this.localTimestamp,
    this.serverTimestamp,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'raw_text': rawText,
        'parsed_data': parsedData?.toString(),
        'image_path': imagePath,
        'sync_status': syncStatus,
        'local_timestamp': localTimestamp,
        'server_timestamp': serverTimestamp,
        'created_at': createdAt,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'raw_text': rawText,
        'parsed_data': parsedData?.toString(),
        'image_path': imagePath,
        'local_timestamp': localTimestamp,
        'server_timestamp': serverTimestamp,
        'created_at': createdAt,
      };

  factory Receipt.fromMap(Map<String, dynamic> map) => Receipt(
        id: map['id'],
        rawText: map['raw_text'],
        parsedData: map['parsed_data'] != null
            ? Map<String, dynamic>.from(
                (map['parsed_data'] as String).split(',').asMap().map(
                      (k, v) => MapEntry('field_$k', v),
                    ),
              )
            : null,
        imagePath: map['image_path'],
        syncStatus: map['sync_status'] ?? 'pending',
        localTimestamp: map['local_timestamp'],
        serverTimestamp: map['server_timestamp'],
        createdAt: map['created_at'],
      );
}

class SyncResult {
  final int synced;
  final int failed;
  SyncResult({required this.synced, required this.failed});
}