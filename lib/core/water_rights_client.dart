import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:prior/data/water_right.dart';

// Mapbox public token — restrict to bundle ID in Mapbox dashboard to prevent abuse
const _mapboxToken =
    'pk.eyJ1Ijoia3lkYXYiLCJhIjoiY21xcjNid29sMGtwMzJxcHd2czd6NmQ5aSJ9.NnCfgYoj6EK8Wg9E_dJXGg';
const _utahBbox = '-114.053,36.997,-109.041,42.001';

const _statewideParcel =
    'https://services1.arcgis.com/99lidPhWCzftIe9K/arcgis/rest/services/UtahStatewideParcels/FeatureServer/0';

const _plssLayer =
    'https://services1.arcgis.com/99lidPhWCzftIe9K/arcgis/rest/services/PLSS_Fabric/FeatureServer/1';

const _podLayer =
    'https://services.arcgis.com/ZzrwjTRez6FJiOq4/ArcGIS/rest/services/Utah_Points_of_Diversion/FeatureServer/0';

const _lirBase =
    'https://services1.arcgis.com/99lidPhWCzftIe9K/arcgis/rest/services';

final _coordPattern = RegExp(r'^(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)$');

class WaterRightsClient {
  WaterRightsClient._();
  static final instance = WaterRightsClient._();

  Future<LookupResult> lookupByAddress(String rawInput) async {
    final input = rawInput.trim();

    final coordMatch = _coordPattern.firstMatch(input);
    if (coordMatch != null) {
      final lat = double.tryParse(coordMatch.group(1)!);
      final lng = double.tryParse(coordMatch.group(2)!);
      if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) {
        return lookupByCoords(lat, lng, address: input);
      }
    }

    final coords = await _geocodeAddress(input);
    if (coords != null) {
      return lookupByCoords(coords.$1, coords.$2, address: input);
    }

    final parcelCenter = await _parcelCenterByNumber(input);
    if (parcelCenter != null) {
      return lookupByCoords(parcelCenter.$1, parcelCenter.$2, address: input);
    }

    return LookupResult.error(
      'Could not find that address, coordinates, or parcel number. '
      'Try "1234 Main St, St George" or "37.1, -113.5".',
    );
  }

  Future<LookupResult> lookupByCoords(
    double lat,
    double lng, {
    String? address,
  }) async {
    // Fetch PLSS and basic parcel data concurrently
    final plssFuture = _plssAtPoint(lat, lng);
    final parcelFuture = _parcelBasic(lat, lng);
    final plss = await plssFuture;
    final basic = await parcelFuture;

    // Fetch water rights and LIR data concurrently (both depend on basic parcel)
    final rightsFuture = _waterRightsForParcel(lat, lng, basic);
    final lirFuture = basic != null
        ? _lirData(lat, lng, basic.county)
        : Future<Map<String, dynamic>?>.value(null);
    final rights = await rightsFuture;
    final lir = await lirFuture;

    final parcelInfo = basic != null
        ? ParcelInfo(
            parcelId: basic.parcelId,
            address: basic.address,
            city: basic.city,
            zip: basic.zip,
            county: basic.county,
            ownType: basic.ownType,
            countyUrl: lir?['ASSESSOR_SRC'] as String? ?? basic.countyUrl,
            acres: (lir?['PARCEL_ACRES'] as num?)?.toDouble(),
            marketValue: (lir?['TOTAL_MKT_VALUE'] as num?)?.toDouble(),
            buildingSqft: (lir?['BLDG_SQFT'] as num?)?.toInt(),
            yearBuilt: (lir?['BUILT_YR'] as num?)?.toInt(),
            subdivName: lir?['SUBDIV_NAME'] as String?,
            propClass: lir?['PROP_CLASS'] as String?,
            isPrimaryRes: lir?['PRIMARY_RES'] == 'Y',
          )
        : null;

    return LookupResult(
      lat: lat,
      lng: lng,
      address: address,
      plssDescription: plss,
      parcelInfo: parcelInfo,
      rights: rights,
    );
  }

  Future<(double, double)?> _geocodeAddress(String address) async {
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/'
      '${Uri.encodeComponent(address)}.json'
      '?access_token=$_mapboxToken'
      '&country=us'
      '&types=address,place,locality,neighborhood,postcode'
      '&bbox=$_utahBbox'
      '&limit=1',
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final features = json['features'] as List?;
      if (features == null || features.isEmpty) return null;
      final coords =
          (features.first as Map<String, dynamic>)['geometry']?['coordinates']
              as List?;
      if (coords == null || coords.length < 2) return null;
      return ((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
    } catch (e) {
      debugPrint('Geocode error: $e');
      return null;
    }
  }

  Future<(double, double)?> _parcelCenterByNumber(String parcelId) async {
    final uri = Uri.parse('$_statewideParcel/query').replace(
      queryParameters: {
        'where': "UPPER(PARCEL_ID)='${parcelId.toUpperCase().replaceAll("'", "''")}'",
        'outFields': 'PARCEL_ID',
        'returnGeometry': 'true',
        'returnCentroid': 'true',
        'outSR': '4326',
        'resultRecordCount': '1',
        'f': 'json',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final features = json['features'] as List?;
      if (features == null || features.isEmpty) return null;
      final feature = features.first as Map<String, dynamic>;
      final centroid = feature['centroid'] as Map<String, dynamic>?;
      if (centroid != null) {
        final x = (centroid['x'] as num?)?.toDouble();
        final y = (centroid['y'] as num?)?.toDouble();
        if (x != null && y != null) return (y, x);
      }
      final rings =
          (feature['geometry'] as Map<String, dynamic>?)?['rings'] as List?;
      if (rings != null && rings.isNotEmpty) {
        final ring = rings.first as List;
        if (ring.isNotEmpty) {
          final pt = ring.first as List;
          return ((pt[1] as num).toDouble(), (pt[0] as num).toDouble());
        }
      }
      return null;
    } catch (e) {
      debugPrint('Parcel number lookup error: $e');
      return null;
    }
  }

  Future<String?> _plssAtPoint(double lat, double lng) async {
    final uri = Uri.parse('$_plssLayer/query').replace(
      queryParameters: {
        'geometry': '$lng,$lat',
        'geometryType': 'esriGeometryPoint',
        'spatialRel': 'esriSpatialRelIntersects',
        'inSR': '4326',
        'outFields': 'LABEL',
        'returnGeometry': 'false',
        'f': 'json',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final features = json['features'] as List?;
      if (features == null || features.isEmpty) return null;
      final a =
          (features.first as Map<String, dynamic>)['attributes']
              as Map<String, dynamic>? ??
          {};
      return a['LABEL']?.toString();
    } catch (e) {
      debugPrint('PLSS error: $e');
      return null;
    }
  }

  /// Fetches basic parcel data (polygon + statewide fields).
  Future<_BasicParcel?> _parcelBasic(double lat, double lng) async {
    final uri = Uri.parse('$_statewideParcel/query').replace(
      queryParameters: {
        'geometry': '$lng,$lat',
        'geometryType': 'esriGeometryPoint',
        'spatialRel': 'esriSpatialRelIntersects',
        'inSR': '4326',
        'outFields':
            'PARCEL_ID,PARCEL_ADD,PARCEL_CITY,PARCEL_ZIP,County,OWN_TYPE,CoParcel_URL',
        'returnGeometry': 'true',
        'outSR': '4326',
        'f': 'json',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final features = json['features'] as List?;
      if (features == null || features.isEmpty) return null;
      final feature = features.first as Map<String, dynamic>;
      final attrs = feature['attributes'] as Map<String, dynamic>? ?? {};
      final geom = feature['geometry'] as Map<String, dynamic>?;
      if (geom == null) return null;
      final rings = geom['rings'];
      if (rings == null) return null;
      return _BasicParcel(
        parcelId: attrs['PARCEL_ID']?.toString() ?? '',
        address: attrs['PARCEL_ADD']?.toString(),
        city: attrs['PARCEL_CITY']?.toString(),
        zip: attrs['PARCEL_ZIP']?.toString(),
        county: attrs['County']?.toString(),
        ownType: attrs['OWN_TYPE']?.toString(),
        countyUrl: attrs['CoParcel_URL']?.toString(),
        polygonJson: jsonEncode({
          'rings': rings,
          'spatialReference': {'wkid': 4326},
        }),
      );
    } catch (e) {
      debugPrint('Parcel basic error: $e');
      return null;
    }
  }

  /// Fetches LIR data for richer parcel info (acres, value, sqft, etc).
  Future<Map<String, dynamic>?> _lirData(
    double lat,
    double lng,
    String? county,
  ) async {
    if (county == null) return null;
    final svc = _lirServiceName(county);
    final uri = Uri.parse(
      '$_lirBase/Parcels_${svc}_LIR/FeatureServer/0/query',
    ).replace(
      queryParameters: {
        'geometry': '$lng,$lat',
        'geometryType': 'esriGeometryPoint',
        'spatialRel': 'esriSpatialRelIntersects',
        'inSR': '4326',
        'outFields':
            'PARCEL_ACRES,TOTAL_MKT_VALUE,BLDG_SQFT,BUILT_YR,SUBDIV_NAME,PROP_CLASS,PRIMARY_RES,ASSESSOR_SRC',
        'returnGeometry': 'false',
        'f': 'json',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final features = json['features'] as List?;
      if (features == null || features.isEmpty) return null;
      return (features.first as Map<String, dynamic>)['attributes']
          as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('LIR error for $county: $e');
      return null;
    }
  }

  String _lirServiceName(String county) {
    const map = {
      'Box Elder': 'BoxElder',
      'Salt Lake': 'SaltLake',
      'San Juan': 'SanJuan',
    };
    return map[county] ?? county.replaceAll(' ', '');
  }

  Future<List<WaterRight>> _waterRightsForParcel(
    double lat,
    double lng,
    _BasicParcel? parcel,
  ) async {
    final Map<String, String> params;
    if (parcel != null) {
      params = {
        'geometry': parcel.polygonJson,
        'geometryType': 'esriGeometryPolygon',
        'spatialRel': 'esriSpatialRelContains',
        'inSR': '4326',
        'outFields': '*',
        'returnGeometry': 'true',
        'outSR': '4326',
        'f': 'json',
      };
    } else {
      params = {
        'geometry': '$lng,$lat',
        'geometryType': 'esriGeometryPoint',
        'spatialRel': 'esriSpatialRelIntersects',
        'inSR': '4326',
        'distance': '150',
        'units': 'esriSRUnit_Meter',
        'outFields': '*',
        'returnGeometry': 'true',
        'outSR': '4326',
        'f': 'json',
      };
    }

    final uri = Uri.parse('$_podLayer/query').replace(queryParameters: params);
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final features = json['features'] as List? ?? [];

      final rights = features.map((f) {
        final attrs =
            (f as Map<String, dynamic>)['attributes']
                as Map<String, dynamic>? ??
            {};
        final geom = f['geometry'] as Map<String, dynamic>?;
        if (geom != null) {
          attrs['LAT'] = geom['y'];
          attrs['LNG'] = geom['x'];
        }
        return WaterRight.fromArcGis(attrs);
      }).toList();

      final seen = <String>{};
      return rights
          .where((r) => r.rightNumber.isEmpty || seen.add(r.rightNumber))
          .toList();
    } catch (e) {
      debugPrint('Water rights error: $e');
      return [];
    }
  }
}

class _BasicParcel {
  final String parcelId;
  final String? address;
  final String? city;
  final String? zip;
  final String? county;
  final String? ownType;
  final String? countyUrl;
  final String polygonJson;

  const _BasicParcel({
    required this.parcelId,
    this.address,
    this.city,
    this.zip,
    this.county,
    this.ownType,
    this.countyUrl,
    required this.polygonJson,
  });
}

class ParcelInfo {
  final String parcelId;
  final String? address;
  final String? city;
  final String? zip;
  final String? county;
  final String? ownType;
  final String? countyUrl;
  final double? acres;
  final double? marketValue;
  final int? buildingSqft;
  final int? yearBuilt;
  final String? subdivName;
  final String? propClass;
  final bool? isPrimaryRes;

  const ParcelInfo({
    required this.parcelId,
    this.address,
    this.city,
    this.zip,
    this.county,
    this.ownType,
    this.countyUrl,
    this.acres,
    this.marketValue,
    this.buildingSqft,
    this.yearBuilt,
    this.subdivName,
    this.propClass,
    this.isPrimaryRes,
  });

  String get displayAddress {
    final parts = [address, city, zip].whereType<String>().toList();
    return parts.join(', ');
  }
}

class LookupResult {
  final double? lat;
  final double? lng;
  final String? address;
  final String? plssDescription;
  final ParcelInfo? parcelInfo;
  final List<WaterRight> rights;
  final String? errorMessage;

  const LookupResult({
    this.lat,
    this.lng,
    this.address,
    this.plssDescription,
    this.parcelInfo,
    this.rights = const [],
    this.errorMessage,
  });

  const LookupResult.error(String message)
    : lat = null,
      lng = null,
      address = null,
      plssDescription = null,
      parcelInfo = null,
      rights = const [],
      errorMessage = message;

  bool get hasError => errorMessage != null;
}
