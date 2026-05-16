import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';

/// Receipt Scanner Service
/// Wraps ML Kit for on-device OCR with offline support
class ReceiptScannerService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  /// Capture and recognize text from camera image
  /// Returns extracted text blocks for UI highlight
  Future<ReceiptScanResult> scanFromCameraImage(
    CameraImage image, {
    required InputImageRotation rotation,
  }) async {
    final inputImage = _convertCameraImage(image, rotation);
    final recognized = await _textRecognizer.processImage(inputImage);

    return ReceiptScanResult(
      textBlocks: recognized.blocks
          .map((b) => TextBlock.fromMlKit(
                text: b.text,
                boundingBox: b.boundingBox,
                cornerPoints: b.cornerPoints,
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
          .map((b) => TextBlock.fromMlKit(
                text: b.text,
                boundingBox: b.boundingBox,
                cornerPoints: b.cornerPoints,
              ))
          .toList(),
      rawText: recognized.text,
      timestamp: DateTime.now(),
    );
  }

  InputImage _convertCameraImage(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    // Convert CameraImage to ML Kit's InputImage format
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        bytesPerRow: plane.bytesPerRow,
        format: InputImageFormat.yuv420,
      ),
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

  factory ReceiptScanResult.empty() => ReceiptScanResult(
        textBlocks: [],
        rawText: '',
        timestamp: DateTime.now(),
      );
}

class TextBlock {
  final String text;
  final Rect boundingBox;
  final List<Offset> corners;

  TextBlock({
    required this.text,
    required this.boundingBox,
    required this.corners,
  });

  /// Convert from ML Kit Point<int> to Offset
  factory TextBlock.fromMlKit({
    required String text,
    required Rect boundingBox,
    required List<Point<int>> cornerPoints,
  }) =>
      TextBlock(
        text: text,
        boundingBox: boundingBox,
        corners:
            cornerPoints.map((p) => Offset(p.x.toDouble(), p.y.toDouble())).toList(),
      );
}