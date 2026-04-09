import 'dart:developer' as dev;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/appointment_model.dart';
import '../models/appointment_waste.dart';
import '../services/points_calculation.dart';

class AppointmentException implements Exception {
  final String message;
  final dynamic originalError;

  AppointmentException(this.message, [this.originalError]);

  @override
  String toString() =>
      'AppointmentException: $message${originalError != null ? '\nOriginal error: $originalError' : ''}';
}

class AppointmentRepository {
  final SupabaseClient _client;

  AppointmentRepository(this._client);

  /// Create appointment with appointment model and associated waste materials
  Future<Appointment> createAppointment(
    Appointment appointment,
    List<AppointmentWaste> wasteMaterials,
  ) async {
    dev.log('Creating appointment...', name: 'AppointmentRepository');
    dev.log(
      'Appointment data: ${appointment.toString()}',
      name: 'AppointmentRepository',
    );
    dev.log(
      'Waste materials: ${wasteMaterials.map((w) => w.toString()).join(', ')}',
      name: 'AppointmentRepository',
    );

    try {
      // Verify current user is authenticated
      final currentUser = _client.auth.currentUser;
      if (currentUser == null) {
        throw AppointmentException(
          'User must be authenticated to create an appointment',
        );
      }

      // Get the combined date and time for the appointment
      final DateTime combinedDateTime = await _getAppointmentDateTime(
        appointment,
      );

      // Calculate total points and weight for QR code
      double totalPoints = 0.0;
      double totalWeight = 0.0;

      // Calculate points and weight from waste materials
      for (final waste in wasteMaterials) {
        final weight = waste.weightKg ?? 0.0;
        totalWeight += weight;

        // Get points per kg for this material
        final materialPointsResult = await _client
            .from('service_materials')
            .select('material_points (points_per_kg)')
            .eq('service_materials_id', waste.serviceMaterialId ?? '')
            .single();

        final pointsPerKg =
            (materialPointsResult['material_points']?['points_per_kg'] ?? 0)
                as num;
        totalPoints += calculateMaterialPoints(weight, pointsPerKg);
      }

      // Validate appointment belongs to current user by checking user_info_id
      final userInfoResult = await _client
          .from('user_info')
          .select('user_info_id')
          .eq('auth_user_id', currentUser.id)
          .single();

      if (userInfoResult['user_info_id'] != appointment.userInfoId) {
        throw AppointmentException(
          'Appointment user_info_id does not match authenticated user',
        );
      }

      // Validate input data
      if (appointment.userInfoId.isEmpty) {
        throw AppointmentException('User ID is required');
      }
      if (appointment.serviceId.isEmpty) {
        throw AppointmentException('Service ID is required');
      }
      if (wasteMaterials.isEmpty) {
        throw AppointmentException('At least one waste material is required');
      }
      // Insert into appointment_info
      // Convert appointment status to match database enum
      String getAppointmentStatus(AppointmentStatus status) {
        switch (status) {
          case AppointmentStatus.pending:
            return 'Pending';
          case AppointmentStatus.confirmed:
            return 'Confirmed';
          case AppointmentStatus.cancelled:
            return 'Cancelled';
          case AppointmentStatus.completed:
            return 'Completed';
        }
      }

      final appointmentInfo = {
        'user_info_id': appointment.userInfoId,
        'service_id': appointment.serviceId,
        'appointment_type':
            appointment.appointmentType == AppointmentType.pickUp
            ? 'Pick-Up'
            : 'Drop-Off',
        'avail_sched_id': appointment.availSchedId,
        'appointment_date': combinedDateTime
            .toIso8601String(), // Use combined date time
        'appointment_create_date':
            (appointment.appointmentCreateDate ?? DateTime.now())
                .toIso8601String(),
        'appointment_location': appointment.appointmentLocation,
        'appointment_status': getAppointmentStatus(
          appointment.appointmentStatus,
        ),
        'appointment_notes': appointment.appointmentNotes,
        'appointment_price_fee': appointment.appointmentPriceFee,
      };

      final inserted = await _client
          .from('appointment_info')
          .insert(appointmentInfo)
          .select('appointment_info_id') // safer than default
          .maybeSingle(); // prevents crashing if nothing is returned

      if (inserted == null || inserted['appointment_info_id'] == null) {
        throw Exception('Insert failed: No appointment_info_id returned.');
      }

      final newAppointmentId = inserted['appointment_info_id'] as String;

      // Update QR code with actual appointment ID
      final finalQrText =
          'ID:$newAppointmentId|Points:$totalPoints|Weight:$totalWeight';
      await _client
          .from('appointment_info')
          .update({'appointment_qr_code': finalQrText})
          .eq('appointment_info_id', newAppointmentId);

      // Insert waste materials
      if (wasteMaterials.isNotEmpty) {
        for (final w in wasteMaterials) {
          await _client.from('appointment_trash').insert({
            'appointment_info_id': newAppointmentId,
            'service_materials_id': w.serviceMaterialId,
            'weight_kg': w.weightKg,
          });
        }
      }

      return await getAppointment(newAppointmentId);
    } catch (e) {
      dev.log(
        'Error creating appointment: $e',
        name: 'AppointmentRepository',
        error: e,
      );
      if (e is AppointmentException) rethrow;
      throw AppointmentException('Failed to create appointment', e);
    }
  }

  /// Fetches a full appointment by ID with associated trash
  Future<Appointment> getAppointment(String appointmentId) async {
    try {
      final response = await _client
          .from('appointment_info')
          .select('''
            *,
            appointment_trash (
              *,
              service_materials (
                material_points (*)
              )
            )
          ''')
          .eq('appointment_info_id', appointmentId)
          .single();

      return Appointment.fromMap(response);
    } catch (e) {
      throw Exception('Failed to get appointment: $e');
    }
  }

  /// Used after appointment creation to calculate total points and generate QR code
  Future<void> finalizeAppointmentWithQr(String appointmentId) async {
    dev.log(
      'Finalizing appointment with QR code...',
      name: 'AppointmentRepository',
    );
    dev.log('Appointment ID: $appointmentId', name: 'AppointmentRepository');

    try {
      if (appointmentId.isEmpty) {
        throw AppointmentException(
          'Appointment ID is required for finalization',
        );
      }
      final response = await _client
          .from('appointment_info')
          .select('''
          appointment_info_id,
          appointment_trash (
            weight_kg,
            service_materials (
              material_points (
                points_per_kg
              )
            )
          )
        ''')
          .eq('appointment_info_id', appointmentId)
          .single();

      double totalPoints = 0.0;
      double totalWeight = 0.0;

      final trashItems = response['appointment_trash'] as List;
      for (final item in trashItems) {
        final weight = (item['weight_kg'] as num).toDouble();
        final pointsPerKg =
            (item['service_materials']?['material_points']?['points_per_kg'] ??
                    0)
                as num;
        totalPoints += calculateMaterialPoints(weight, pointsPerKg);
        totalWeight += weight;
      }

      final qrText =
          'ID:$appointmentId|Points:$totalPoints|Weight:$totalWeight';

      // Update the appointment with QR code and points
      await _client
          .from('appointment_info')
          .update({'appointment_qr_code': qrText})
          .eq('appointment_info_id', appointmentId);

      dev.log(
        'QR code and points updated successfully',
        name: 'AppointmentRepository',
      );
    } catch (e) {
      dev.log(
        'Error finalizing appointment: $e',
        name: 'AppointmentRepository',
        error: e,
      );
      throw AppointmentException('Failed to finalize appointment with QR', e);
    }
  }

  /// Fetch appointments for the current user
  Future<List<Appointment>> getUserAppointments() async {
    dev.log('Fetching user appointments...', name: 'AppointmentRepository');

    try {
      final currentUser = _client.auth.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      dev.log('Current user: ${currentUser.id}', name: 'AppointmentRepository');

      // Step 1: Get user_info.id by matching user_info.user_id = auth.uid
      final userInfoResponse = await _client
          .from('user_info')
          .select('user_info_id')
          .eq('auth_user_id', currentUser.id)
          .maybeSingle();

      final userInfoId = userInfoResponse?['user_info_id'] as String?;
      if (userInfoId == null) {
        throw Exception('No user_info entry found for this user');
      }

      // Step 2: Get appointments using user_info_id
      final response = await _client
          .from('appointment_info')
          .select('''
          *,
          appointment_trash (
            *,
            service_materials (
              material_points (*)
            )
          )
        ''')
          .eq('user_info_id', userInfoId)
          .order('appointment_date', ascending: true);

      dev.log(
        'Fetched ${response.length} appointments',
        name: 'AppointmentRepository',
      );

      return (response as List)
          .map((data) => Appointment.fromMap(data))
          .toList();
    } catch (e, stack) {
      dev.log(
        'Error fetching appointments: $e',
        name: 'AppointmentRepository',
        error: e,
        stackTrace: stack,
      );
      throw AppointmentException('Failed to fetch user appointments', e);
    }
  }

  /// Update appointment status
  Future<void> updateAppointmentStatus(
    String appointmentId,
    AppointmentStatus status,
  ) async {
    try {
      await _client
          .from('appointment_info')
          .update({
            'appointment_status': status.toSupabaseString(),
            if (status == AppointmentStatus.confirmed)
              'appointment_confirm_date': DateTime.now().toIso8601String(),
            if (status == AppointmentStatus.cancelled)
              'appointment_cancel_date': DateTime.now().toIso8601String(),
          })
          .eq('appointment_info_id', appointmentId);
    } catch (e) {
      throw Exception('Failed to update appointment status: $e');
    }
  }

  /// Fetches complete appointment details including all related data
  Future<Map<String, dynamic>> getCompleteAppointmentDetails(
    String appointmentId,
  ) async {
    dev.log(
      'Fetching complete appointment details...',
      name: 'AppointmentRepository',
    );
    dev.log('Appointment ID: $appointmentId', name: 'AppointmentRepository');

    try {
      if (appointmentId.isEmpty) {
        throw AppointmentException('Appointment ID is required');
      }

      final response = await _client
          .from('appointment_info')
          .select('''
            *,
            disposal_service (
              service_id,
              service_name
            ),
            appointment_trash (
              weight_kg,
              service_materials (
                service_materials_id,
                disposal_service_id,
                material_points_id,
                material_points (
                  material_type,
                  points_per_kg
                )
              )
            )
          ''')
          .eq('appointment_info_id', appointmentId)
          .single();

      dev.log('Fetched response: $response', name: 'AppointmentRepository');

      if (response['disposal_service'] == null) {
        dev.log(
          'Warning: No disposal service found for appointment',
          name: 'AppointmentRepository',
        );
      }

      if ((response['appointment_trash'] as List).isEmpty) {
        dev.log(
          'Warning: No trash items found for appointment',
          name: 'AppointmentRepository',
        );
      }

      return response;
    } catch (e) {
      dev.log(
        'Error fetching complete appointment details: $e',
        name: 'AppointmentRepository',
        error: e,
      );
      throw AppointmentException(
        'Failed to fetch complete appointment details',
        e,
      );
    }
  }

  Future<DateTime> _getAppointmentDateTime(Appointment appointment) async {
    if (appointment.appointmentType == AppointmentType.pickUp) {
      final scheduleResult = await _client
          .from('available_schedules')
          .select()
          .eq('avail_sched_id', appointment.availSchedId!)
          .single();

      final availDate = DateTime.parse(scheduleResult['avail_date'] as String);
      final availStartTime = scheduleResult['avail_start_time'] as String;

      // Parse time in 24-hour format (HH:mm)
      final timeComponents = availStartTime.split(':');
      final hour = int.parse(timeComponents[0]);
      final minute = int.parse(timeComponents[1]);

      return DateTime(
        availDate.year,
        availDate.month,
        availDate.day,
        hour,
        minute,
      );
    }
    // For drop-off appointments, use the selected appointment date
    return appointment.appointmentDate;
  }

  String getAppointmentStatus(AppointmentStatus? status) {
    switch (status) {
      case AppointmentStatus.pending:
        return 'Pending';
      case AppointmentStatus.confirmed:
        return 'Confirmed';
      case AppointmentStatus.completed:
        return 'Completed';
      case AppointmentStatus.cancelled:
        return 'Cancelled';
      case null:
        return 'Pending'; // Default to pending if not specified
    }
  }

  Future<String?> fetchAppointmentStatus(String appointmentId) async {
    try {
      final result = await _client
          .from('appointment_info')
          .select('status')
          .eq('appointment_info_id', appointmentId)
          .maybeSingle();

      return result?['status'];
    } catch (e) {
      print('Error fetching status: $e');
      return null;
    }
  }
}
