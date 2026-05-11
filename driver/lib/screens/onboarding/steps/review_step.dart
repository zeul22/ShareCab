import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../onboarding_state.dart';

/// Step 4 — Review + submit. Read-only summary of everything captured so
/// far with "Edit" links that jump back to the relevant step.
class ReviewStep extends StatelessWidget {
  final OnboardingState state;
  final bool submitting;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onBack;
  final ValueChanged<int> onEditStep;

  const ReviewStep({
    super.key,
    required this.state,
    required this.submitting,
    required this.error,
    required this.onSubmit,
    required this.onBack,
    required this.onEditStep,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              children: [
                const Text(
                  'Review & submit',
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  "We'll review your application within 24 hours. You'll get "
                  'a notification when you can start accepting trips.',
                  style: TextStyle(color: Colors.black54, height: 1.4),
                ),
                const SizedBox(height: 22),
                _Section(
                  title: 'Personal',
                  onEdit: () => onEditStep(0),
                  rows: [
                    _Row('Name', state.fullName),
                    if (state.email.isNotEmpty) _Row('Email', state.email),
                  ],
                ),
                const SizedBox(height: 14),
                _Section(
                  title: 'Vehicle',
                  onEdit: () => onEditStep(1),
                  rows: [
                    _Row('Licence', state.licenseNumber.toUpperCase()),
                    _Row('Model', state.vehicleModel),
                    _Row('Plate', state.plate.toUpperCase()),
                    if (state.color.isNotEmpty) _Row('Colour', state.color),
                    _Row('Capacity', '${state.capacity} seats'),
                  ],
                ),
                const SizedBox(height: 14),
                _Section(
                  title: 'Documents',
                  onEdit: () => onEditStep(2),
                  rows: [
                    _Row(
                      'Driving licence',
                      state.licensePhotoPath == null
                          ? 'Not attached'
                          : 'Attached',
                    ),
                    _Row(
                      'Vehicle RC',
                      state.rcPhotoPath == null ? 'Not attached' : 'Attached',
                    ),
                    _Row(
                      'Selfie',
                      state.selfiePhotoPath == null
                          ? 'Not attached'
                          : 'Attached',
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            error!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: ElevatedButton(
              onPressed: submitting ? null : onSubmit,
              child: submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Submit for review'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final VoidCallback onEdit;
  final List<_Row> rows;

  const _Section({
    required this.title,
    required this.onEdit,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              TextButton(
                onPressed: onEdit,
                child: const Text(
                  'Edit',
                  style: TextStyle(
                      color: AppTheme.brand, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final r in rows) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      r.label,
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.value.isEmpty ? '—' : r.value,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row {
  final String label;
  final String value;
  const _Row(this.label, this.value);
}
