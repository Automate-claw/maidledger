import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

// GpsResult is defined in this file

class GpsResult {
  final double latitude;
  final double longitude;

  GpsResult({required this.latitude, required this.longitude});
}

class LocationResult {
  final String? region;   // 港島 / 九龍 / 新界
  final String? district; // 荃灣、筲箕灣、灣仔等
  final String? displayText;
  final double? confidence;

  LocationResult({
    this.region,
    this.district,
    this.displayText,
    this.confidence,
  });

  String get fallbackText {
    if (district != null) return district!;
    if (region != null) return region!;
    return "未知地點";
  }
}

class LocationService {
  /// Nominatim reverse geocode: GPS → district/region name
  /// Falls back to coordinate-based region if Nominatim fails or times out.
  Future<LocationResult?> reverseGeocode(GpsResult gps) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${gps.latitude}&lon=${gps.longitude}'
        '&format=json&accept-language=zh-tw',
      );

      debugPrint('🔵 [reverseGeocode] requesting: $uri');

      final httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final req = await httpClient.getUrl(uri);
      req.headers.set('User-Agent', 'MaidLedgerApp/1.0 (contact: wandvault@gmail.com)');
      req.headers.set('Accept', 'application/json');

      final resp = await req.close();
      debugPrint('🔵 [reverseGeocode] response status: ${resp.statusCode}');

      if (resp.statusCode != 200) {
        final body = await resp.transform(utf8.decoder).join();
        debugPrint('🔵 [reverseGeocode] non-200 body: ${body.substring(0, body.length < 200 ? body.length : 200)}');
        return _regionFallback(gps.latitude, gps.longitude);
      }

      final jsonStr = await resp
          .transform(utf8.decoder)
          .join();

      debugPrint('🔵 [reverseGeocode] response body (${jsonStr.length} chars): ${jsonStr.substring(0, jsonStr.length < 300 ? jsonStr.length : 300)}');

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final addr = json['address'] as Map<String, dynamic>?;

      if (addr == null) {
        debugPrint('🔵 [reverseGeocode] addr=null, falling back to coordinates');
        return _regionFallback(gps.latitude, gps.longitude);
      }

      // District: suburb gives fine-grained names (筲箕灣, 灣仔).
      // city_district is broader (香港島, 九龍城) and used as fallback.
      // Priority: suburb > city_district > town > village > city > county
      final district = addr['suburb']
          ?? addr['city_district']
          ?? addr['town']
          ?? addr['village']
          ?? addr['city']
          ?? addr['county'];

      debugPrint('🔵 [reverseGeocode] district=$district addr=$addr');

      // Region is derived from city_district directly — no hardcoded inference needed
      final region = _cityDistrictToRegion(addr['city_district']);

      return LocationResult(
        region: region,
        district: district,
        displayText: district ?? region,
        confidence: 0.9,
      );
    } catch (e, stack) {
      debugPrint('🔵 [reverseGeocode] ERROR: $e');
      debugPrint('🔵 [reverseGeocode] stack: $stack');
      return _regionFallback(gps.latitude, gps.longitude);
    }
  }

  String _cityDistrictToRegion(String? cityDistrict) {
    if (cityDistrict == null) return '未知';
    if (cityDistrict.contains('香港島') || cityDistrict == '香港') return '港島';
    if (cityDistrict.contains('九龍')) return '九龍';
    if (cityDistrict.contains('新界')) return '新界';
    return '未知';
  }

  LocationResult _regionFallback(double lat, double lon) {
    // Rough fallback using coordinates only
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

  /// Extract location from EXIF bytes (photo GPS) — no network needed
  /// This is used when user sends a photo with embedded GPS
  LocationResult? reverseGeocodeLocal(GpsResult gps) {
    // No local DB needed, delegate to async Nominatim
    // This sync version just returns the coordinate-based fallback
    return _regionFallback(gps.latitude, gps.longitude);
  }
}