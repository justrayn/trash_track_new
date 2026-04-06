/// Points calculation utility for trash_track
/// 
/// Handles eco-points calculation with threshold-based bonus multiplier
/// 
/// RULES:
/// - Base points: 1 point per 1kg disposed
/// - Bonus multiplier: 5x (only when disposal weight >= 50kg)
/// - Example: 50kg = 50 base + 250 bonus (5x50) = 300 total

/// Calculate disposal points with progressive bonuses
/// 
/// Returns a tuple of (basePoints, bonusPoints)
/// 
/// Parameters:
///   - disposalWeightKg: Total weight of waste disposed (in kg)
///   - basePointsPerKg: Points awarded per kg (typically 1)
/// 
/// Example:
/// ```dart
/// final (base, bonus) = calculateDisposalPoints(60, 1);
/// // base = 60, bonus = 300 (60 * 5)
/// // total = 360
/// ```
(int basePoints, int bonusPoints) calculateDisposalPoints(
  double disposalWeightKg,
  int basePointsPerKg,
) {
  // Calculate base points (linear)
  final basePoints = (disposalWeightKg * basePointsPerKg).toInt();

  // Calculate bonus: 5x multiplier only if weight >= 50kg
  // This encourages users to participate in larger-scale disposals
  final bonusPoints = disposalWeightKg >= 50 ? basePoints * 5 : 0;

  return (basePoints, bonusPoints);
}

/// Calculate total points from disposal
int calculateTotalPoints(double disposalWeightKg, int basePointsPerKg) {
  final (base, bonus) = calculateDisposalPoints(disposalWeightKg, basePointsPerKg);
  return base + bonus;
}

/// Constants for eco-points system
class EcoPointsConstants {
  /// Minimum weight required to earn bonus multiplier (kg)
  static const double bonusThresholdKg = 50.0;

  /// Bonus multiplier applied to base points when threshold is met
  static const int bonusMultiplier = 5;

  /// Base points awarded per kilogram of waste
  static const int basePointsPerKg = 1;

  /// Maximum points a user can earn in a single disposal
  static const int maxPointsPerDisposal = 10000;
}

/// Extended points calculation with validation
/// 
/// Throws [ArgumentError] if parameters are invalid
int calculateDisposalPointsSafe(double disposalWeightKg) {
  if (disposalWeightKg < 0) {
    throw ArgumentError('Disposal weight cannot be negative');
  }

  if (disposalWeightKg > 1000) {
    throw ArgumentError('Disposal weight exceeds maximum limit (1000kg)');
  }

  final (base, bonus) =
      calculateDisposalPoints(disposalWeightKg, EcoPointsConstants.basePointsPerKg);
  final total = base + bonus;

  // Cap at maximum points
  return total > EcoPointsConstants.maxPointsPerDisposal
      ? EcoPointsConstants.maxPointsPerDisposal
      : total;
}

/// Points breakdown for user display
class PointsBreakdown {
  final double disposalWeightKg;
  final int basePoints;
  final int bonusPoints;
  final int totalPoints;
  final bool qualifiesForBonus;

  PointsBreakdown({
    required this.disposalWeightKg,
    required this.basePoints,
    required this.bonusPoints,
    required this.totalPoints,
    required this.qualifiesForBonus,
  });

  String toReadableString() {
    final weightStr = 'Dispose ${disposalWeightKg.toStringAsFixed(2)} kg';
    final baseStr = '$basePoints base points';
    final bonusStr = qualifiesForBonus
        ? '+${bonusPoints} bonus (${EcoPointsConstants.bonusMultiplier}x multiplier)'
        : 'no bonus (need ≥${EcoPointsConstants.bonusThresholdKg}kg)';
    final totalStr = '= $totalPoints total';

    return '$weightStr\n$baseStr\n$bonusStr\n$totalStr';
  }
}

/// Create a detailed breakdown of points earned
PointsBreakdown getPointsBreakdown(double disposalWeightKg) {
  final (base, bonus) =
      calculateDisposalPoints(disposalWeightKg, EcoPointsConstants.basePointsPerKg);
  final qualifiesForBonus = disposalWeightKg >= EcoPointsConstants.bonusThresholdKg;

  return PointsBreakdown(
    disposalWeightKg: disposalWeightKg,
    basePoints: base,
    bonusPoints: bonus,
    totalPoints: base + bonus,
    qualifiesForBonus: qualifiesForBonus,
  );
}
