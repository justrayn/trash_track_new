import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/appointment_model.dart';
import '../providers/appointment_provider.dart';
import '../widgets/appointment/points_weight_summary.dart';
import '../widgets/appointment/location_details_section.dart';
import '../widgets/appointment/material_summary_section.dart';
import '../services/driver_info_section.dart';
import '../services/points_calculation.dart';
import '../widgets/dialogs/cancel_confirmation_dialog.dart';
import '../widgets/appointment/appointment_header_section.dart';
import 'qr_code_screen.dart';

class AppointmentDetailsPage extends ConsumerWidget {
  final Map<String, String?> appointment;

  const AppointmentDetailsPage({super.key, required this.appointment});

  Future<void> _handleCancel(BuildContext context, WidgetRef ref) async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => CancelConfirmationDialog(
        onConfirm: () async {
          try {
            final appointmentRepo = ref.read(appointmentRepositoryProvider);
            final appointmentId = appointment["appointment_info_id"];

            if (appointmentId == null) {
              throw Exception("Appointment ID is missing");
            }

            await appointmentRepo.updateAppointmentStatus(
              appointmentId,
              AppointmentStatus.cancelled,
            );

            ref.invalidate(userAppointmentsProvider);

            if (context.mounted) {
              await Future.delayed(const Duration(milliseconds: 300));

              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close detail page
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error cancelling appointment: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );

    // fallback pop if dialog returned true but was dismissed outside
    if (shouldCancel == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleConfirmation(BuildContext context, WidgetRef ref) async {
    try {
      final appointmentRepo = ref.read(appointmentRepositoryProvider);
      final appointmentId = appointment["appointment_info_id"];

      if (appointmentId == null) {
        throw Exception("Appointment ID is missing");
      }

      await appointmentRepo.updateAppointmentStatus(
        appointmentId,
        AppointmentStatus.confirmed,
      );

      await appointmentRepo.finalizeAppointmentWithQr(appointmentId);

      ref.invalidate(userAppointmentsProvider);

      final updatedAppointment = await appointmentRepo.getAppointment(
        appointmentId,
      );

      if (context.mounted) {
        await Future.delayed(const Duration(milliseconds: 300));

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QrCodeScreen(appointment: updatedAppointment),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error confirming appointment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPickup = appointment["appointment_type"] == "Pick-Up";
    final serviceType = appointment["appointment_type"] ?? "";

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 70), // Spacer to push down below button
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Consumer(
                    builder: (context, ref, _) {
                      final detailsAsync = ref.watch(
                        appointmentDetailsProvider(
                          appointment["appointment_info_id"]!,
                        ),
                      );
                      return detailsAsync.when(
                        data: (details) {
                          final wastes =
                              details['appointment_trash'] as List<dynamic>;
                          final disposalService = details['disposal_service'];

                          final Map<String, Map<String, dynamic>>
                          materialSummary = {};
                          double totalCalculatedWeight = 0.0;
                          double totalCalculatedPoints = 0.0;

                          for (final item in wastes) {
                            final materialType =
                                item['service_materials']?['material_points']?['material_type']
                                    as String?;
                            final weight =
                                (item['weight_kg'] as num?)?.toDouble() ?? 0.0;
                            final pointsPerKg =
                                item['service_materials']?['material_points']?['points_per_kg']
                                    as num? ??
                                0.0;
                            final points = calculateMaterialPoints(
                              weight,
                              pointsPerKg,
                            );

                            if (materialType != null) {
                              materialSummary.update(
                                materialType,
                                (value) => {
                                  'weight':
                                      (value['weight'] as double) + weight,
                                  'points':
                                      (value['points'] as double) + points,
                                },
                                ifAbsent: () => {
                                  'weight': weight,
                                  'points': points,
                                },
                              );
                              totalCalculatedWeight += weight;
                              totalCalculatedPoints += points;
                            }
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppointmentHeaderSection(
                                serviceName:
                                    disposalService?['service_name'] ??
                                    "Unknown Service",
                                serviceType: serviceType,
                                appointmentDate:
                                    appointment["appointment_date"] ?? "N/A",
                                status:
                                    appointment["appointment_status"] ??
                                    "Pending",
                              ),
                              const SizedBox(height: 20),
                              PointsWeightSummary(
                                totalPoints: totalCalculatedPoints,
                                totalWeight: totalCalculatedWeight,
                              ),
                              const SizedBox(height: 20),
                              LocationDetailsSection(
                                address:
                                    appointment["appointment_location"] ??
                                    "N/A",
                                isPickup: isPickup,
                              ),
                              const SizedBox(height: 16),
                              MaterialSummarySection(
                                materialSummary: materialSummary,
                                notes:
                                    appointment["appointment_notes"] ?? "None",
                              ),
                              if (appointment["appointment_type"] ==
                                  "Pick-Up") ...[
                                DriverInfoSection(useMockData: true),
                              ],
                            ],
                          );
                        },
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) =>
                            const Text("Error loading appointment details"),
                      );
                    },
                  ),
                ),
                if (appointment["appointment_status"] == "Pending")
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _handleConfirmation(context, ref),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4B5320),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              "Confirm",
                              style: TextStyle(
                                color: Color(0xFFFEFAE0),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _handleCancel(context, ref),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[400],
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              "Cancel",
                              style: TextStyle(
                                color: Color(0xFFFEFAE0),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ✅ Back Button Positioned
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 8.0),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        spreadRadius: 2,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.black,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
