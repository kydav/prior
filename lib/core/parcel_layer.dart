import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const _utahParcelUrl =
    'https://services1.arcgis.com/99lidPhWCzftIe9K/arcgis/rest/services/UtahStatewideParcels/FeatureServer/0';

const _sourceId = 'parcel-boundaries';
const _layerId = 'parcel-lines';
const _coSourceId = 'co-parcel-source';
const _coLayerId = 'co-parcel-lines';
const _minZoomToShow = 12.5;
const _maxParcels = 150;

bool _isColoradoCenter(double lat, double lng) =>
    lat >= 36.99 && lat <= 41.01 && lng >= -109.07 && lng <= -102.03;

bool _isUtahCenter(double lat, double lng) =>
    lat >= 36.99 && lat <= 42.01 && lng >= -114.06 && lng <= -109.03;

class ParcelLayer {
  ParcelLayer._();

  static bool _layerAdded = false;
  static final isFetching = ValueNotifier<bool>(false);
  static http.Client? _client;
  static double? _lastMinLng, _lastMinLat, _lastMaxLng, _lastMaxLat;

  static Future<void> setup(MapboxMap map) async {
    _layerAdded = false;
    _lastMinLng = _lastMinLat = _lastMaxLng = _lastMaxLat = null;
    try {
      // Utah: dynamic GeoJSON fetched from ArcGIS
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
            lineColor: 0xFFFFAB40,
            lineOpacity: 0.9,
            lineWidth: 1.5,
          ),
        );
      }

      // Colorado: vector tiles served from PMTiles on Cloudflare R2
      final coSourceExists = await map.style.styleSourceExists(_coSourceId);
      if (!coSourceExists) {
        await map.style.addSource(
          VectorSource(
            id: _coSourceId,
            tiles: ['https://auaha.app/tiles/co/{z}/{x}/{y}.mvt'],
            minzoom: 12,
            maxzoom: 16,
          ),
        );
      }
      final coLayerExists = await map.style.styleLayerExists(_coLayerId);
      if (!coLayerExists) {
        await map.style.addLayer(
          LineLayer(
            id: _coLayerId,
            sourceId: _coSourceId,
            sourceLayer: 'parcels',
            lineColor: 0xFFFFAB40,
            lineOpacity: 0.9,
            lineWidth: 1.5,
            minZoom: _minZoomToShow,
          ),
        );
      }

      _layerAdded = true;
    } catch (e) {
      debugPrint('ParcelLayer setup error: $e');
    }
  }

  static Future<void> onIdle(MapboxMap map) async {
    if (!_layerAdded) return;

    try {
      final camera = await map.getCameraState();
      final center = camera.center.coordinates;
      final lat = center.lat.toDouble();
      final lng = center.lng.toDouble();

      if (camera.zoom < _minZoomToShow) {
        await _setData(map, '{"type":"FeatureCollection","features":[]}');
        return;
      }

      // Colorado uses vector tiles — Mapbox loads them automatically, nothing to fetch.
      if (_isColoradoCenter(lat, lng)) {
        await _setData(map, '{"type":"FeatureCollection","features":[]}');
        return;
      }

      // Outside supported states: clear GeoJSON layer.
      if (!_isUtahCenter(lat, lng)) {
        await _setData(map, '{"type":"FeatureCollection","features":[]}');
        return;
      }

      // Utah: fetch parcel GeoJSON from ArcGIS.
      if (isFetching.value) return;

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
          _utahParcelUrl,
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
      final res = await _client!.get(uri).timeout(const Duration(seconds: 100));
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

  /// Query properties of a Colorado parcel at the given screen position.
  /// Returns null if no CO parcel tile feature is rendered there.
  static Future<Map<String, dynamic>?> queryProperties(
    MapboxMap map,
    ScreenCoordinate screenCoord,
  ) async {
    try {
      final result = await map.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenCoordinate(screenCoord),
        RenderedQueryOptions(layerIds: [_coLayerId], filter: null),
      );
      if (result.isEmpty) return null;
      final props = result.first?.queriedFeature.feature['properties'];
      if (props is! Map) return null;
      return Map<String, dynamic>.from(
        props.map((k, v) => MapEntry(k?.toString() ?? '', v)),
      );
    } catch (e) {
      debugPrint('ParcelLayer.queryProperties error: $e');
      return null;
    }
  }

  static bool isColorado(double lat, double lng) =>
      _isColoradoCenter(lat, lng);

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
