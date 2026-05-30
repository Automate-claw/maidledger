import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:exif/exif.dart' show readExifFromBytes;
import 'location_service.dart'; // Uses GpsResult from location_service

/// Receipt Scanner Service provider for managed lifecycle.
///
/// Usage:
///   ref.watch(receiptScannerProvider)    // access the service
///   ref.watch(receiptScannerProvider.notifier).dispose()  // cleanup if needed
///
/// The service is disposed automatically when the provider is invalidated.
class ReceiptScannerService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  /// Scan from file (for gallery import or camera capture)
  Future<ReceiptScanResult> scanFromFile(File file) async {
    final inputImage = InputImage.fromFile(file);
    final recognized = await _textRecognizer.processImage(inputImage);

    final blocks = recognized.blocks.map((b) => TextBlock(
      text: b.text,
      boundingBox: Rect.fromLTRB(
        b.boundingBox.left.toDouble(),
        b.boundingBox.top.toDouble(),
        b.boundingBox.right.toDouble(),
        b.boundingBox.bottom.toDouble(),
      ),
    )).toList();

    // Group blocks by row using Y-coordinate clustering
    final groupedRows = _groupByRow(blocks);

    return ReceiptScanResult(
      textBlocks: blocks,
      groupedRows: groupedRows,
      rawText: recognized.text,
      timestamp: DateTime.now(),
    );
  }

  /// Group text blocks into rows based on Y-coordinate proximity.
  /// Text blocks on the same row (e.g., "Item Name" and "$45.00") are grouped together.
  List<TextRow> _groupByRow(List<TextBlock> blocks) {
    if (blocks.isEmpty) return [];

    // Sort blocks by top Y, then left X
    final sorted = List<TextBlock>.from(blocks)
      ..sort((a, b) {
        final dy = a.boundingBox.top - b.boundingBox.top;
        if (dy.abs() > 2) return dy.round();
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      });

    final rows = <TextRow>[];
    TextRow? currentRow;

    for (final block in sorted) {
      if (currentRow == null) {
        currentRow = TextRow(blocks: [block], topY: block.boundingBox.top);
      } else {
        // Check if this block is on the same row (Y within tolerance)
        final dy = (block.boundingBox.top - currentRow.topY).abs();
        final dh = ((block.boundingBox.top + block.boundingBox.height / 2) -
                   (currentRow.blocks.last.boundingBox.top + currentRow.blocks.last.boundingBox.height / 2)).abs();

        if (dy < 8 || dh < 10) {
          // Same row — add to current row (keep left-to-right order)
          final leftX = block.boundingBox.left;
          final insertAt = currentRow.blocks.indexWhere((b) => b.boundingBox.left > leftX);
          if (insertAt < 0) {
            currentRow.blocks.add(block);
          } else {
            currentRow.blocks.insert(insertAt, block);
          }
        } else {
          // New row — save current and start new
          rows.add(currentRow);
          currentRow = TextRow(blocks: [block], topY: block.boundingBox.top);
        }
      }
    }

    if (currentRow != null) {
      rows.add(currentRow);
    }

    return rows;
  }

  /// Release ML Kit resources. Safe to call multiple times.
  void dispose() {
    _textRecognizer.close();
  }

  Future<GpsResult?> extractGpsFromFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return await extractGpsFromBytes(bytes);
    } catch (e) {
      return null;
    }
  }

  Future<GpsResult?> extractGpsFromBytes(Uint8List imageBytes) async {
    try {
      final exifData = await readExifFromBytes(imageBytes);

      // Debug: print ALL GPS-related EXIF tags
      final gpsTags = exifData.entries
          .where((e) => e.key.toLowerCase().contains('gps') ||
                        e.key.toLowerCase().contains('lat') ||
                        e.key.toLowerCase().contains('lon') ||
                        e.key.toLowerCase().contains('geo') ||
                        e.key.toLowerCase().contains('location'))
          .map((e) => '${e.key}=${e.value}')
          .toList();
      print('🔵 [GPS EXIF] Tags: $gpsTags');

      final lat = exifData['GPS GPSLatitude'];
      final lon = exifData['GPS GPSLongitude'];
      final latRef = exifData['GPS GPSLatitudeRef']?.printable;
      final lonRef = exifData['GPS GPSLongitudeRef']?.printable;

      print('🔵 [GPS EXIF] lat=$lat, lon=$lon, latRef=$latRef, lonRef=$lonRef');

      if (lat != null && lon != null) {
        final latitude = _parseDMS(lat.printable, latRef);
        final longitude = _parseDMS(lon.printable, lonRef);
        print('🔵 [GPS EXIF] parsed lat=$latitude, lon=$longitude');
        if (latitude != null && longitude != null && (latitude != 0 || longitude != 0)) {
          return GpsResult(latitude: latitude, longitude: longitude);
        }
      }

      return null;
    } catch (e) {
      print('🔵 [GPS EXIF] Error: $e');
      return null;
    }
  }

  double? _parseDMS(String dms, String? ref) {
    final regex = RegExp(r"(\d+)°\s*(\d+)'?\s*(\d+(?:\.\d+)?)?[""']?");
    final match = regex.firstMatch(dms);
    if (match == null) return null;

    final degrees = double.parse(match.group(1)!);
    final minutes = double.parse(match.group(2)!);
    final seconds = double.tryParse(match.group(3) ?? '0') ?? 0;

    double decimal = degrees + (minutes / 60) + (seconds / 3600);

    if (ref == 'S') decimal = -decimal;
    if (ref == 'W') decimal = -decimal;

    return decimal;
  }
}

/// Result of a receipt scan including grouped rows.
class ReceiptScanResult {
  final List<TextBlock> textBlocks;
  final List<TextRow> groupedRows;
  final String rawText;
  final DateTime timestamp;

  ReceiptScanResult({
    required this.textBlocks,
    required this.groupedRows,
    required this.rawText,
    required this.timestamp,
  });

  /// Build a "reconstructed" text that groups items + prices on the same row.
  /// Each row is joined with " | " separator.
  String get reconstructedText {
    return groupedRows.map((row) {
      return row.blocks.map((b) => b.text.trim()).join(' | ');
    }).join('\n');
  }
}

/// A row of text blocks that are on the same Y-coordinate line.
class TextRow {
  final List<TextBlock> blocks;
  final double topY;

  TextRow({required this.blocks, required this.topY});

  /// Return the block with the rightmost X (typically the price).
  TextBlock? get rightmost => blocks.isEmpty ? null : blocks.reduce(
    (a, b) => a.boundingBox.left > b.boundingBox.left ? b : a,
  );

  /// Return the block with the leftmost X (typically the item name).
  TextBlock? get leftmost => blocks.isEmpty ? null : blocks.reduce(
    (a, b) => a.boundingBox.left < b.boundingBox.left ? b : a,
  );
}

class TextBlock {
  final String text;
  final Rect boundingBox;

  TextBlock({
    required this.text,
    required this.boundingBox,
  });
}

// GpsResult is defined in location_service.dart