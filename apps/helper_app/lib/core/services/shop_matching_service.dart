import 'package:supabase_flutter/supabase_flutter.dart';

class ShopMatchingService {
  final SupabaseClient _supabase;

  ShopMatchingService(this._supabase);

  Future<ShopMatchResult?> matchShop({
    required String rawShopName,
    String? shopType,
    String? region,
    String? district,
  }) async {
    if (rawShopName.trim().isEmpty) return null;

    final cleanName = rawShopName.trim();

    final exactMatchResult = await _exactAliasMatch(cleanName);
    if (exactMatchResult != null) return exactMatchResult;

    final ilikeResult = await _ilikeMatch(cleanName, shopType);
    if (ilikeResult != null) {
      await _createAlias(ilikeResult.shopId, cleanName, 'ocr');
      return ilikeResult;
    }

    if (ilikeResult == null && shopType != null) {
      final newShop = await createShop(
        canonicalName: cleanName,
        shopType: shopType,
        region: region,
        district: district,
      );
      await _createAlias(newShop.shopId, cleanName, 'ocr');
      return newShop;
    }

    return null;
  }

  Future<ShopMatchResult?> _exactAliasMatch(String rawName) async {
    final result = await _supabase
        .from('shop_aliases')
        .select('id, shop_id, shops(id, canonical_name, shop_type, region, district)')
        .eq('raw_name', rawName)
        .maybeSingle();

    if (result == null) return null;

    final shop = result['shops'] as Map<String, dynamic>?;
    return ShopMatchResult(
      shopId: result['shop_id'] as String,
      canonicalName: shop?['canonical_name'] as String? ?? '',
      shopType: shop?['shop_type'] as String?,
      region: shop?['region'] as String?,
      district: shop?['district'] as String?,
      confidence: 1.0,
      matchedVia: MatchedVia.exactAlias,
    );
  }

  String _escapeIlike(String input) {
    return input.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
  }

  Future<ShopMatchResult?> _ilikeMatch(String rawName, String? shopType) async {
    final keywords = _extractKeywords(rawName);
    if (keywords.isEmpty) return null;

    String tsQuery;
    try {
      tsQuery = keywords.join(' & ');
    } catch (_) {
      tsQuery = keywords.join(' ');
    }

    List<dynamic> rows = [];
    try {
      var query = _supabase
          .from('shops')
          .select('id, canonical_name, shop_type, region, district')
          .textSearch('canonical_name', tsQuery, config: 'simple');

      if (shopType != null && shopType.isNotEmpty && shopType != 'other') {
        query = query.eq('shop_type', shopType);
      }

      final results = await query.limit(20);
      rows = results as List;
    } catch (_) {
      for (final kw in keywords) {
        final fallbackResults = await _supabase
            .from('shops')
            .select('id, canonical_name, shop_type, region, district')
            .ilike('canonical_name', '%${_escapeIlike(kw)}%')
            .limit(10);
        final fallbackRows = fallbackResults as List;
        if (fallbackRows.isNotEmpty) {
          rows = fallbackRows;
          break;
        }
      }
    }

    if (rows.isEmpty) return null;

    ShopMatchResult? best;
    int bestScore = 0;

    for (final row in rows) {
      final canonical = (row['canonical_name'] as String).toLowerCase();
      int score = 0;
      for (final kw in keywords) {
        if (canonical.contains(kw.toLowerCase())) score++;
      }

      if (score > bestScore) {
        bestScore = score;
        best = ShopMatchResult(
          shopId: row['id'] as String,
          canonicalName: row['canonical_name'] as String,
          shopType: row['shop_type'] as String?,
          region: row['region'] as String?,
          district: row['district'] as String?,
          confidence: score / keywords.length,
          matchedVia: MatchedVia.ilike,
        );
      }
    }

    if (best != null && best.confidence >= 0.5) {
      return best;
    }

    return null;
  }

  Future<ShopMatchResult> createShop({
    required String canonicalName,
    required String shopType,
    String? region,
    String? district,
  }) async {
    final shopResult = await _supabase.from('shops').insert({
      'canonical_name': canonicalName,
      'shop_type': shopType,
      'region': region,
      'district': district,
    }).select();

    if (shopResult.isEmpty) {
      throw Exception('Failed to create shop: no result returned');
    }
    final first = shopResult.first;

    return ShopMatchResult(
      shopId: first['id'] as String,
      canonicalName: canonicalName,
      shopType: shopType,
      region: region,
      district: district,
      confidence: 1.0,
      matchedVia: MatchedVia.newShop,
    );
  }

  Future<void> _createAlias(String shopId, String rawName, String source) async {
    try {
      await _supabase.from('shop_aliases').upsert({
        'raw_name': rawName.trim(),
        'shop_id': shopId,
        'source': source,
      }, onConflict: 'raw_name');
    } catch (_) {}
  }

  List<String> _extractKeywords(String text) {
    final noise = [' ', '  ', '1', '2', '店', '分店', 'location'];
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

  Future<void> bindReceipt(String receiptId, String shopId) async {
    await _supabase.from('receipts').update({
      'shop_id': shopId,
    }).eq('id', receiptId);
  }
}

enum MatchedVia { exactAlias, ilike, newShop }

class ShopMatchResult {
  final String shopId;
  final String canonicalName;
  final String? shopType;
  final String? region;
  final String? district;
  final double confidence;
  final MatchedVia matchedVia;

  ShopMatchResult({
    required this.shopId,
    required this.canonicalName,
    this.shopType,
    this.region,
    this.district,
    required this.confidence,
    required this.matchedVia,
  });
}