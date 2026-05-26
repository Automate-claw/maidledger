import 'package:supabase_flutter/supabase_flutter.dart';

/// Relation Service
/// Handles employer-helper relationship verification and linking
class RelationService {
  final SupabaseClient _supabase;

  RelationService(this._supabase);

  /// Check if user has an active employer-helper relation
  Future<RelationStatus> checkRelationStatus(String userId) async {
    try {
      final relations = await _supabase
          .from('employer_helper_relations')
          .select('*, employer:user_profiles!employer_id(name)')
          .eq('helper_id', userId)
          .eq('status', 'active');

      if (relations.isEmpty) {
        return RelationStatus(
          hasActiveRelation: false,
          relations: [],
        );
      }

      return RelationStatus(
        hasActiveRelation: true,
        relations: relations,
      );
    } catch (e) {
      return RelationStatus(
        hasActiveRelation: false,
        error: 'Failed to check relation: $e',
      );
    }
  }

  /// Resolve employer by short_code (6-char code) or UUID
  /// Returns employer profile if found, null otherwise
  Future<Map<String, dynamic>?> _resolveEmployer(String code) async {
    // Try short_code first (6-char code like DEMO01)
    if (code.length == 6) {
      final byShortCode = await _supabase
          .from('user_profiles')
          .select('id, name, role, short_code')
          .eq('short_code', code.toUpperCase())
          .eq('role', 'employer')
          .maybeSingle();

      if (byShortCode != null) return byShortCode;
    }

    // Fall back to UUID lookup
    final byUuid = await _supabase
        .from('user_profiles')
        .select('id, name, role, short_code')
        .eq('id', code)
        .eq('role', 'employer')
        .maybeSingle();

    return byUuid;
  }

  /// Link helper to employer via short_code (6-char) or UUID
  /// Returns the created/updated relation
  Future<LinkResult> linkToEmployer({
    required String helperId,
    required String employerCode,
  }) async {
    try {
      // Resolve employer from short_code or UUID
      final employer = await _resolveEmployer(employerCode.trim());

      if (employer == null) {
        return LinkResult(
          success: false,
          error: '無效的僱主代碼，請確認代碼是否正確',
        );
      }

      final employerId = employer['id'];

      // Check if a relation already exists (active or pending)
      final existing = await _supabase
          .from('employer_helper_relations')
          .select('id, status')
          .eq('employer_id', employerId)
          .eq('helper_id', helperId)
          .maybeSingle();

      if (existing != null) {
        if (existing['status'] == 'active') {
          return LinkResult(
            success: false,
            error: '你已經連接到呢位僱主了',
          );
        }

        // Reactivate pending/inactive relation
        final updated = await _supabase
            .from('employer_helper_relations')
            .update({
              'helper_id': helperId,
              'status': 'active',
            })
            .eq('id', existing['id'])
            .select()
            .single();

        return LinkResult(
          success: true,
          relation: updated,
          employerName: employer['name'],
        );
      }

      // Create new active relation
      final newRelation = await _supabase
          .from('employer_helper_relations')
          .insert({
            'employer_id': employerId,
            'helper_id': helperId,
            'status': 'active',
          })
          .select()
          .single();

      return LinkResult(
        success: true,
        relation: newRelation,
        employerName: employer['name'],
      );
    } catch (e) {
      return LinkResult(
        success: false,
        error: '連接失敗：$e',
      );
    }
  }

  /// End/disconnect an active relation
  Future<LinkResult> endRelation({
    required String helperId,
    required String employerId,
  }) async {
    try {
      await _supabase
          .from('employer_helper_relations')
          .update({'status': 'inactive'})
          .eq('helper_id', helperId)
          .eq('employer_id', employerId)
          .eq('status', 'active');

      return LinkResult(success: true);
    } catch (e) {
      return LinkResult(success: false, error: '断开连接失败：$e');
    }
  }

  /// Get all active relations for a helper
  Future<List<Map<String, dynamic>>> getActiveRelations(String helperId) async {
    final relations = await _supabase
        .from('employer_helper_relations')
        .select('*, employer:user_profiles!employer_id(id, name)')
        .eq('helper_id', helperId)
        .eq('status', 'active');

    return List<Map<String, dynamic>>.from(relations);
  }
}

/// Status of user's employer relations
class RelationStatus {
  final bool hasActiveRelation;
  final List<Map<String, dynamic>> relations;
  final String? error;

  RelationStatus({
    required this.hasActiveRelation,
    this.relations = const [],
    this.error,
  });
}

/// Result of linking helper to employer
class LinkResult {
  final bool success;
  final Map<String, dynamic>? relation;
  final String? employerName;
  final String? error;

  LinkResult({
    required this.success,
    this.relation,
    this.employerName,
    this.error,
  });
}