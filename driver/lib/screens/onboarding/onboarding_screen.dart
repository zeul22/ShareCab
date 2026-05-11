import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../routes.dart';
import '../../services/api/driver_api.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'onboarding_state.dart';
import 'steps/personal_step.dart';
import 'steps/vehicle_step.dart';
import 'steps/documents_step.dart';
import 'steps/review_step.dart';

/// Driver onboarding wizard — the Rapido/Uber/Ola-style first-launch flow.
/// Four steps:
///   1. Personal       — name, email
///   2. Vehicle        — license number + car details
///   3. Documents      — photo uploads (UX stub; backend wiring later)
///   4. Review/submit  — confirm + send to /drivers/onboard
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _state = OnboardingState();
  int _stepIndex = 0;
  bool _submitting = false;
  String? _error;

  static const _totalSteps = 4;

  void _next() {
    setState(() {
      _error = null;
      if (_stepIndex < _totalSteps - 1) _stepIndex++;
    });
  }

  void _back() {
    setState(() {
      _error = null;
      if (_stepIndex > 0) _stepIndex--;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    // Grab service refs upfront so we don't re-read from context across the
    // async gap (lint: use_build_context_synchronously).
    final driverApi = context.read<DriverApi>();
    final auth = context.read<AuthService>();
    try {
      final submission = OnboardingSubmission(
        fullName: _state.fullName.trim(),
        email: _state.email.trim().isEmpty ? null : _state.email.trim(),
        licenseNumber: _state.licenseNumber.trim().toUpperCase(),
        vehicleModel: _state.vehicleModel.trim(),
        plate: _state.plate.trim().toUpperCase(),
        color: _state.color.trim().isEmpty ? null : _state.color.trim(),
        capacity: _state.capacity,
      );
      await driverApi.submitOnboarding(submission);
      // Backend just promoted the User role from rider → driver, but the
      // JWT we're holding was minted at OTP time and still says rider.
      // Refresh the session so subsequent role-gated endpoints (/online,
      // /offline, /me/dispatch) see the new role on the wire.
      await auth.forceRefresh();
      if (!mounted) return;
      Navigator.of(context)
          .pushNamedAndRemoveUntil(Routes.pendingReview, (_) => false);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^[A-Z]\w+: '), '');
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildStepBody() {
    switch (_stepIndex) {
      case 0:
        return PersonalStep(state: _state, onContinue: _next);
      case 1:
        return VehicleStep(
          state: _state,
          onContinue: _next,
          onBack: _back,
        );
      case 2:
        return DocumentsStep(
          state: _state,
          onContinue: _next,
          onBack: _back,
        );
      case 3:
        return ReviewStep(
          state: _state,
          submitting: _submitting,
          error: _error,
          onSubmit: _submit,
          onBack: _back,
          onEditStep: (i) => setState(() => _stepIndex = i),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_stepIndex + 1) / _totalSteps;
    return Scaffold(
      appBar: AppBar(
        leading: _stepIndex == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _back,
              ),
        title: Text(
          'Step ${_stepIndex + 1} of $_totalSteps',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: AppTheme.brandLight,
            valueColor: const AlwaysStoppedAnimation(AppTheme.brand),
          ),
        ),
      ),
      // AnimatedSwitcher gives each step a soft cross-fade — small touch
      // that makes the wizard feel less like four disconnected forms.
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey(_stepIndex),
          child: _buildStepBody(),
        ),
      ),
    );
  }
}
