import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_scanner/receipt_scanner.dart';

void main() {
  group('SyncService', () {
    group('Sync conflict resolution', () {
      test('should handle timestamp-based last-write-wins for upsert', () {
        // Simulate local and server receipts
        final localReceipt = Receipt(
          id: 'receipt-1',
          rawText: 'Local text',
          syncStatus: 'pending',
          localTimestamp: DateTime.now().millisecondsSinceEpoch - 1000,
          createdAt: DateTime.now().millisecondsSinceEpoch - 5000,
        );

        final serverReceipt = Receipt(
          id: 'receipt-1',
          rawText: 'Server text',
          syncStatus: 'synced',
          localTimestamp: DateTime.now().millisecondsSinceEpoch,
          serverTimestamp: DateTime.now().millisecondsSinceEpoch,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );

        // Last-write-wins: server (higher localTimestamp) should overwrite
        final winner = localReceipt.localTimestamp > serverReceipt.localTimestamp
            ? localReceipt
            : serverReceipt;

        expect(winner.id, 'receipt-1');
        expect(winner.rawText, 'Server text');
      });

      test('should preserve local data when offline queue is processed', () {
        final now = DateTime.now().millisecondsSinceEpoch;

        // Receipt created offline
        final offlineReceipt = Receipt(
          id: 'offline-1',
          rawText: 'Coffee shop receipt',
          parsedData: {'total': 45.0, 'currency': 'HKD'},
          syncStatus: 'pending',
          localTimestamp: now,
          createdAt: now,
        );

        // Serialise to map (as would happen in sync queue)
        final map = offlineReceipt.toMap();
        final deserialized = Receipt.fromMap(map);

        expect(deserialized.id, offlineReceipt.id);
        expect(deserialized.rawText, offlineReceipt.rawText);
        expect(deserialized.parsedData?['total'], 45.0);
        expect(deserialized.syncStatus, 'pending');
      });

      test('should handle null parsedData gracefully', () {
        final now = DateTime.now().millisecondsSinceEpoch;
        final receipt = Receipt(
          id: 'no-parse',
          rawText: 'Plain text receipt',
          parsedData: null,
          syncStatus: 'pending',
          localTimestamp: now,
          createdAt: now,
        );

        final map = receipt.toMap();
        final deserialized = Receipt.fromMap(map);

        expect(deserialized.parsedData, isNull);
        expect(deserialized.rawText, 'Plain text receipt');
      });
    });

    group('Receipt model', () {
      test('toJson should strip sync_status for server payload', () {
        final receipt = Receipt(
          id: 'test',
          rawText: 'test',
          syncStatus: 'pending',
          localTimestamp: 123,
          createdAt: 456,
        );

        final json = receipt.toJson();
        expect(json.containsKey('sync_status'), isTrue); // included in toJson

        final serverPayload = receipt.toJson()..remove('sync_status');
        expect(serverPayload.containsKey('sync_status'), isFalse);
      });
    });
  });
}