import 'package:flutter_test/flutter_test.dart';
import 'package:prior/core/states/idaho_source.dart';
import 'package:prior/core/states/state_outlines.dart';
import 'package:prior/core/states/state_source.dart';
import 'package:prior/data/water_right.dart';

void main() {
  group('state outlines', () {
    test('Idaho contains Idaho towns and not its neighbours', () {
      expect(inState('ID', 43.615, -116.202), isTrue); // Boise
      expect(inState('ID', 42.563, -114.461), isTrue); // Twin Falls
      expect(inState('ID', 47.677, -116.780), isTrue); // Coeur d'Alene
      expect(inState('ID', 46.872, -113.994), isFalse); // Missoula, MT
      expect(inState('ID', 40.761, -111.891), isFalse); // Salt Lake City
      expect(inState('ID', 47.659, -117.426), isFalse); // Spokane, WA
    });

    test('the plug-in registry picks Idaho only inside Idaho', () {
      expect(stateSourceAt(43.615, -116.202)?.code, 'ID');
      expect(stateSourceAt(41.735, -111.834), isNull); // Logan, UT
      expect(stateSourceAt(39.739, -104.990), isNull); // Denver
    });
  });

  test('an IDWR point of diversion becomes a WaterRight', () {
    final r = IdahoSource.fromIdwr({
      'attributes': {
        'WaterRightNumber': '47-13114  ',
        'Status': 'Active',
        'Basis': 'Decreed',
        'PriorityDate': -536432400000, // 1953
        'Owner': 'SMITH, JANE',
        'OverallMaxDiversionRate': 0.04,
        'Source': 'GROUND WATER',
        'Uses': 'DOMESTIC, IRRIGATION',
        'WRReport': 'https://research.idwr.idaho.gov/report?basin=47',
      },
      'geometry': {'x': -114.45, 'y': 42.56},
    });
    expect(r.rightNumber, '47-13114');
    expect(r.sourceType, 'Underground');
    expect(r.status, 'Active · Decreed');
    expect(r.isActive, isTrue);
    expect(r.priorityDate, endsWith('1953'));
    expect(r.isSenior, isFalse);
    expect(r.beneficialUse, 'Domestic, Irrigation');
    expect(r.podLat, 42.56);
  });

  group('WaterRight status', () {
    WaterRight right({String? status, String? priority}) => WaterRight(
      rightNumber: '1',
      raw: const {},
      status: status,
      priorityDate: priority,
    );

    test('senior reads the year from MM/DD/YYYY', () {
      expect(right(priority: '06/01/1902').isSenior, isTrue);
      expect(right(priority: '06/01/1980').isSenior, isFalse);
      expect(right().isSenior, isFalse);
    });

    test('active across states', () {
      expect(right(status: 'Perfected').isActive, isTrue);
      expect(right(status: 'Active').isActive, isTrue); // Colorado
      expect(right(status: 'Active · Decreed').isActive, isTrue); // Idaho
      expect(right(status: 'Unapproved').isActive, isFalse);
      expect(right(status: 'Lapsed').isActive, isFalse);
      expect(right(status: 'Historical').isActive, isFalse);
    });
  });
}
