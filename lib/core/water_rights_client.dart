import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:prior/data/water_right.dart';

// Mapbox public token — restrict to bundle ID in Mapbox dashboard to prevent abuse
const _mapboxToken =
    'pk.eyJ1Ijoia3lkYXYiLCJhIjoiY21xcjNid29sMGtwMzJxcHd2czd6NmQ5aSJ9.NnCfgYoj6EK8Wg9E_dJXGg';

// Geocoding bbox covering Utah + Colorado
const _westernBbox = '-114.053,36.992,-102.040,42.001';

// ── Utah ──────────────────────────────────────────────────────────────────────
const _utahParcelUrl =
    'https://services1.arcgis.com/99lidPhWCzftIe9K/arcgis/rest/services/UtahStatewideParcels/FeatureServer/0';
const _utahPodUrl =
    'https://services.arcgis.com/ZzrwjTRez6FJiOq4/ArcGIS/rest/services/Utah_Points_of_Diversion/FeatureServer/0';
const _utahLirBase =
    'https://services1.arcgis.com/99lidPhWCzftIe9K/arcgis/rest/services';

// ── Colorado ──────────────────────────────────────────────────────────────────
const _coParcelUrl =
    'https://gis.colorado.gov/public/rest/services/Address_and_Parcel/Colorado_Public_Parcels/FeatureServer/0';
const _cdssStructuresUrl = 'https://dwr.state.co.us/Rest/GET/api/v2/structures';

// ── National ──────────────────────────────────────────────────────────────────
// BLM national PLSS — layer 2 = sections (first divisions)
const _blmPlssUrl =
    'https://gis.blm.gov/arcgis/rest/services/Cadastral/BLM_Natl_PLSS_CadNSDI/MapServer/2';

final _coordPattern = RegExp(r'^(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)$');

enum _State { utah, colorado, unknown }

_State _detectState(double lat, double lng) {
  // Colorado: roughly 37.0–41.0 N, 102.0–109.1 W
  if (lat >= 36.99 && lat <= 41.01 && lng >= -109.07 && lng <= -102.03) {
    return _State.colorado;
  }
  // Utah: roughly 37.0–42.0 N, 109.0–114.1 W
  if (lat >= 36.99 && lat <= 42.01 && lng >= -114.06 && lng <= -109.03) {
    return _State.utah;
  }
  return _State.unknown;
}

class WaterRightsClient {
  WaterRightsClient._();
  static final instance = WaterRightsClient._();

  http.Client? _coParcelClient;

  void cancelColoradoLookup() {
    _coParcelClient?.close();
    _coParcelClient = null;
  }

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
      'Try "1234 Main St, Denver CO" or "39.73, -104.99".',
    );
  }

  Future<LookupResult> lookupByCoords(
    double lat,
    double lng, {
    String? address,
  }) async {
    final state = _detectState(lat, lng);

    switch (state) {
      case _State.utah:
        return _lookupUtah(lat, lng, address: address);
      case _State.colorado:
        return _lookupColorado(lat, lng, address: address);
      case _State.unknown:
        // Try Utah then Colorado parcel services as fallback
        final result = await _lookupUtah(lat, lng, address: address);
        if (result.parcelInfo != null || result.rights.isNotEmpty) {
          return result;
        }
        return _lookupColorado(lat, lng, address: address);
    }
  }

  // ── Utah ───────────────────────────────────────────────────────────────────

  Future<LookupResult> _lookupUtah(
    double lat,
    double lng, {
    String? address,
  }) async {
    final plssFuture = _plssAtPoint(lat, lng);
    final parcelFuture = _utahParcelBasic(lat, lng);
    final plss = await plssFuture;
    final basic = await parcelFuture;

    final rightsFuture = _utahWaterRights(lat, lng, basic);
    final lirFuture = basic != null
        ? _utahLirData(lat, lng, basic.county)
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
            state: 'UT',
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

  Future<_BasicParcel?> _utahParcelBasic(double lat, double lng) async {
    final uri = Uri.parse('$_utahParcelUrl/query').replace(
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
      debugPrint('Utah parcel error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _utahLirData(
    double lat,
    double lng,
    String? county,
  ) async {
    if (county == null) return null;
    final svc = _utahLirServiceName(county);
    final uri =
        Uri.parse(
          '$_utahLirBase/Parcels_${svc}_LIR/FeatureServer/0/query',
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
      debugPrint('Utah LIR error for $county: $e');
      return null;
    }
  }

  String _utahLirServiceName(String county) {
    const map = {
      'Box Elder': 'BoxElder',
      'Salt Lake': 'SaltLake',
      'San Juan': 'SanJuan',
    };
    return map[county] ?? county.replaceAll(' ', '');
  }

  Future<List<WaterRight>> _utahWaterRights(
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

    final uri = Uri.parse(
      '$_utahPodUrl/query',
    ).replace(queryParameters: params);
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
      debugPrint('Utah water rights error: $e');
      return [];
    }
  }

  // ── Colorado ───────────────────────────────────────────────────────────────

  Future<LookupResult> _lookupColorado(
    double lat,
    double lng, {
    String? address,
  }) async {
    final plssFuture = _plssAtPoint(lat, lng);
    final parcelFuture = _coloradoParcelBasic(lat, lng);
    final rightsFuture = _coloradoWaterRights(lat, lng);
    final plss = await plssFuture;
    final basic = await parcelFuture;
    final rights = await rightsFuture;

    final parcelInfo = basic != null
        ? ParcelInfo(
            parcelId: basic.parcelId,
            address: basic.address,
            city: basic.city,
            zip: basic.zip,
            county: basic.county,
            state: 'CO',
            ownType: basic.ownType,
            acres: basic.acres,
            marketValue: basic.marketValue,
            subdivName: basic.subdivName,
            propClass: basic.propClass,
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

  Future<_BasicParcel?> _coloradoParcelBasic(double lat, double lng) async {
    final uri = Uri.parse('$_coParcelUrl/query').replace(
      queryParameters: {
        'geometry': '$lng,$lat',
        'geometryType': 'esriGeometryPoint',
        'spatialRel': 'esriSpatialRelIntersects',
        'inSR': '4326',
        'outFields':
            'parcel_id,situsAdd,sitAddCty,sitAddZip,countyName,owner,landAcres,apprValTot,subName,landUseDsc',
        'returnGeometry': 'true',
        'outSR': '4326',
        'f': 'json',
      },
    );
    _coParcelClient = http.Client();
    try {
      final res = await _coParcelClient!
          .get(uri)
          .timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final features = json['features'] as List?;
      if (features == null || features.isEmpty) return null;
      final feature = features.first as Map<String, dynamic>;
      final attrs = feature['attributes'] as Map<String, dynamic>? ?? {};
      final geom = feature['geometry'] as Map<String, dynamic>?;
      final rings = geom?['rings'];

      return _BasicParcel(
        parcelId: attrs['parcel_id']?.toString() ?? '',
        address: attrs['situsAdd']?.toString(),
        city: attrs['sitAddCty']?.toString(),
        zip: attrs['sitAddZip']?.toString(),
        county: attrs['countyName']?.toString(),
        ownType: attrs['owner']?.toString(),
        polygonJson: rings != null
            ? jsonEncode({
                'rings': rings,
                'spatialReference': {'wkid': 4326},
              })
            : '{}',
        acres: (attrs['landAcres'] as num?)?.toDouble(),
        marketValue: double.tryParse(attrs['apprValTot']?.toString() ?? ''),
        subdivName: attrs['subName']?.toString(),
        propClass: attrs['landUseDsc']?.toString(),
      );
    } catch (e) {
      debugPrint('Colorado parcel error: $e');
      return null;
    } finally {
      _coParcelClient?.close();
      _coParcelClient = null;
    }
  }

  Future<List<WaterRight>> _coloradoWaterRights(double lat, double lng) async {
    // CDSS structures within 0.15 miles (~240m) of the point
    final uri = Uri.parse(_cdssStructuresUrl).replace(
      queryParameters: {
        'latitude': lat.toStringAsFixed(6),
        'longitude': lng.toStringAsFixed(6),
        'radius': '0.15',
        'units': 'miles',
        'format': 'json',
        'pageSize': '50',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final results = json['ResultList'] as List? ?? [];

      final rights = results
          .map((r) => WaterRight.fromCdss(r as Map<String, dynamic>))
          .toList();

      final seen = <String>{};
      return rights.where((r) => seen.add(r.rightNumber)).toList();
    } catch (e) {
      debugPrint('Colorado water rights error: $e');
      return [];
    }
  }

  // ── National PLSS (BLM) ────────────────────────────────────────────────────

  Future<String?> _plssAtPoint(double lat, double lng) async {
    final uri = Uri.parse('$_blmPlssUrl/query').replace(
      queryParameters: {
        'geometry': '$lng,$lat',
        'geometryType': 'esriGeometryPoint',
        'spatialRel': 'esriSpatialRelIntersects',
        'inSR': '4326',
        'outFields': 'FRSTDIVNO,TWNSHPLAB,PRINMER,STATEABBR',
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
      final section = a['FRSTDIVNO']?.toString();
      final twnshp = a['TWNSHPLAB']?.toString();
      final pm = a['PRINMER']?.toString();
      if (section == null && twnshp == null) return null;
      final parts = [if (section != null) 'Sec. $section', ?twnshp, ?pm];
      return parts.join(', ');
    } catch (e) {
      debugPrint('PLSS error: $e');
      return null;
    }
  }

  // ── Geocoding ──────────────────────────────────────────────────────────────

  Future<(double, double)?> _geocodeAddress(String address) async {
    final uri = Uri.parse(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/'
      '${Uri.encodeComponent(address)}.json'
      '?access_token=$_mapboxToken'
      '&country=us'
      '&types=address,place,locality,neighborhood,postcode'
      '&bbox=$_westernBbox'
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
    // Try Utah first, then Colorado
    final utahResult = await _parcelCenterUtah(parcelId);
    if (utahResult != null) return utahResult;
    return _parcelCenterColorado(parcelId);
  }

  Future<(double, double)?> _parcelCenterUtah(String parcelId) async {
    final uri = Uri.parse('$_utahParcelUrl/query').replace(
      queryParameters: {
        'where':
            "UPPER(PARCEL_ID)='${parcelId.toUpperCase().replaceAll("'", "''")}'",
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
      debugPrint('Utah parcel number lookup error: $e');
      return null;
    }
  }

  Future<(double, double)?> _parcelCenterColorado(String parcelId) async {
    final uri = Uri.parse('$_coParcelUrl/query').replace(
      queryParameters: {
        'where':
            "UPPER(parcel_id)='${parcelId.toUpperCase().replaceAll("'", "''")}'",
        'outFields': 'parcel_id',
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
      return null;
    } catch (e) {
      debugPrint('Colorado parcel number lookup error: $e');
      return null;
    }
  }
}

// ── Internal models ────────────────────────────────────────────────────────────

class _BasicParcel {
  final String parcelId;
  final String? address;
  final String? city;
  final String? zip;
  final String? county;
  final String? ownType;
  final String? countyUrl;
  final String polygonJson;
  // Colorado-only extras (no LIR equivalent — comes from statewide parcel)
  final double? acres;
  final double? marketValue;
  final String? subdivName;
  final String? propClass;

  const _BasicParcel({
    required this.parcelId,
    this.address,
    this.city,
    this.zip,
    this.county,
    this.ownType,
    this.countyUrl,
    required this.polygonJson,
    this.acres,
    this.marketValue,
    this.subdivName,
    this.propClass,
  });
}

// ── Public models ──────────────────────────────────────────────────────────────

class ParcelInfo {
  final String parcelId;
  final String? address;
  final String? city;
  final String? zip;
  final String? county;
  final String state;
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
    this.state = 'UT',
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
    final parts = [address, city, state, zip].whereType<String>().toList();
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
