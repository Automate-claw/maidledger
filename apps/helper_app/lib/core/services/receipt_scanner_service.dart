import 'dart:io';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Receipt Scanner Service
/// Wraps ML Kit for on-device OCR with offline support
class ReceiptScannerService {
  final TextRecognizer _textRecognizer = TextRecognizer();

  /// Scan from file (for gallery import or camera capture)
  Future<ReceiptScanResult> scanFromFile(File file) async {
    final inputImage = InputImage.fromFile(file);
    final recognized = await _textRecognizer.processImage(inputImage);

    return ReceiptScanResult(
      textBlocks: recognized.blocks
          .map((b) => TextBlock(
                text: b.text,
                boundingBox: Rect.fromLTRB(
                  b.boundingBox.left.toDouble(),
                  b.boundingBox.top.toDouble(),
                  b.boundingBox.right.toDouble(),
                  b.boundingBox.bottom.toDouble(),
                ),
              ))
          .toList(),
      rawText: recognized.text,
      timestamp: DateTime.now(),
    );
  }

  void dispose() {
    _textRecognizer.close();
  }
}

class ReceiptScanResult {
  final List<TextBlock> textBlocks;
  final String rawText;
  final DateTime timestamp;

  ReceiptScanResult({
    required this.textBlocks,
    required this.rawText,
    required this.timestamp,
  });
}

class TextBlock {
  final String text;
  final Rect boundingBox;

  TextBlock({
    required this.text,
    required this.boundingBox,
  });
}