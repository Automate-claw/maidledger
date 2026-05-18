import 'package:supabase_flutter/supabase_flutter.dart';

/// ILIKE-based product matching service
/// Phase 1 MVP: no pgvector dependency
class ProductMatchingService {
  // Multi-language keyword dictionaries (moved inside class as static const)
  static const Map<String, List<String>> _multiLangFish = {
    'fish': ['魚', '魚類', '紅衫魚', '石斑', 'isda', 'ikan', 'fish', 'iping', 'bangus'],
  };

  static const Map<String, List<String>> _multiLangMeat = {
    'pork': ['豬肉', '豬', 'carne', 'karne', 'baboy', 'daging babi'],
    'beef': ['牛肉', '牛', 'beef', 'carne de res', 'sapi'],
    'chicken': ['雞肉', '雞', 'chicken', 'manok', 'ayam'],
  };

  static const Map<String, List<String>> _multiLangVeg = {
    'vegetables': ['蔬菜', '菜', 'veggies', 'gulay', 'sayur', 'sayuran'],
  };

  static const Map<String, List<String>> _multiLangRice = {
    'rice': ['米', '飯', 'rice', 'kanin', 'nasi'],
  };

  final SupabaseClient _supabase;

  ProductMatchingService(this._supabase);

  /// Match a raw item name to a master_product_id
  /// Returns matched master_product_id or null if no confident match
  Future<MasterMatchResult?> matchItem({
    required String itemName,
    String? prdCate,
  }) async {
    if (itemName.trim().isEmpty) return null;

    final cleanName = itemName.trim();

    // Step 1: exact match in aliases
    final aliasMatch = await _exactAliasMatch(cleanName);
    if (aliasMatch != null) return aliasMatch;

    // Step 2: ILIKE keyword match
    final keywords = _extractKeywords(cleanName);
    if (keywords.isNotEmpty) {
      final ilikeMatch = await _ilikeMatch(keywords, prdCate);
      if (ilikeMatch != null) {
        // Auto-create alias for next time
        await _createAlias(ilikeMatch.masterProductId, cleanName, 'ocr');
        return ilikeMatch;
      }
    }

    // Step 3: no confident match — return null (caller can choose to create new master)
    return null;
  }

  /// Step 1: exact alias match
  Future<MasterMatchResult?> _exactAliasMatch(String rawName) async {
    final result = await _supabase
        .from('product_aliases')
        .select('id, master_product_id, master_products(canonical_name, brand, prd_cate)')
        .eq('raw_name', rawName)
        .maybeSingle();

    if (result == null) return null;

    final mp = result['master_products'] as Map<String, dynamic>?;
    return MasterMatchResult(
      masterProductId: result['master_product_id'] as String,
      canonicalName: mp?['canonical_name'] as String? ?? '',
      confidence: 1.0, // exact match = 100%
      matchedVia: MatchedVia.exactAlias,
    );
  }

  /// Step 2: ILIKE keyword match
  Future<MasterMatchResult?> _ilikeMatch(List<String> keywords, String? prdCate) async {
    // Build ILIKE query: each keyword must appear in canonical_name
    // Use text search for better performance
    String? tsQuery;
    try {
      tsQuery = keywords.join(' & ');
    } catch (_) {
      tsQuery = keywords.join(' ');
    }

    var query = _supabase
        .from('master_products')
        .select('id, canonical_name, brand, prd_cate')
        .textSearch('canonical_name', tsQuery, config: 'simple');

    final filteredQuery = prdCate != null && prdCate.isNotEmpty && prdCate != 'other'
        ? query.eq('prd_cate', prdCate)
        : query;

    final results = await filteredQuery.limit(5);
    final rows = results as List;

    if (rows.isEmpty) {
      return _multiLangFallbackMatch(keywords, prdCate);
    }

    // Score by how many keywords matched
    MasterMatchResult? best;
    int bestScore = 0;

    for (final row in rows) {
      final canonical = (row['canonical_name'] as String).toLowerCase();
      int score = 0;
      for (final kw in keywords) {
        if (canonical.contains(kw.toLowerCase())) score++;
      }

      if (score > bestScore) {
        bestScore = score;
        best = MasterMatchResult(
          masterProductId: row['id'] as String,
          canonicalName: row['canonical_name'] as String,
          brand: row['brand'] as String?,
          prdCate: row['prd_cate'] as String?,
          confidence: score / keywords.length,
          matchedVia: MatchedVia.ilike,
        );
      }
    }

    // Require at least 50% keyword match confidence
    if (best != null && best.confidence >= 0.5) {
      return best;
    }

    return _multiLangFallbackMatch(keywords, prdCate);
  }

  Future<MasterMatchResult?> _multiLangFallbackMatch(List<String> keywords, String? prdCate) async {
    final allLangDicts = [_multiLangFish, _multiLangMeat, _multiLangVeg, _multiLangRice];

    for (final kw in keywords) {
      final kwLower = kw.toLowerCase();
      for (final dict in allLangDicts) {
        for (final entry in dict.entries) {
          if (entry.value.contains(kwLower)) {
            final englishKeyword = entry.key;
            final langResults = await _supabase
                .from('master_products')
                .select('id, canonical_name, brand, prd_cate')
                .textSearch('canonical_name', englishKeyword, config: 'simple')
                .limit(3);

            final rows = langResults as List;
            if (rows.isNotEmpty) {
              final row = rows.first;
              return MasterMatchResult(
                masterProductId: row['id'] as String,
                canonicalName: row['canonical_name'] as String,
                brand: row['brand'] as String?,
                prdCate: row['prd_cate'] as String?,
                confidence: 0.6,
                matchedVia: MatchedVia.ilike,
              );
            }
          }
        }
      }
    }
    return null;
  }

  /// Create a new master product and alias from a raw item name
  Future<MasterMatchResult> createMasterProduct({
    required String rawName,
    String? brand,
    String? prdCate,
    String defaultUnit = '件',
  }) async {
    final canonicalName = rawName.trim();

    // Insert master product
    final mpResult = await _supabase.from('master_products').insert({
      'canonical_name': canonicalName,
      'brand': brand,
      'prd_cate': prdCate ?? 'other',
      'default_unit': defaultUnit,
    }).select().single();

    // Create self-referencing alias
    await _supabase.from('product_aliases').insert({
      'raw_name': rawName.trim(),
      'master_product_id': mpResult['id'],
      'source': 'ocr',
    });

    return MasterMatchResult(
      masterProductId: mpResult['id'] as String,
      canonicalName: canonicalName,
      brand: brand,
      prdCate: prdCate ?? 'other',
      confidence: 1.0,
      matchedVia: MatchedVia.newProduct,
    );
  }

  Future<void> _createAlias(String masterProductId, String rawName, String source) async {
    try {
      await _supabase.from('product_aliases').upsert({
        'raw_name': rawName.trim(),
        'master_product_id': masterProductId,
        'source': source,
      }, onConflict: 'raw_name');
    } catch (_) {
      // Alias already exists or error — ignore
    }
  }

  /// Extract searchable keywords from item name
  List<String> _extractKeywords(String text) {
    // Remove common noise, keep meaningful tokens
    final noise = [' ', '  ', '1', '2', '件', '個', '包', '支', '罐', '盒', '斤', '兩', '克', 'kg', 'g', 'ml', 'l'];
    String cleaned = text;
    for (final n in noise) {
      cleaned = cleaned.replaceAll(n, ' ');
    }

    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1)
        .toList();

    return tokens;
  }

  /// Bind an existing master_product_id to a receipt_item
  Future<void> bindReceiptItem(String receiptItemId, String masterProductId) async {
    await _supabase.from('receipt_items').update({
      'master_product_id': masterProductId,
    }).eq('id', receiptItemId);
  }
}

enum MatchedVia { exactAlias, ilike, newProduct }

class MasterMatchResult {
  final String masterProductId;
  final String canonicalName;
  final String? brand;
  final String? prdCate;
  final double confidence; // 0.0 - 1.0
  final MatchedVia matchedVia;

  MasterMatchResult({
    required this.masterProductId,
    required this.canonicalName,
    this.brand,
    this.prdCate,
    required this.confidence,
    required this.matchedVia,
  });
}