import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_scanner/receipt_scanner.dart';

void main() {
  // Initialize binding for platform channel tests
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Receipt', () {
    test('should serialize and deserialize correctly', () {
      final receipt = Receipt(
        id: 'test-id-123',
        rawText: 'Sample receipt text',
        parsedData: {'total': 100.0, 'currency': 'HKD'},
        imagePath: '/path/to/image.jpg',
        syncStatus: 'pending',
        localTimestamp: DateTime.now().millisecondsSinceEpoch,
        serverTimestamp: null,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      final map = receipt.toMap();
      final deserialized = Receipt.fromMap(map);

      expect(deserialized.id, receipt.id);
      expect(deserialized.rawText, receipt.rawText);
      expect(deserialized.syncStatus, 'pending');
    });

    test('should default syncStatus to pending', () {
      final receipt = Receipt(
        id: 'test-id',
        rawText: 'text',
        localTimestamp: DateTime.now().millisecondsSinceEpoch,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(receipt.syncStatus, 'pending');
    });
  });

  group('ReceiptScanResult', () {
    test('should create empty result', () {
      final result = ReceiptScanResult.empty();
      expect(result.textBlocks, isEmpty);
      expect(result.rawText, isEmpty);
    });

    test('should hold scan data', () {
      final block = TextBlock(
        text: 'Total: \$100',
        boundingBox: const Rect.fromLTWH(10, 10, 100, 20),
        corners: const [
          Offset(10, 10),
          Offset(110, 10),
          Offset(110, 30),
          Offset(10, 30),
        ],
      );

      final result = ReceiptScanResult(
        textBlocks: [block],
        rawText: 'Total: \$100',
        timestamp: DateTime.now(),
      );

      expect(result.textBlocks.length, 1);
      expect(result.rawText, 'Total: \$100');
    });
  });

  group('TextBlock', () {
    test('should create from ML Kit data', () {
      final block = TextBlock.fromMlKit(
        text: 'Hello',
        boundingBox: const Rect.fromLTWH(0, 0, 50, 20),
        cornerPoints: const [
          Point<int>(0, 0),
          Point<int>(50, 0),
          Point<int>(50, 20),
          Point<int>(0, 20),
        ],
      );

      expect(block.text, 'Hello');
      expect(block.corners.length, 4);
      expect(block.corners[0], const Offset(0, 0));
    });
  });

  group('SyncResult', () {
    test('should hold sync counts', () {
      final result = SyncResult(synced: 5, failed: 2);
      expect(result.synced, 5);
      expect(result.failed, 2);
    });
  });
}