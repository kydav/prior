import 'package:prior/core/states/idaho_source.dart';
import 'package:prior/data/water_right.dart';

/// One state's water-rights data, as a plug-in (docs/ROADMAP.md, Phase 1).
/// A new state is one of these plus an entry in [kStateSources]; the
/// lookup, detail screen and saved lookups work unchanged.
///
/// Utah and Colorado predate this and still live in WaterRightsClient;
/// they move over as each is next touched.
abstract class StateSource {
  const StateSource();

  /// Two-letter code, e.g. 'ID'.
  String get code;
  String get name;

  /// Whether a point is in this state.
  bool contains(double lat, double lng);

  /// Water rights whose point of diversion is near the point.
  Future<List<WaterRight>> waterRightsNear(double lat, double lng);

  /// Where to look a right up by hand on the state's own site.
  String get officialSearchUrl;

  /// What this state's results can and can't tell you, shown with them.
  String? get coverageNote => null;
}

/// States served through [StateSource], checked before Utah and Colorado.
const List<StateSource> kStateSources = [IdahoSource()];

StateSource? stateSourceAt(double lat, double lng) {
  for (final s in kStateSources) {
    if (s.contains(lat, lng)) return s;
  }
  return null;
}
