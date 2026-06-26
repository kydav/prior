import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:prior/core/parcel_layer.dart';
import 'package:prior/core/water_rights_client.dart';
import 'package:prior/features/detail/detail_screen.dart' show WaterRightCard;
import 'package:prior/features/search/search_loader_card.dart';
import 'package:url_launcher/url_launcher.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchCtrl = TextEditingController();
  // Stable reference — must not be recreated on rebuild or the map resets camera
  final _initialViewport = CameraViewportState(
    center: Point(coordinates: Position(-113.583, 37.105)),
    zoom: 10,
  );
  MapboxMap? _map;
  bool _searching = false;
  bool _showingLines = false;
  bool _locating = false;
  String _currentStyle = MapboxStyles.STANDARD;

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    map.addInteraction(
      TapInteraction.onMap((ctx) async {
        if (_searching || !_showingLines) return;
        final coord = ctx.point.coordinates;
        await _runQuery(
          () => WaterRightsClient.instance.lookupByCoords(
            coord.lat.toDouble(),
            coord.lng.toDouble(),
          ),
          isTap: true,
        );
      }),
    );
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    if (_map == null) return;
    await ParcelLayer.setup(_map!);
  }

  Future<void> _onMapIdle(MapIdleEventData _) async {
    if (_map == null) return;
    final camera = await _map!.getCameraState();
    final atZoom = camera.zoom >= 12.5;
    if (atZoom != _showingLines) setState(() => _showingLines = atZoom);
    await ParcelLayer.onIdle(_map!);
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.deniedForever ||
          permission == geo.LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required')),
          );
        }
        return;
      }
      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (_map != null && mounted) {
        await _map!.flyTo(
          CameraOptions(
            center: Point(coordinates: Position(pos.longitude, pos.latitude)),
            zoom: 15,
          ),
          MapAnimationOptions(duration: 1000),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get current location')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _searchAddress() async {
    final address = _searchCtrl.text.trim();
    if (address.isEmpty) return;
    FocusScope.of(context).unfocus();
    await _runQuery(() => WaterRightsClient.instance.lookupByAddress(address));
  }

  Future<void> _runQuery(
    Future<LookupResult> Function() queryFn, {
    bool isTap = false,
  }) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _searching = true);
    try {
      final result = await queryFn();
      if (!mounted) return;
      if (result.hasError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.errorMessage!)));
      } else {
        // Always fly to the result location
        if (!isTap &&
            result.lat != null &&
            result.lng != null &&
            _map != null) {
          await _map!.flyTo(
            CameraOptions(
              center: Point(coordinates: Position(result.lng!, result.lat!)),
              zoom: 16,
            ),
            MapAnimationOptions(duration: 1200),
          );
        }
        if (mounted) _showNoRightsSheet(result);
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _showStyleSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MapStyleSheet(
        current: _currentStyle,
        onSelected: (style) async {
          Navigator.pop(context);
          if (_map == null || style == _currentStyle) return;
          setState(() => _currentStyle = style);
          await _map!.loadStyleURI(style);
        },
      ),
    );
  }

  void _showNoRightsSheet(LookupResult? result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.25,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Material(
            child: _ParcelInfoSheet(
              result: result,
              scrollController: controller,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
            onMapIdleListener: _onMapIdle,
            viewport: _initialViewport,
          ),
          // Search bar
          Positioned(
            bottom: 80,
            left: 16,
            right: 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Address, coordinates, or parcel number...',
                        prefixIcon: const Icon(Icons.search),
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
                  IconButton(
                    icon: const Icon(Icons.person),
                    onPressed: () => context.push('/profile'),
                  ),
                ],
              ),
            ),
          ),
          // Parcel fetch indicator
          Positioned(
            right: 20,
            bottom: 225,
            child: ValueListenableBuilder<bool>(
              valueListenable: ParcelLayer.isFetching,
              builder: (context, fetching, _) {
                if (!fetching || !_showingLines) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Loading parcel boundaries'),
                        content: const Text(
                          'Parcel boundaries are fetched from the state GIS service, '
                          'which can be slow (up to a minute for Colorado). '
                          'The map will update automatically when the data arrives.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              ParcelLayer.cancelFetch();
                              WaterRightsClient.instance.cancelColoradoLookup();
                              Navigator.pop(ctx);
                            },
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.blue,
                          ),
                        ),
                        const Icon(
                          Icons.info_outline,
                          color: Colors.blue,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Map type button
          Positioned(
            right: 16,
            bottom: 180,
            child: FloatingActionButton.small(
              heroTag: 'maptype',
              onPressed: _showStyleSheet,
              tooltip: 'Map type',
              child: const Icon(Icons.layers_outlined),
            ),
          ),
          // Current location button
          Positioned(
            right: 16,
            bottom: 135,
            child: FloatingActionButton.small(
              heroTag: 'location',
              onPressed: _locating ? null : _goToCurrentLocation,
              tooltip: 'My location',
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
          // Full-screen loading overlay
          if (_searching)
            Container(
              color: Colors.black45,
              child: const Center(child: SearchLoaderCard()),
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

// ── Map style picker ──────────────────────────────────────────────────────────

const _mapStyles = [
  (label: 'Standard', icon: Icons.map_outlined, style: MapboxStyles.STANDARD),
  (
    label: 'Satellite',
    icon: Icons.satellite_alt_outlined,
    style: MapboxStyles.SATELLITE,
  ),
  (
    label: 'Hybrid',
    icon: Icons.satellite_outlined,
    style: MapboxStyles.SATELLITE_STREETS,
  ),
  (
    label: 'Outdoors',
    icon: Icons.terrain_outlined,
    style: MapboxStyles.OUTDOORS,
  ),
  (label: 'Dark', icon: Icons.dark_mode_outlined, style: MapboxStyles.DARK),
];

class _MapStyleSheet extends StatelessWidget {
  final String current;
  final void Function(String) onSelected;
  const _MapStyleSheet({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Map type', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _mapStyles.map((s) {
              final selected = current == s.style;
              return GestureDetector(
                onTap: () => onSelected(s.style),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withAlpha(40)
                            : Colors.grey[850],
                        borderRadius: BorderRadius.circular(12),
                        border: selected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              )
                            : null,
                      ),
                      child: Icon(
                        s.icon,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[400],
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Parcel + water rights sheet ───────────────────────────────────────────────

class _ParcelInfoSheet extends StatelessWidget {
  final LookupResult? result;
  final ScrollController scrollController;
  const _ParcelInfoSheet({this.result, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final info = result?.parcelInfo;
    final rights = result?.rights ?? [];
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomPad),
      children: [
        // Handle bar
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Address header
        if (info?.address != null) ...[
          Text(
            info!.address!,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (info.city != null)
            Text(
              [info.city!, if (info.zip != null) info.zip!].join(' '),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[400]),
            ),
        ] else if (info?.parcelId != null && info!.parcelId.isNotEmpty) ...[
          Text(
            'Parcel ${info.parcelId}',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ] else if (result?.lat != null && result?.lng != null) ...[
          Text(
            '${result!.lat!.toStringAsFixed(5)}, ${result!.lng!.toStringAsFixed(5)}',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            'Parcel data unavailable',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
          ),
        ] else
          Text(
            'Unknown location',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),

        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),

        // Parcel details
        if (info != null) ...[
          _SheetRow('Parcel ID', info.parcelId),
          if (info.county != null)
            _SheetRow('County', '${info.county!} County'),
          if (info.subdivName != null)
            _SheetRow('Subdivision', info.subdivName!),
          if (info.propClass != null) _SheetRow('Type', info.propClass!),
          if (info.acres != null)
            _SheetRow('Lot size', '${info.acres!.toStringAsFixed(2)} acres'),
          if (info.buildingSqft != null)
            _SheetRow('Building', '${_fmt(info.buildingSqft!)} sq ft'),
          if (info.yearBuilt != null)
            _SheetRow('Year built', '${info.yearBuilt!}'),
          if (info.marketValue != null)
            _SheetRow('Market value', '\$${_fmt(info.marketValue!.toInt())}'),
        ],

        if (info?.countyUrl != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.open_in_browser, size: 16),
              label: const Text('View county assessor records'),
              onPressed: () {
                final url = Uri.tryParse(info!.countyUrl!);
                if (url != null) {
                  launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
        ],

        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),

        // Water rights section
        if (rights.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No private water rights found on this parcel. '
                    'The property is likely served by city or municipal culinary water.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          )
        else ...[
          Text(
            '${rights.length} Water Right${rights.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ...rights.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: WaterRightCard(right: r),
            ),
          ),
        ],
      ],
    );
  }

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _SheetRow extends StatelessWidget {
  final String label;
  final String value;
  const _SheetRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
