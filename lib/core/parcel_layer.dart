import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const _statewide =
    'https://services1.arcgis.com/99lidPhWCzftIe9K/arcgis/rest/services/UtahStatewideParcels/FeatureServer/0';

const _sourceId = 'parcel-boundaries';
const _layerId = 'parcel-lines';
const _minZoomToShow = 12.5;
const _maxParcels = 300;

class ParcelLayer {
  ParcelLayer._();

  static bool _layerAdded = false;

  /// Call whenever the map style loads (or reloads). Safe to call multiple times.
  static Future<void> setup(MapboxMap map) async {
    _layerAdded = false;
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
      final geojson = await _fetchParcelGeoJson(
        sw.lng.toDouble(),
        sw.lat.toDouble(),
        ne.lng.toDouble(),
        ne.lat.toDouble(),
      );
      if (geojson != null) await _setData(map, geojson);
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
    double minLng,
    double minLat,
    double maxLng,
    double maxLat,
  ) async {
    final uri = Uri.parse('$_statewide/query').replace(
      queryParameters: {
        'geometry': '$minLng,$minLat,$maxLng,$maxLat',
        'geometryType': 'esriGeometryEnvelope',
        'spatialRel': 'esriSpatialRelIntersects',
        'inSR': '4326',
        'outFields': 'PARCEL_ID',
        'returnGeometry': 'true',
        'outSR': '4326',
        'resultRecordCount': '$_maxParcels',
        'f': 'geojson',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      if (json['type'] == null) return null;
      return res.body;
    } catch (e) {
      debugPrint('ParcelLayer fetch error: $e');
      return null;
    }
  }

  static void reset() {
    _layerAdded = false;
  }
}
