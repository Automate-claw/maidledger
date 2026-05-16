import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'receipt_scanner_service.dart';

/// Provider that manages ReceiptScannerService lifecycle.
/// Disposes automatically when the widget tree unmounts or the provider is invalidated.
final receiptScannerProvider = NotifierProvider<_ReceiptScannerNotifier, ReceiptScannerService>(
  _ReceiptScannerNotifier.new,
);

class _ReceiptScannerNotifier extends Notifier<ReceiptScannerService> {
  @override
  ReceiptScannerService build() {
    final service = ReceiptScannerService();
    ref.onDispose(() => service.dispose());
    return service;
  }
}