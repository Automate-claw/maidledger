import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';

/// Receipt Scanner Service
/// Wraps ML Kit for on-device OCR with offline support
class ReceiptScannerService {
  final TextRecognizer _textRecognizer = TextRecognizer();

  /// Capture and recognize text from camera image
  /// Returns extracted text blocks for UI highlight
  Future<ReceiptScanResult> scanFromCamera(CameraImage image) async {
    final inputImage = _convertCameraImage(image);
    final recognized = await _textRecognizer.processImage(inputImage);

    return ReceiptScanResult(
      textBlocks: recognized.blocks
          .map((b) => TextBlock(
                text: b.text,
                boundingBox: b.boundingBox,
                corners: b.cornerPoints,
              ))
          .toList(),
      rawText: recognized.text,
      timestamp: DateTime.now(),
    );
  }

  /// Scan from file (for gallery import)
  Future<ReceiptScanResult> scanFromFile(File file) async {
    final inputImage = InputImage.fromFile(file);
    final recognized = await _textRecognizer.processImage(inputImage);

    return ReceiptScanResult(
      textBlocks: recognized.blocks
          .map((b) => TextBlock(
                text: b.text,
                boundingBox: b.boundingBox,
                corners: b.cornerPoints,
              ))
          .toList(),
      rawText: recognized.text,
      timestamp: DateTime.now(),
    );
  }

  CameraImage _convertCameraImage(camera.CameraImage image) {
    // ML Kit accepts camera image via InputImage
    // This is handled by the platform-specific implementation
    throw UnimplementedError('Use scanFromFile for CameraImage');
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
  final List<Point<int>> corners;

  TextBlock({
    required this.text,
    required this.boundingBox,
    required this.corners,
  });
}

class Rect {
  final double left, top, right, bottom;
  Rect({required this.left, required this.top, required this.right, required this.bottom});
  double get width => right - left;
  double get height => bottom - top;
}

class Point<T extends num> {
  final T x, y;
  Point(this.x, this.y);
}