import 'package:flutter_test/flutter_test.dart';
import 'package:trash_track/services/points_calculation.dart';

void main() {
  group('calculateMaterialPoints', () {
    test('returns expected points for valid weight and rate', () {
      final result = calculateMaterialPoints(2.5, 4);

      expect(result, 10);
    });

    test('throws for negative weight', () {
      expect(
        () => calculateMaterialPoints(-1, 4),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws for negative points per kg', () {
      expect(
        () => calculateMaterialPoints(1, -4),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('extractPointsFromQrPayload', () {
    test('extracts and rounds point values from payload', () {
      final points = extractPointsFromQrPayload(
        'ID:abc|Points:12.6|Weight:5.2',
      );

      expect(points, 13);
    });

    test('throws format exception when points segment is missing', () {
      expect(
        () => extractPointsFromQrPayload('ID:abc|Weight:5.2'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('exposes centralized schedule confirmation bonus constant', () {
    expect(EcoPointsConstants.scheduleConfirmationBonusPoints, 5);
  });
}
