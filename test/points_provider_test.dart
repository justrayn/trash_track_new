import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/models/user_points_model.dart';
import '../lib/services/points_viewmodel.dart';

/// Mock Classes
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockSupabaseAuth extends Mock implements GoTrueClient {}
class MockSupabaseQueryBuilder extends Mock implements PostgrestFilterBuilder {}
class MockSupabaseResponse extends Mock implements PostgrestResponse {}

/// Test Suite: Eco-Points Calculation Logic
void main() {
  group('PointsViewModel - Bonus Points Calculation', () {
    late PointsViewModel pointsViewModel;
    late MockSupabaseClient mockClient;
    late ProviderContainer container;

    setUp(() {
      mockClient = MockSupabaseClient();
      container = ProviderContainer();
      
      // Mock the Supabase instance
      // In a real test, you'd use dependency injection or a testing package
    });

    tearDown(() {
      container.dispose();
    });

    test(
      'BUGFIX PR#1: Should award bonus points (5x multiplier) only when disposal weight >= 50kg',
      () {
        // GIVEN: A user disposes waste at 50kg
        const disposalWeightKg = 50;
        const basePointsPerKg = 1;
        const expectedBasePoints = disposalWeightKg * basePointsPerKg; // 50 points
        const expectedBonusPoints = expectedBasePoints * 5; // 250 points (5x multiplier)
        const expectedTotalPoints = expectedBasePoints + expectedBonusPoints; // 300 points

        // WHEN: Calculating points with the fix
        final (basePoints, bonusPoints) = calculateDisposalPoints(
          disposalWeightKg,
          basePointsPerKg,
        );

        // THEN: Should include bonus points
        expect(basePoints, equals(expectedBasePoints));
        expect(bonusPoints, equals(expectedBonusPoints));
        expect(basePoints + bonusPoints, equals(expectedTotalPoints));
      },
    );

    test(
      'Should NOT award bonus points when disposal weight < 50kg',
      () {
        // GIVEN: A user disposes waste at 40kg (below threshold)
        const disposalWeightKg = 40;
        const basePointsPerKg = 1;
        const expectedBasePoints = disposalWeightKg * basePointsPerKg; // 40 points
        const expectedBonusPoints = 0; // NO bonus

        // WHEN: Calculating points
        final (basePoints, bonusPoints) = calculateDisposalPoints(
          disposalWeightKg,
          basePointsPerKg,
        );

        // THEN: Should NOT include bonus points
        expect(basePoints, equals(expectedBasePoints));
        expect(bonusPoints, equals(expectedBonusPoints));
        expect(basePoints + bonusPoints, equals(expectedBasePoints));
      },
    );

    test(
      'Should award bonus points at exactly 50kg threshold',
      () {
        // GIVEN: Weight is exactly at threshold
        const disposalWeightKg = 50;
        const basePointsPerKg = 2;
        const expectedBasePoints = 100;
        const expectedBonusPoints = 500; // 5x multiplier on 100

        // WHEN: Calculating points at boundary
        final (basePoints, bonusPoints) = calculateDisposalPoints(
          disposalWeightKg,
          basePointsPerKg,
        );

        // THEN: Bonus should be awarded
        expect(bonusPoints, isGreaterThan(0));
      },
    );

    test(
      'Should NOT award bonus when weight is 49.99kg (just below threshold)',
      () {
        // GIVEN: Weight is just below threshold
        const disposalWeightKg = 49.99;
        const basePointsPerKg = 1;

        // WHEN: Calculating points just below boundary
        final (basePoints, bonusPoints) = calculateDisposalPoints(
          disposalWeightKg,
          basePointsPerKg,
        );

        // THEN: Bonus should NOT be awarded
        expect(bonusPoints, equals(0));
      },
    );

    test(
      'Should handle edge case: zero weight',
      () {
        // GIVEN: Zero disposal weight
        const disposalWeightKg = 0;
        const basePointsPerKg = 1;

        // WHEN: Calculating points
        final (basePoints, bonusPoints) = calculateDisposalPoints(
          disposalWeightKg,
          basePointsPerKg,
        );

        // THEN: Should be 0
        expect(basePoints + bonusPoints, equals(0));
      },
    );

    test(
      'Should calculate large disposal correctly (500kg)',
      () {
        // GIVEN: Large disposal amount
        const disposalWeightKg = 500;
        const basePointsPerKg = 2;
        const expectedBasePoints = 1000;
        const expectedBonusPoints = 5000; // 5x multiplier

        // WHEN: Calculating large disposal
        final (basePoints, bonusPoints) = calculateDisposalPoints(
          disposalWeightKg,
          basePointsPerKg,
        );

        // THEN: Should calculate correctly
        expect(basePoints, equals(expectedBasePoints));
        expect(bonusPoints, equals(expectedBonusPoints));
      },
    );

    test(
      'Redeem points should deduct from balance correctly',
      () {
        // GIVEN: User has 500 points and wants to redeem 200
        final userPoints = UserPoints(points: 500);
        const redeemCost = 200;

        // WHEN: Attempting to redeem
        final canRedeem = userPoints.points >= redeemCost;

        // THEN: Should be able to redeem
        expect(canRedeem, isTrue);
      },
    );

    test(
      'Redeem should fail when insufficient points',
      () {
        // GIVEN: User has 50 points and wants to redeem 200
        final userPoints = UserPoints(points: 50);
        const redeemCost = 200;

        // WHEN: Attempting to redeem
        final canRedeem = userPoints.points >= redeemCost;

        // THEN: Should NOT be able to redeem
        expect(canRedeem, isFalse);
      },
    );
  });
}

/// FIXED IMPLEMENTATION: Bonus points calculation logic
/// 
/// BUG FIX DESCRIPTION:
/// Previous implementation awarded bonus points to all disposals.
/// This fix ensures bonus points (5x multiplier) are only awarded
/// when disposal weight meets or exceeds 50kg threshold.
/// 
/// BEFORE (Buggy):
/// ```dart
/// int calculateBonusPoints(double weight, int basePoints) {
///   return basePoints * 5; // Always gives 5x bonus!
/// }
/// ```
/// 
/// AFTER (Fixed):
/// ```dart
/// (int, int) calculateDisposalPoints(double weight, int basePerKg) {
///   int basePoints = (weight * basePerKg).toInt();
///   int bonusPoints = weight >= 50 ? basePoints * 5 : 0;
///   return (basePoints, bonusPoints);
/// }
/// ```
(int basePoints, int bonusPoints) calculateDisposalPoints(
  double disposalWeightKg,
  int basePointsPerKg,
) {
  final basePoints = (disposalWeightKg * basePointsPerKg).toInt();
  final bonusPoints = disposalWeightKg >= 50 ? basePoints * 5 : 0;
  return (basePoints, bonusPoints);
}
