import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_client_provider.dart';
import '../../core/services/relation_service.dart';

/// Widget that checks if helper has an active employer relation
/// Shows linking dialog if not connected, but allows dismissal
class RelationGate extends ConsumerStatefulWidget {
  final Widget child;

  const RelationGate({super.key, required this.child});

  @override
  ConsumerState<RelationGate> createState() => _RelationGateState();
}

class _RelationGateState extends ConsumerState<RelationGate> {
  bool _isChecked = false;
  bool _hasActiveRelation = false;
  bool _dismissed = false;
  RelationStatus? _status;

  @override
  void initState() {
    super.initState();
    _checkRelation();
  }

  Future<void> _checkRelation() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _isChecked = true);
      return;
    }

    final service = RelationService(supabase);
    final status = await service.checkRelationStatus(user.id);

    if (mounted) {
      setState(() {
        _isChecked = true;
        _hasActiveRelation = status.hasActiveRelation;
        _status = status;
      });
    }
  }

  void _showLinkingDialog() {
    showDialog(
      context: context,
      barrierDismissible: true, // Allow dismiss
      builder: (context) => _EmployerLinkDialog(
        onLinked: () {
          setState(() => _hasActiveRelation = true);
        },
        onDismissed: () {
          setState(() => _dismissed = true);
        },
      ),
    ).then((_) {
      // Dialog was dismissed (not linked)
      if (mounted && !_hasActiveRelation) {
        setState(() => _dismissed = true);
      }
    });
  }

  /// Called by features that need relation (e.g., scan screen)
  /// Re-shows dialog if dismissed and still no relation
  void ensureRelation() {
    if (_isChecked && !_hasActiveRelation && !_dismissed) {
      _showLinkingDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isChecked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Always show child - relation check just overlays dialog
    return widget.child;
  }
}

/// Dialog to link helper to employer via short_code
class _EmployerLinkDialog extends ConsumerStatefulWidget {
  final VoidCallback onLinked;
  final VoidCallback onDismissed;

  const _EmployerLinkDialog({
    required this.onLinked,
    required this.onDismissed,
  });

  @override
  ConsumerState<_EmployerLinkDialog> createState() => _EmployerLinkDialogState();
}

class _EmployerLinkDialogState extends ConsumerState<_EmployerLinkDialog> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _linkToEmployer() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '請輸入僱主代碼');
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _error = '請先登入');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final service = RelationService(supabase);
    final result = await service.linkToEmployer(
      helperId: user.id,
      employerCode: code,
    );

    if (mounted) {
      setState(() => _isLoading = false);

      if (result.success) {
        widget.onLinked();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 已連接到 ${result.employerName ?? "僱主"}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => _error = result.error ?? '連接失敗');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('🔗 連接僱主'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '請向僱主取得連接代碼，然後輸入以下方框：',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: InputDecoration(
              labelText: '僱主代碼',
              hintText: '例如 DEMO01',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            enabled: !_isLoading,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
          ),
          const SizedBox(height: 8),
          const Text(
            '代碼由僱主從「我的代碼」取得（6位字母）',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading
              ? null
              : () {
                  widget.onDismissed();
                  Navigator.of(context).pop();
                },
          child: const Text('稍後'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _linkToEmployer,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('連接'),
        ),
      ],
    );
  }
}

/// Provider for relation status (reusable across the app)
final relationStatusProvider = FutureProvider<RelationStatus>((ref) async {
  final user = supabase.auth.currentUser;
  if (user == null) {
    return RelationStatus(hasActiveRelation: false);
  }
  final service = RelationService(supabase);
  return service.checkRelationStatus(user.id);
});

