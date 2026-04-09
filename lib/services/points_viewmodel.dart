import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_points_model.dart';
import 'points_calculation.dart';

class PointsViewModel extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  final Ref ref;

  UserPoints _userPoints = UserPoints(points: 0);
  UserPoints get userPoints => _userPoints;

  bool isLoading = false;

  PointsViewModel(this.ref);

  Future<void> fetchPoints() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final response = await _client
        .from('user_credentials')
        .select('user_info_id')
        .eq('user_cred_id', userId)
        .maybeSingle();

    final userInfoId = response?['user_info_id'];
    if (userInfoId == null) return;

    final data = await _client
        .from('user_info')
        .select('user_points')
        .eq('user_info_id', userInfoId)
        .maybeSingle();

    _userPoints = UserPoints.fromJson(data ?? {});
    notifyListeners();
  }

  Future<bool> redeem(int cost) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final response = await _client
        .from('user_credentials')
        .select('user_info_id')
        .eq('user_cred_id', userId)
        .maybeSingle();

    final userInfoId = response?['user_info_id'];
    if (userInfoId == null || _userPoints.points < cost) return false;

    final newBalance = _userPoints.points - cost;

    await _client
        .from('user_info')
        .update({'user_points': newBalance})
        .eq('user_info_id', userInfoId);

    _userPoints = UserPoints(points: newBalance);
    notifyListeners();
    return true;
  }

  Future<bool> addPointsForAppointment(
    String appointmentId,
    String? qrData,
  ) async {
    try {
      isLoading = true;
      notifyListeners();

      final userId = _client.auth.currentUser?.id;
      if (userId == null || qrData == null) return false;

      // Extract points from QR data using shared parser.
      final pointsEarned = extractPointsFromQrPayload(qrData);

      // Get user_info_id
      final userResponse = await _client
          .from('user_credentials')
          .select('user_info_id')
          .eq('user_cred_id', userId)
          .maybeSingle();

      final userInfoId = userResponse?['user_info_id'];
      if (userInfoId == null) return false;

      // Get current user points
      final userInfoResponse = await _client
          .from('user_info')
          .select('user_points')
          .eq('user_info_id', userInfoId)
          .maybeSingle();

      final currentPoints = (userInfoResponse?['user_points'] ?? 0) as int;
      final newBalance = currentPoints + pointsEarned;

      // Update user points
      await _client
          .from('user_info')
          .update({'user_points': newBalance})
          .eq('user_info_id', userInfoId);

      _userPoints = UserPoints(points: newBalance);
      notifyListeners();
      return true;
    } on FormatException {
      return false;
    } catch (e) {
      debugPrint('Error adding points: $e');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
