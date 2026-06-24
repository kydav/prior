class WaterRight {
  final String rightNumber;
  final String? source;
  final String? sourceType; // Surface, Groundwater
  final String? priorityDate;
  final double? volumeAcreFt;
  final String? beneficialUse; // Irrigation, Culinary, Stockwater, etc.
  final String? status; // Approved, Approved-Unexercised, Lapsed, etc.
  final String? ownerName;
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
    this.beneficialUse,
    this.status,
    this.ownerName,
    this.podLat,
    this.podLng,
    this.divisionOfWaterRightsUrl,
    required this.raw,
  });

  bool get isSenior {
    if (priorityDate == null) return false;
    final year = int.tryParse(priorityDate!.split('-').first) ?? 9999;
    return year < 1935;
  }

  bool get isActive {
    if (status == null) return false;
    final s = status!.toLowerCase();
    return s.contains('approved') && !s.contains('lapsed') && !s.contains('canceled');
  }

  factory WaterRight.fromArcGis(Map<String, dynamic> attrs) {
    String? field(List<String> keys) {
      for (final k in keys) {
        final v = attrs[k];
        if (v != null && v.toString().trim().isNotEmpty && v.toString() != 'null') {
          return v.toString().trim();
        }
      }
      return null;
    }

    final rightNum = field(['WR_SERIAL_NO', 'SERIAL_NO', 'WATER_RIGHT_NO', 'RIGHT_NO']) ?? '';
    final url = rightNum.isNotEmpty
        ? 'https://waterrights.utah.gov/wrinfo/info.asp?wrserial=$rightNum'
        : null;

    return WaterRight(
      rightNumber: rightNum,
      source: field(['SOURCE', 'WATER_SOURCE', 'STREAM_NAME', 'SOURCE_NAME']),
      sourceType: field(['WR_TYPE', 'SOURCE_TYPE', 'TYPE']),
      priorityDate: field(['PRIORITY_DATE', 'PRI_DATE', 'DATE_PRIORITY']),
      volumeAcreFt: double.tryParse(field(['DIVERSION_VOLUME', 'VOLUME', 'ACRE_FEET', 'AF_ANNUAL']) ?? ''),
      beneficialUse: field(['BENEFICIAL_USE', 'USE_TYPE', 'BEN_USE', 'PRIMARY_USE']),
      status: field(['STATUS', 'WR_STATUS', 'RIGHT_STATUS']),
      ownerName: field(['OWNER', 'OWNER_NAME', 'CLAIMANT']),
      podLat: double.tryParse(field(['LAT_DECIMAL', 'LATITUDE', 'LAT']) ?? ''),
      podLng: double.tryParse(field(['LONG_DECIMAL', 'LONGITUDE', 'LNG', 'LON']) ?? ''),
      divisionOfWaterRightsUrl: url,
      raw: attrs,
    );
  }
}
