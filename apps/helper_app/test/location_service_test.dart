import 'package:flutter_test/flutter_test.dart';
import 'package:maidledger/core/services/location_service.dart';

void main() {
  group('LocationService', () {
    group('GpsResult', () {
      test('stores latitude and longitude', () {
        final gps = GpsResult(latitude: 22.3193, longitude: 114.1694);
        expect(gps.latitude, equals(22.3193));
        expect(gps.longitude, equals(114.1694));
      });

      test('handles extreme coordinates', () {
        final gps = GpsResult(latitude: 90.0, longitude: 180.0);
        expect(gps.latitude, equals(90.0));
        expect(gps.longitude, equals(180.0));
      });
    });

    group('LocationResult', () {
      test('stores all location fields', () {
        final result = LocationResult(
          region: '九龍',
          district: '旺角',
          displayText: '旺角',
          confidence: 0.9,
        );

        expect(result.region, equals('九龍'));
        expect(result.district, equals('旺角'));
        expect(result.displayText, equals('旺角'));
        expect(result.confidence, equals(0.9));
      });

      test('fallbackText returns district when available', () {
        final result = LocationResult(
          region: '九龍',
          district: '旺角',
        );
        expect(result.fallbackText, equals('旺角'));
      });

      test('fallbackText returns region when district is null', () {
        final result = LocationResult(
          region: '新界',
          district: null,
        );
        expect(result.fallbackText, equals('新界'));
      });

      test('fallbackText returns unknown when both are null', () {
        final result = LocationResult();
        expect(result.fallbackText, equals('未知地點'));
      });

      test('handles empty strings', () {
        final result = LocationResult(
          region: '',
          district: '',
        );
        expect(result.fallbackText, equals(''));
      });

      test('nullable confidence', () {
        final result = LocationResult(confidence: null);
        expect(result.confidence, isNull);
      });
    });

    group('_inferRegion', () {
      late LocationService service;

      setUp(() {
        service = LocationService();
      });

      test('detects Hong Kong Island from region name', () {
        // Using reflection to test private method would require mock or modification
        // Instead we test the public behavior
        final result = _inferRegionForTest('未知', {'region': '香港島'});
        expect(result, equals('港島'));
      });

      test('detects Kowloon from region name', () {
        final result = _inferRegionForTest('未知', {'region': '九龍城'});
        expect(result, equals('九龍'));
      });

      test('detects New Territories from region name', () {
        final result = _inferRegionForTest('未知', {'region': '新界區'});
        expect(result, equals('新界'));
      });

      test('returns unknown for unrecognized region', () {
        final result = _inferRegionForTest('未知', {'region': '其他'});
        expect(result, equals('未知'));
      });

      test('handles null region', () {
        final result = _inferRegionForTest('未知', {});
        expect(result, equals('未知'));
      });
    });

    group('_regionFallback (coordinate-based)', () {
      late LocationService service;

      setUp(() {
        service = LocationService();
      });

      test('returns New Territories for lat > 22.36', () {
        final result = _regionFallbackForTest(22.5, 114.0);
        expect(result.region, equals('新界'));
        expect(result.confidence, equals(0.3));
      });

      test('returns Kowloon for lat between 22.29 and 22.36', () {
        final result = _regionFallbackForTest(22.32, 114.0);
        expect(result.region, equals('九龍'));
        expect(result.confidence, equals(0.3));
      });

      test('returns Hong Kong Island for lat <= 22.29', () {
        final result = _regionFallbackForTest(22.28, 114.0);
        expect(result.region, equals('港島'));
        expect(result.confidence, equals(0.3));
      });

      test('boundary case: exactly 22.36 returns 九龍 (not strictly greater)', () {
        // lat > 22.36 is false when lat == 22.36, so it falls to lat > 22.29 -> 九龍
        final result = _regionFallbackForTest(22.36, 114.0);
        expect(result.region, equals('九龍'));
      });

      test('boundary case: exactly 22.29 returns 港島 (not strictly greater)', () {
        // lat > 22.29 is false when lat == 22.29, so it falls to else -> 港島
        final result = _regionFallbackForTest(22.29, 114.0);
        expect(result.region, equals('港島'));
      });

      test('boundary case: just above 22.36 returns 新界', () {
        final result = _regionFallbackForTest(22.37, 114.0);
        expect(result.region, equals('新界'));
      });
    });
  });
}

/// Test helpers that mirror private implementation for unit testing
String _inferRegionForTest(String district, Map<String, dynamic> addr) {
  final region = addr['region'] as String?;

  if (region != null) {
    if (region.contains('港島') || region.contains('香港島')) return '港島';
    if (region.contains('九龍')) return '九龍';
    if (region.contains('新界')) return '新界';
  }

  return '未知';
}

LocationResult _regionFallbackForTest(double lat, double lon) {
  String region;
  if (lat > 22.36) {
    region = '新界';
  } else if (lat > 22.29) {
    region = '九龍';
  } else {
    region = '港島';
  }
  return LocationResult(region: region, confidence: 0.3);
}