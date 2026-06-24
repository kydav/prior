import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:prior/core/parcel_layer.dart';
import 'package:prior/core/water_rights_client.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchCtrl = TextEditingController();
  MapboxMap? _map;
  bool _searching = false;
  bool _showingLines = false;

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    await ParcelLayer.setup(map);
  }

  Future<void> _onMapIdle(MapIdleEventData _) async {
    if (_map == null) return;
    final camera = await _map!.getCameraState();
    final atZoom = camera.zoom >= 14.5;
    if (atZoom != _showingLines) setState(() => _showingLines = atZoom);
    await ParcelLayer.onIdle(_map!);
  }

  Future<void> _searchAddress() async {
    final address = _searchCtrl.text.trim();
    if (address.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final result = await WaterRightsClient.instance.lookupByAddress(address);
      if (!mounted) return;
      if (result.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage!)),
        );
      } else {
        // Fly to the result location
        if (result.lat != null && result.lng != null && _map != null) {
          await _map!.flyTo(
            CameraOptions(
              center: Point(
                coordinates: Position(result.lng!, result.lat!),
              ),
              zoom: 16,
            ),
            MapAnimationOptions(duration: 1200),
          );
        }
        if (mounted) context.push('/detail', extra: result.rights);
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _onMapTap(MapContentGestureContext ctx) async {
    if (_searching) return;
    setState(() => _searching = true);
    try {
      final coord = ctx.point.coordinates;
      final result = await WaterRightsClient.instance.lookupByCoords(
        coord.lat.toDouble(),
        coord.lng.toDouble(),
      );
      if (!mounted) return;
      if (result.rights.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No water rights found near this location')),
        );
      } else {
        context.push('/detail', extra: result.rights);
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prior'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_outline),
            onPressed: () => context.push('/saved'),
          ),
        ],
      ),
      body: Stack(
        children: [
          MapWidget(
            onMapCreated: _onMapCreated,
            onMapIdleListener: _onMapIdle,
            onTapListener: _onMapTap,
            cameraOptions: CameraOptions(
              center: Point(coordinates: Position(-113.583, 37.105)),
              zoom: 10,
            ),
          ),
          // Search bar
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Enter an address...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchAddress(),
              ),
            ),
          ),
          // Hint card at bottom
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.water_drop, color: Colors.lightBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _showingLines
                            ? 'Tap a parcel to look up water rights'
                            : 'Zoom in to see property lines · Tap to look up water rights',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    ParcelLayer.reset();
    super.dispose();
  }
}
