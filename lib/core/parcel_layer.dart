import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const _statewide =
    'https://services1.arcgis.com/99lidPhWCzftIe9K/arcgis/rest/services/UtahStatewideParcels/FeatureServer/0';

const _sourceId = 'parcel-boundaries';
const _layerId = 'parcel-lines';
const _minZoomToShow = 14.5;
const _maxParcels = 300;

class ParcelLayer {
  ParcelLayer._();

  static GeoJsonSource? _source;
  static bool _layerAdded = false;

  // Call once after map style is loaded
  static Future<void> setup(MapboxMap map) async {
    _layerAdded = false;
    _source = GeoJsonSource(
      id: _sourceId,
      data: '{"type":"FeatureCollection","features":[]}',
    );
    try {
      await map.style.addSource(_source!);
      await map.style.addLayer(
        LineLayer(
          id: _layerId,
          sourceId: _sourceId,
          lineColor: 0xFF4DD0E1, // teal
          lineOpacity: 0.65,
          lineWidth: 1.2,
        ),
      );
      _layerAdded = true;
    } catch (e) {
      debugPrint('ParcelLayer setup error: $e');
    }
  }

  // Call on map idle — updates parcel lines for the current viewport
  static Future<void> onIdle(MapboxMap map) async {
    if (!_layerAdded || _source == null) return;

    final camera = await map.getCameraState();
    if ((camera.zoom) < _minZoomToShow) {
      await _source!.updateGeoJSON(
        '{"type":"FeatureCollection","features":[]}',
      );
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

    final geojson = await _fetchParcelGeoJson(minLng, minLat, maxLng, maxLat);
    if (geojson != null) {
      await _source!.updateGeoJSON(geojson);
    }
  }

  static Future<String?> _fetchParcelGeoJson(
    double minLng,
    double minLat,
    double maxLng,
    double maxLat,
  ) async {
    final uri = Uri.parse('$_statewide/query').replace(queryParameters: {
      'geometry': '$minLng,$minLat,$maxLng,$maxLat',
      'geometryType': 'esriGeometryEnvelope',
      'spatialRel': 'esriSpatialRelIntersects',
      'inSR': '4326',
      'outFields': 'PARCEL_ID',
      'returnGeometry': 'true',
      'outSR': '4326',
      'resultRecordCount': '$_maxParcels',
      'f': 'geojson',
    });
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      // Validate it's real GeoJSON before returning
      final json = jsonDecode(res.body);
      if (json['type'] == null) return null;
      return res.body;
    } catch (e) {
      debugPrint('ParcelLayer fetch error: $e');
      return null;
    }
  }

  static void reset() {
    _source = null;
    _layerAdded = false;
  }
}
