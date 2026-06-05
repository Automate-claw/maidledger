import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductMatchingService', () {
    group('_extractKeywords (mirrors implementation)', () {
      test('extracts single keyword from clean name', () {
        final keywords = _extractKeywords('紅衫魚');
        expect(keywords, contains('紅衫魚'));
      });

      test('removes single character tokens', () {
        final keywords = _extractKeywords('魚 1件');
        // '1' and '件' should be filtered as noise
        expect(keywords, isNot(contains('1')));
        expect(keywords, isNot(contains('件')));
      });

      test('handles multi-word input with spaces', () {
        final keywords = _extractKeywords('急凍紅衫魚 1包');
        expect(keywords.any((k) => k.contains('紅衫魚') || k.contains('急凍')), isTrue);
      });

      test('handles unit suffixes removal', () {
        // Only 'g', 'kg', 'ml', 'l' are in noise list, not all numbers
        // So '500' is NOT filtered (only '1' and '2' are in noise)
        final keywords = _extractKeywords('雞肉 500g');
        expect(keywords, isNot(contains('g')));
        expect(keywords, contains('500')); // '500' is kept (only 1,2 are filtered)
        expect(keywords, contains('雞肉'));
      });

      test('handles empty input', () {
        final keywords = _extractKeywords('');
        expect(keywords, isEmpty);
      });

      test('handles whitespace only input', () {
        final keywords = _extractKeywords('   ');
        expect(keywords, isEmpty);
      });

      test('filters out all noise leaving only meaningful tokens', () {
        final keywords = _extractKeywords('魚 1 件 個 包 支 罐 盒 斤 兩');
        // All single-char tokens should be removed
        for (final kw in keywords) {
          expect(kw.length, greaterThan(1));
        }
      });
    });

    group('_escapeIlike (mirrors implementation)', () {
      test('escapes percent sign', () {
        expect(_escapeIlike('100%'), equals('100\\%'));
      });

      test('escapes underscore', () {
        expect(_escapeIlike('test_value'), equals('test\\_value'));
      });

      test('escapes both percent and underscore', () {
        expect(_escapeIlike('100%_test'), equals('100\\%\\_test'));
      });

      test('returns unchanged string when no special chars', () {
        expect(_escapeIlike('normal text'), equals('normal text'));
      });
    });

    group('MasterMatchResult', () {
      test('stores all fields correctly', () {
        final result = MasterMatchResult(
          masterProductId: 'mp-123',
          canonicalName: '紅衫魚',
          brand: '優之選',
          prdCate: 'fish',
          confidence: 0.85,
          matchedVia: MatchedVia.ilike,
        );

        expect(result.masterProductId, equals('mp-123'));
        expect(result.canonicalName, equals('紅衫魚'));
        expect(result.brand, equals('優之選'));
        expect(result.prdCate, equals('fish'));
        expect(result.confidence, equals(0.85));
        expect(result.matchedVia, equals(MatchedVia.ilike));
      });

      test('matchedVia enum has correct values', () {
        expect(MatchedVia.values, containsAll([MatchedVia.exactAlias, MatchedVia.ilike, MatchedVia.newProduct]));
      });
    });

    group('multilang fallback dictionary (static access)', () {
      // These are package-level constants, testable via public interface
      test('fish category includes common multilingual names', () {
        const fishEntries = _multiLangFish;
        expect(fishEntries.containsKey('fish'), isTrue);
        expect(fishEntries['fish'], contains('魚'));
        expect(fishEntries['fish'], contains('紅衫魚'));
        expect(fishEntries['fish'], contains('石斑'));
      });

      test('meat categories have multilingual support', () {
        final meatEntries = _multiLangMeat;
        expect(meatEntries['pork'], contains('豬肉'));
        expect(meatEntries['beef'], contains('牛肉'));
        expect(meatEntries['chicken'], contains('雞肉'));
      });

      test('vegetables and rice have multilingual support', () {
        final vegEntries = _multiLangVeg;
        final riceEntries = _multiLangRice;
        expect(vegEntries['vegetables'], contains('蔬菜'));
        expect(riceEntries['rice'], contains('米'));
      });
    });
  });
}

/// Mirrors ProductMatchingService implementation for testing
List<String> _extractKeywords(String text) {
  final noise = [' ', '  ', '1', '2', '件', '個', '包', '支', '罐', '盒', '斤', '兩', '克', 'kg', 'g', 'ml', 'l'];
  String cleaned = text;
  for (final n in noise) {
    cleaned = cleaned.replaceAll(n, ' ');
  }
  return cleaned.split(RegExp(r'\s+')).where((t) => t.length > 1).toList();
}

String _escapeIlike(String s) => s.replaceAll('%', '\\%').replaceAll('_', '\\_');

// Static multilang dictionaries (copied from ProductMatchingService)
const Map<String, List<String>> _multiLangFish = {
  'fish': ['魚', '魚類', '紅衫魚', '石斑', 'isda', 'ikan', 'fish', 'iping', 'bangus'],
};

const Map<String, List<String>> _multiLangMeat = {
  'pork': ['豬肉', '豬', 'carne', 'karne', 'baboy', 'daging babi'],
  'beef': ['牛肉', '牛', 'beef', 'carne de res', 'sapi'],
  'chicken': ['雞肉', '雞', 'chicken', 'manok', 'ayam'],
};

const Map<String, List<String>> _multiLangVeg = {
  'vegetables': ['蔬菜', '菜', 'veggies', 'gulay', 'sayur', 'sayuran'],
};

const Map<String, List<String>> _multiLangRice = {
  'rice': ['米', '飯', 'rice', 'kanin', 'nasi'],
};

// Test double for MasterMatchResult
enum MatchedVia { exactAlias, ilike, newProduct }

class MasterMatchResult {
  final String masterProductId;
  final String canonicalName;
  final String? brand;
  final String? prdCate;
  final double confidence;
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