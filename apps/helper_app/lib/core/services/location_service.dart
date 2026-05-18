import 'dart:math';

class GpsResult {
  final double latitude;
  final double longitude;

  GpsResult({required this.latitude, required this.longitude});
}

class LocationResult {
  final String? region;
  final String? district;
  final String? market;
  final String? shopName;
  final GpsResult? gps;
  final double? confidence;

  LocationResult({
    this.region,
    this.district,
    this.market,
    this.shopName,
    this.gps,
    this.confidence,
  });

  String get displayText {
    if (market != null && shopName != null) return "$market - $shopName";
    if (market != null) return market!;
    if (district != null) return district!;
    if (region != null) return region!;
    return "未知地點";
  }
}

class LocationService {
  static const List<_MarketDb> _markets = [
    _MarketDb(name: '聯和墟街市', type: 'wet_market', region: '新界', district: '粉嶺', lat: 22.1234, lon: 114.1234),
    _MarketDb(name: '粉嶺聯和墟', type: 'wet_market', region: '新界', district: '粉嶺', lat: 22.1234, lon: 114.1234),
    _MarketDb(name: '鵝頸橋街市', type: 'wet_market', region: '港島', district: '灣仔', lat: 22.2345, lon: 114.2345),
    _MarketDb(name: '渣華街街市', type: 'wet_market', region: '港島', district: '北角', lat: 22.2915, lon: 114.3021),
    _MarketDb(name: '北角街市', type: 'wet_market', region: '港島', district: '北角', lat: 22.2915, lon: 114.3021),
    _MarketDb(name: '大埔墟街市', type: 'wet_market', region: '新界', district: '大埔', lat: 22.4456, lon: 114.1678),
    _MarketDb(name: '旺角街市', type: 'wet_market', region: '九龍', district: '旺角', lat: 22.3178, lon: 114.1689),
    _MarketDb(name: '旺角熟食市場', type: 'wet_market', region: '九龍', district: '旺角', lat: 22.3178, lon: 114.1689),
    _MarketDb(name: '深水埗街市', type: 'wet_market', region: '九龍', district: '深水埗', lat: 22.3298, lon: 114.1589),
    _MarketDb(name: '美孚街市', type: 'wet_market', region: '九龍', district: '美孚', lat: 22.3312, lon: 114.1423),
    _MarketDb(name: '九龍城街市', type: 'wet_market', region: '九龍', district: '九龍城', lat: 22.3412, lon: 114.1767),
    _MarketDb(name: '黃大仙街市', type: 'wet_market', region: '九龍', district: '黃大仙', lat: 22.3412, lon: 114.1767),
  ];

  static const List<_MarketDb> _supermarkets = [
    _MarketDb(name: '惠康超市', type: 'supermarket', region: '九龍', district: '旺角', lat: 22.3178, lon: 114.1689),
    _MarketDb(name: '惠康', type: 'supermarket', region: '九龍', district: '旺角', lat: 22.3178, lon: 114.1689),
    _MarketDb(name: '百佳超級市場', type: 'supermarket', region: '九龍', district: '旺角', lat: 22.3165, lon: 114.1695),
    _MarketDb(name: '百佳', type: 'supermarket', region: '九龍', district: '旺角', lat: 22.3165, lon: 114.1695),
    _MarketDb(name: '759阿信屋', type: 'supermarket', region: '九龍', district: '旺角', lat: 22.3180, lon: 114.1690),
  ];

  LocationResult? reverseGeocode(GpsResult gps, {double maxDistanceKm = 0.5}) {
    final allMarkets = [..._markets, ..._supermarkets];

    _MarketDb? closest;
    double minDist = double.infinity;

    for (final market in allMarkets) {
      final dist = _haversine(gps.latitude, gps.longitude, market.lat, market.lon);
      if (dist < minDist && dist <= maxDistanceKm) {
        minDist = dist;
        closest = market;
      }
    }

    if (closest == null) {
      return _regionFromCoords(gps.latitude, gps.longitude);
    }

    return LocationResult(
      region: closest.region,
      district: closest.district,
      market: closest.name,
      gps: gps,
      confidence: 1.0 - (minDist / maxDistanceKm),
    );
  }

  LocationResult? inferFromText(String text) {
    final lower = text.toLowerCase();

    for (final market in _markets) {
      if (lower.contains(market.name.toLowerCase())) {
        return LocationResult(
          region: market.region,
          district: market.district,
          market: market.name,
          confidence: 0.8,
        );
      }
    }

    for (final shop in _supermarkets) {
      if (lower.contains(shop.name.toLowerCase())) {
        return LocationResult(
          region: shop.region,
          district: shop.district,
          market: shop.name,
          shopName: shop.name,
          confidence: 0.7,
        );
      }
    }

    return null;
  }

  LocationResult _regionFromCoords(double lat, double lon) {
    String region;
    if (lat > 22.35) {
      region = '新界';
    } else if (lat > 22.28) {
      region = '九龍';
    } else {
      region = '港島';
    }
    return LocationResult(region: region, confidence: 0.3);
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * 3.141592653589793 / 180;
}

class _MarketDb {
  final String name;
  final String type;
  final String region;
  final String district;
  final double lat;
  final double lon;

  const _MarketDb({
    required this.name,
    required this.type,
    required this.region,
    required this.district,
    required this.lat,
    required this.lon,
  });
}