extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

class ChangeApplication {
  final String appNumber;
  final String filedDate;
  final String status;

  const ChangeApplication({
    required this.appNumber,
    required this.filedDate,
    required this.status,
  });

  bool get isPending => status.toLowerCase() == 'unapproved';
}

// Field reference for Utah_Points_of_Diversion (services.arcgis.com/ZzrwjTRez6FJiOq4):
// WRNUM, OWNER, SOURCE, TYPE (Surface/Underground), PRIORITY (YYYYMMDD int),
// STATUS (Approved/Perfected/Unapproved/Lapsed/Expired/etc),
// TYPE_OF_RIGHT, ACFT, CFS, USES (codes: I=Irrigation D=Domestic S=Stock O=Other),
// LOCATION (PLSS description), WIN (well ID), WebLink (DWRi search URL)

class WaterRight {
  final String rightNumber;
  final String? source;
  final String? sourceType; // Surface, Underground
  final String? priorityDate; // formatted display string
  final double? volumeAcreFt;
  final double? cfs;
  final String? beneficialUse; // expanded from use codes
  final String? status;
  final String? ownerName;
  final String? plssLocation;
  final double? podLat;
  final double? podLng;
  final String? divisionOfWaterRightsUrl;
  final Map<String, dynamic> raw;

  const WaterRight({
    required this.rightNumber,
    this.source,
    this.sourceType,
    this.priorityDate,
    this.volumeAcreFt,
    this.cfs,
    this.beneficialUse,
    this.status,
    this.ownerName,
    this.plssLocation,
    this.podLat,
    this.podLng,
    this.divisionOfWaterRightsUrl,
    required this.raw,
  });

  // PRIORITY is stored as an int YYYYMMDD (e.g. 20170327)
  bool get isSenior {
    if (priorityDate == null) return false;
    final year = int.tryParse(priorityDate!.substring(0, 4)) ?? 9999;
    return year < 1935;
  }

  bool get isActive {
    if (status == null) return false;
    final s = status!.toLowerCase();
    return (s == 'approved' || s == 'perfected' || s == 'certificated') &&
        !s.contains('lapsed') &&
        !s.contains('expired') &&
        !s.contains('disallowed') &&
        !s.contains('forfeited');
  }

  factory WaterRight.fromArcGis(Map<String, dynamic> attrs) {
    String? f(List<String> keys) {
      for (final k in keys) {
        final v = attrs[k];
        if (v != null && v.toString().trim().isNotEmpty && v.toString() != 'null' && v.toString() != '0') {
          return v.toString().trim();
        }
      }
      return null;
    }

    final rightNum = f(['WRNUM', 'WR_SERIAL_NO', 'SERIAL_NO']) ?? '';

    // WebLink field comes directly from the service — use it, fall back to search URL
    final webLink = f(['WebLink', 'WEBLINK', 'WEB_LINK']) ??
        (rightNum.isNotEmpty
            ? 'https://www.waterrights.utah.gov/search/?q=${Uri.encodeComponent(rightNum)}'
            : null);

    // PRIORITY is YYYYMMDD int — format for display
    final rawPriority = f(['PRIORITY']);
    String? priorityDisplay;
    if (rawPriority != null && rawPriority.length == 8) {
      final y = rawPriority.substring(0, 4);
      final m = rawPriority.substring(4, 6);
      final d = rawPriority.substring(6, 8);
      priorityDisplay = '$m/$d/$y';
    } else {
      priorityDisplay = rawPriority;
    }

    // Expand USES codes to readable string
    final usesCodes = f(['USES']) ?? '';
    final uses = _expandUseCodes(usesCodes);

    return WaterRight(
      rightNumber: rightNum,
      source: f(['SOURCE', 'WATER_SOURCE', 'SOURCE_NAME']),
      sourceType: f(['TYPE', 'WR_TYPE', 'SOURCE_TYPE']),
      priorityDate: priorityDisplay,
      volumeAcreFt: double.tryParse(f(['ACFT', 'ACRE_FEET', 'AF_ANNUAL', 'DIVERSION_VOLUME']) ?? ''),
      cfs: double.tryParse(f(['CFS', 'FLOW_CFS']) ?? ''),
      beneficialUse: uses.isNotEmpty ? uses : f(['BENEFICIAL_USE', 'USE_TYPE', 'BEN_USE']),
      status: f(['STATUS', 'SUMMARY_ST', 'WR_STATUS']),
      ownerName: f(['OWNER', 'OWNER_NAME', 'CLAIMANT']),
      plssLocation: f(['LOCATION']),
      podLat: (attrs['LAT'] as num?)?.toDouble(),
      podLng: (attrs['LNG'] as num?)?.toDouble(),
      divisionOfWaterRightsUrl: webLink,
      raw: attrs,
    );
  }

  // Colorado CDSS structures endpoint
  factory WaterRight.fromCdss(Map<String, dynamic> attrs) {
    String? f(String key) {
      final v = attrs[key];
      if (v == null || v.toString().trim().isEmpty || v.toString() == 'null') return null;
      return v.toString().trim();
    }

    final wdid = f('wdid') ?? '';
    final structureType = f('structureType') ?? '';
    final sourceType = structureType == 'WELL' ? 'Underground' : 'Surface';

    // ciuCode: A=Active, H=Historical, C=Conditionally Active, U=Unknown
    final ciuCode = f('ciuCode') ?? '';
    final status = switch (ciuCode) {
      'A' => 'Active',
      'H' => 'Historical',
      'C' => 'Conditional',
      'U' => 'Unknown',
      _ => ciuCode.isNotEmpty ? ciuCode : null,
    };

    final lat = (attrs['latdecdeg'] as num?)?.toDouble();
    final lng = (attrs['longdecdeg'] as num?)?.toDouble();

    return WaterRight(
      rightNumber: wdid,
      source: f('waterSource'),
      sourceType: sourceType,
      priorityDate: null, // requires separate waterrights/netamount call
      volumeAcreFt: null,
      cfs: null,
      beneficialUse: null,
      status: status,
      ownerName: null,
      plssLocation: [
        if (f('pm') != null) f('pm'),
        if (f('township') != null && f('range') != null)
          'T${f('township')} R${f('range')}',
        if (f('section') != null) 'Sec. ${f('section')}',
      ].join(', ').nullIfEmpty,
      podLat: lat,
      podLng: lng,
      divisionOfWaterRightsUrl: wdid.isNotEmpty
          ? 'https://dwr.state.co.us/Tools/Structures/$wdid'
          : null,
      raw: attrs,
    );
  }

  static String _expandUseCodes(String codes) {
    const map = {
      'I': 'Irrigation',
      'D': 'Domestic',
      'S': 'Stock',
      'M': 'Municipal',
      'P': 'Power',
      'O': 'Other',
      'X': 'Exchange',
      'F': 'Fish/Wildlife',
      'G': 'Geothermal',
      'R': 'Recreation',
    };
    return codes.split('').map((c) => map[c] ?? c).join(', ');
  }
}
