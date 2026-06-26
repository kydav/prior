import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const _utahParcelUrl =
    'https://services1.arcgis.com/99lidPhWCzftIe9K/arcgis/rest/services/UtahStatewideParcels/FeatureServer/0';
const _coloradoParcelUrl =
    'https://gis.colorado.gov/public/rest/services/Address_and_Parcel/Colorado_Public_Parcels/FeatureServer/0';

const _sourceId = 'parcel-boundaries';
const _layerId = 'parcel-lines';
const _minZoomToShow = 12.5;
const _maxParcels = 150;

String? _parcelUrlForCenter(double lat, double lng) {
  if (lat >= 36.99 && lat <= 41.01 && lng >= -109.07 && lng <= -102.03) {
    return _coloradoParcelUrl;
  }
  if (lat >= 36.99 && lat <= 42.01 && lng >= -114.06 && lng <= -109.03) {
    return _utahParcelUrl;
  }
  return null;
}

class ParcelLayer {
  ParcelLayer._();

  static bool _layerAdded = false;
  static final isFetching = ValueNotifier<bool>(false);
  static http.Client? _client;
  // Last successfully fetched bbox — skip re-fetch if viewport hasn't moved much
  static double? _lastMinLng, _lastMinLat, _lastMaxLng, _lastMaxLat;

  /// Call whenever the map style loads (or reloads). Safe to call multiple times.
  static Future<void> setup(MapboxMap map) async {
    _layerAdded = false;
    _lastMinLng = _lastMinLat = _lastMaxLng = _lastMaxLat = null;
    try {
      // Only add source/layer if the style doesn't already have them —
      // avoids duplicate-add errors on re-entry.
      final sourceExists = await map.style.styleSourceExists(_sourceId);
      if (!sourceExists) {
        await map.style.addSource(
          GeoJsonSource(
            id: _sourceId,
            data: '{"type":"FeatureCollection","features":[]}',
          ),
        );
      }
      final layerExists = await map.style.styleLayerExists(_layerId);
      if (!layerExists) {
        await map.style.addLayer(
          LineLayer(
            id: _layerId,
            sourceId: _sourceId,
            lineColor: 0xFFFFAB40, // amber — distinct from blue water features
            lineOpacity: 0.9,
            lineWidth: 1.5,
          ),
        );
      }
      _layerAdded = true;
    } catch (e) {
      debugPrint('ParcelLayer setup error: $e');
    }
  }

  /// Call on map idle — updates parcel lines for the current viewport.
  static Future<void> onIdle(MapboxMap map) async {
    if (!_layerAdded) return;

    try {
      final camera = await map.getCameraState();
      if (camera.zoom < _minZoomToShow) {
        await _setData(map, '{"type":"FeatureCollection","features":[]}');
        return;
      }

      final center = camera.center.coordinates;
      final serviceUrl = _parcelUrlForCenter(
        center.lat.toDouble(),
        center.lng.toDouble(),
      );
      if (serviceUrl == null) {
        await _setData(map, '{"type":"FeatureCollection","features":[]}');
        return;
      }

      final bounds = await map.coordinateBoundsForCamera(
        CameraOptions(
          center: camera.center,
          zoom: camera.zoom,
          bearing: camera.bearing,
          pitch: camera.pitch,
        ),
      );

      final sw = bounds.southwest.coordinates;
      final ne = bounds.northeast.coordinates;
      final minLng = sw.lng.toDouble();
      final minLat = sw.lat.toDouble();
      final maxLng = ne.lng.toDouble();
      final maxLat = ne.lat.toDouble();

      // Skip if a fetch is already in flight.
      if (isFetching.value) return;

      // Skip if the viewport hasn't moved more than ~30% of its width/height
      // since the last successful fetch (avoids re-fetching on tiny pans).
      if (_lastMinLng != null) {
        final widthThreshold = (maxLng - minLng) * 0.3;
        final heightThreshold = (maxLat - minLat) * 0.3;
        if ((minLng - _lastMinLng!).abs() < widthThreshold &&
            (maxLng - _lastMaxLng!).abs() < widthThreshold &&
            (minLat - _lastMinLat!).abs() < heightThreshold &&
            (maxLat - _lastMaxLat!).abs() < heightThreshold) {
          return;
        }
      }

      isFetching.value = true;
      try {
        final geojson = await _fetchParcelGeoJson(
          serviceUrl,
          minLng,
          minLat,
          maxLng,
          maxLat,
        );
        if (geojson != null) {
          await _setData(map, geojson);
          _lastMinLng = minLng;
          _lastMinLat = minLat;
          _lastMaxLng = maxLng;
          _lastMaxLat = maxLat;
        }
      } finally {
        isFetching.value = false;
      }
    } catch (e) {
      // Style was likely reloaded — re-add source and layer on next idle
      debugPrint('ParcelLayer onIdle error, will re-setup: $e');
      _layerAdded = false;
    }
  }

  static Future<void> _setData(MapboxMap map, String geojson) async {
    await map.style.setStyleSourceProperty(_sourceId, 'data', geojson);
  }

  static Future<String?> _fetchParcelGeoJson(
    String serviceUrl,
    double minLng,
    double minLat,
    double maxLng,
    double maxLat,
  ) async {
    final uri = Uri.parse('$serviceUrl/query').replace(
      queryParameters: {
        'geometry': '$minLng,$minLat,$maxLng,$maxLat',
        'geometryType': 'esriGeometryEnvelope',
        'spatialRel': 'esriSpatialRelIntersects',
        'inSR': '4326',
        'outFields': 'OBJECTID',
        'returnGeometry': 'true',
        'outSR': '4326',
        'maxAllowableOffset': '0.0001',
        'resultRecordCount': '$_maxParcels',
        'f': 'geojson',
      },
    );
    _client = http.Client();
    try {
      final res = await _client!
          .get(uri)
          .timeout(const Duration(seconds: 100));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      if (json['type'] == null) return null;
      return res.body;
    } catch (e) {
      debugPrint('ParcelLayer fetch error: $e');
      return null;
    } finally {
      _client?.close();
      _client = null;
    }
  }

  static void cancelFetch() {
    _client?.close();
    _client = null;
  }

  static void reset() {
    cancelFetch();
    _layerAdded = false;
    isFetching.value = false;
    _lastMinLng = _lastMinLat = _lastMaxLng = _lastMaxLat = null;
  }
}
