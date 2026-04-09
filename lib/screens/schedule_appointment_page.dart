import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/appointment_model.dart';
import '../models/appointment_waste.dart';
import '../models/available_schedule.dart';
import '../models/disposal_service.dart';
import '../providers/appointment_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/schedule/service_type_selector.dart';
import '../widgets/dialogs/success_dialog.dart';
import '../widgets/schedule/waste_material_selection.dart';
import '../widgets/schedule/pickup_details_widget.dart';
import '../widgets/schedule/dropoff_schedule_widget.dart';
import '../widgets/schedule/additional_notes_field.dart';
import '../widgets/schedule/waste_summary_widget.dart';
import '../widgets/schedule/bottom_summary_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/points_calculation.dart';

class ScheduleAppointmentPage extends ConsumerStatefulWidget {
  final DisposalService service;

  const ScheduleAppointmentPage({super.key, required this.service});

  @override
  ConsumerState<ScheduleAppointmentPage> createState() =>
      _ScheduleAppointmentPageState();
}

class _ScheduleAppointmentPageState
    extends ConsumerState<ScheduleAppointmentPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  AppointmentType? selectedType;
  DateTime selectedDate = DateTime.now().add(
    const Duration(days: 1),
  ); // Start with tomorrow's date
  AvailableSchedule? selectedSchedule;
  List<AppointmentWaste> wasteMaterials = [];
  String? userLocation;
  final TextEditingController _notesController = TextEditingController();
  bool isLoading = false;
  String? error;

  // Track used material categories
  Set<String> usedMaterialTypes = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.service.serviceAvailability.contains('Pick-Up')) {
        _selectType(AppointmentType.pickUp);
      } else if (widget.service.serviceAvailability.contains('Drop-Off')) {
        _selectType(AppointmentType.dropOff);
      }
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _addMaterial() {
    if (widget.service.serviceMaterials.isEmpty) return;
    if (wasteMaterials.length >= 5) return; // Limit to 5 entries

    setState(() {
      wasteMaterials.add(
        AppointmentWaste(
          appointmentWasteId: '',
          appointmentInfoId: '',
          weightKg: 1.0,
          serviceMaterialId:
              widget.service.serviceMaterials.first.serviceMaterialsId,
        ),
      );
    });
  }

  void _removeMaterial(int index) {
    setState(() {
      wasteMaterials.removeAt(index);
    });
  }

  void _updateMaterialWeight(int index, double weight) {
    if (weight <= 0) return;
    setState(() {
      wasteMaterials[index] = AppointmentWaste(
        appointmentWasteId: wasteMaterials[index].appointmentWasteId,
        appointmentInfoId: wasteMaterials[index].appointmentInfoId,
        weightKg: weight,
        serviceMaterialId: wasteMaterials[index].serviceMaterialId,
      );
    });
  }

  void _selectType(AppointmentType type) {
    // Verify service availability
    final isPickupAvailable = widget.service.serviceAvailability.contains(
      'Pick-Up',
    );
    final isDropoffAvailable = widget.service.serviceAvailability.contains(
      'Drop-Off',
    );

    // Only allow selection if the service type is available
    if ((type == AppointmentType.pickUp && isPickupAvailable) ||
        (type == AppointmentType.dropOff && isDropoffAvailable)) {
      setState(() {
        selectedType = type;
        // Reset schedule selection
        selectedSchedule = null;
        // Reset location for drop-off
        if (type == AppointmentType.dropOff) {
          userLocation = widget.service.serviceLocation;
        } else {
          userLocation = null;
        }
      });
    }
  }

  void _clearForm() {
    setState(() {
      // Only clear user input data
      selectedSchedule = null;
      wasteMaterials.clear();
      if (selectedType == AppointmentType.pickUp) {
        userLocation = null;
      }
      _notesController.clear();
      error = null;
    });
  }

  Future<void> _scheduleAppointment() async {
    if (!mounted) return;
    print('🚀 Starting appointment scheduling...');

    final userInfo = await ref.read(userProvider.future);
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null || userInfo == null) {
      setState(() => error = 'Please sign in to schedule an appointment');
      return;
    }

    // 🔎 Validation
    if (selectedType == null) {
      setState(() => error = 'Please select a service type');
      return;
    }
    if (wasteMaterials.isEmpty) {
      setState(() => error = 'Please add at least one waste material');
      return;
    }
    if (selectedType == AppointmentType.pickUp) {
      if (selectedSchedule == null) {
        setState(() => error = 'Please select a schedule');
        return;
      }
      if (userLocation == null || userLocation!.isEmpty) {
        setState(() => error = 'Please provide a pickup location');
        return;
      }
    }

    setState(() {
      isLoading = true;
      error = null;
    });

    // ✅ Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final wastes = wasteMaterials.map((waste) {
        return AppointmentWaste(
          appointmentInfoId: '',
          serviceMaterialId: waste.serviceMaterialId!,
          weightKg: waste.weightKg!,
        );
      }).toList();

      print('Creating appointment with date: ${selectedDate.toString()}');
      final appointment = Appointment(
        appointmentInfoId: '',
        serviceId: widget.service.serviceId,
        userInfoId: userInfo.userInfoId,
        availSchedId: selectedSchedule?.availScheduleId,
        appointmentDate: selectedType == AppointmentType.pickUp
            ? selectedSchedule!.availDate
            : selectedDate, // Use selectedDate directly for drop-off
        appointmentLocation: userLocation ?? widget.service.serviceLocation,
        appointmentStatus: AppointmentStatus.pending,
        appointmentNotes: _notesController.text.trim(),
        appointmentType: selectedType!,
        appointmentPriceFee: selectedType == AppointmentType.pickUp
            ? 50.0
            : 0.0,
        appointmentCreateDate: DateTime.now(),
      );

      // Timeout for Supabase
      final createdAppointment = await ref
          .read(
            createAppointmentProvider({
              'appointment': appointment,
              'waste': wastes,
            }).future,
          )
          .timeout(const Duration(seconds: 15));

      // Finalize QR code
      await ref
          .read(
            finalizeAppointmentProvider(
              createdAppointment.appointmentInfoId!,
            ).future,
          )
          .timeout(const Duration(seconds: 10));

      // --- MODIFICATION START: Add points to user ---
      try {
        // Fetch the latest user points directly from the database to avoid model issues
        final pointsResponse = await Supabase.instance.client
            .from('user_info')
            .select('user_points')
            .eq('user_info_id', userInfo.userInfoId)
            .single();

        final currentPoints = (pointsResponse['user_points'] ?? 0) as int;
        final newPoints =
            currentPoints + EcoPointsConstants.scheduleConfirmationBonusPoints;

        await Supabase.instance.client
            .from('user_info')
            .update({'user_points': newPoints})
            .eq('user_info_id', userInfo.userInfoId);

        // Invalidate the user provider to refresh the user's data across the app
        ref.invalidate(userProvider);
      } catch (e) {
        // Log the error but don't block the success flow
        print('Error updating user points: $e');
      }
      // --- MODIFICATION END ---

      // Hide loader
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // Show success dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => SuccessDialog(
            message:
                'Success! Your recycling appointment is confirmed. You earned ${EcoPointsConstants.scheduleConfirmationBonusPoints} points! Thank you for helping us make a difference!',
          ),
        ).then((_) {
          ref.invalidate(userAppointmentsProvider);
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      if (mounted)
        Navigator.of(context, rootNavigator: true).pop(); // hide loader

      setState(() {
        error = 'Error: ${e.toString()}';
        isLoading = false;
      });
      print('Exception during scheduling: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  TextButton(
                    onPressed: _clearForm,
                    child: Text(
                      "Clear data",
                      style: TextStyle(
                        fontFamily: 'Mallanna',
                        color: const Color(0xFF4B5320),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ServiceTypeSelector(
                service: widget.service,
                selectedType: selectedType,
                onTypeSelected: _selectType,
              ),
              if (selectedType != null) ...[
                const Divider(height: 30),
                WasteMaterialSection(
                  wasteMaterials: wasteMaterials,
                  serviceMaterials: widget.service.serviceMaterials,
                  onMaterialChanged: (index, newMaterialId) {
                    setState(() {
                      wasteMaterials[index] = AppointmentWaste(
                        appointmentWasteId:
                            wasteMaterials[index].appointmentWasteId,
                        appointmentInfoId:
                            wasteMaterials[index].appointmentInfoId,
                        weightKg: wasteMaterials[index].weightKg,
                        serviceMaterialId: newMaterialId,
                      );
                    });
                  },
                  onWeightChanged: (index, newWeight) =>
                      _updateMaterialWeight(index, newWeight),
                  onRemove: (index) => _removeMaterial(index),
                  onAdd: _addMaterial,
                ),
                const Divider(height: 30),
                selectedType == AppointmentType.pickUp &&
                        widget.service.serviceAvailability.contains('Pick-Up')
                    ? PickupDetailsSection(
                        key: ValueKey(selectedSchedule?.availScheduleId),
                        service: widget.service,
                        selectedSchedule: selectedSchedule,
                        onScheduleSelected: (schedule) => setState(() {
                          selectedSchedule = schedule;
                        }),
                        userLocation: userLocation,
                        onLocationChanged: (value) {
                          setState(() => userLocation = value);
                        },
                      )
                    : DropoffDetailsSection(
                        service: widget.service,
                        selectedDate: selectedDate,
                        onDateSelected: (newDate) {
                          setState(() {
                            selectedDate = newDate;
                          });
                        },
                      ),
                const Divider(height: 30),
                AdditionalNotesField(controller: _notesController),
                const Divider(height: 30),
                WasteSummaryWidget(
                  wasteMaterials: wasteMaterials,
                  service: widget.service,
                  selectedType: selectedType!,
                  userLocation: userLocation,
                  selectedSchedule: selectedSchedule,
                  selectedDate: selectedDate,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      error!,
                      style: const TextStyle(
                        fontFamily: 'Mallanna',
                        color: Colors.red,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                BottomSummaryWidget(
                  wasteMaterials: wasteMaterials,
                  selectedType: selectedType!,
                  isLoading: isLoading,
                  onSchedulePressed: _scheduleAppointment,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
