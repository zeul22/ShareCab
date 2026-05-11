import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../onboarding_state.dart';

/// Step 2 — License + vehicle details. The backend mirrors this exact
/// shape: `licenseNumber` plus a `vehicle` sub-doc with model, plate,
/// color and capacity.
class VehicleStep extends StatefulWidget {
  final OnboardingState state;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  const VehicleStep({
    super.key,
    required this.state,
    required this.onContinue,
    required this.onBack,
  });

  @override
  State<VehicleStep> createState() => _VehicleStepState();
}

class _VehicleStepState extends State<VehicleStep> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _license =
      TextEditingController(text: widget.state.licenseNumber);
  late final TextEditingController _model =
      TextEditingController(text: widget.state.vehicleModel);
  late final TextEditingController _plate =
      TextEditingController(text: widget.state.plate);
  late final TextEditingController _color =
      TextEditingController(text: widget.state.color);
  late int _capacity = widget.state.capacity;

  @override
  void dispose() {
    _license.dispose();
    _model.dispose();
    _plate.dispose();
    _color.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    widget.state
      ..licenseNumber = _license.text.trim().toUpperCase()
      ..vehicleModel = _model.text.trim()
      ..plate = _plate.text.trim().toUpperCase()
      ..color = _color.text.trim()
      ..capacity = _capacity;
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Your vehicle',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Riders will see this on the trip screen. Use the exact '
                'details that appear on your RC and licence.',
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 22),
              TextFormField(
                controller: _license,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(20),
                ],
                decoration: const InputDecoration(
                  labelText: 'Driving licence number',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.length < 4) return 'Enter your licence number';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _model,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Car model (e.g. Maruti Swift)',
                  prefixIcon: Icon(Icons.directions_car_outlined),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.length < 2) return 'Enter your car model';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _plate,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: const InputDecoration(
                  labelText: 'Number plate (e.g. KA01AB1234)',
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.length < 6) return 'Enter your number plate';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _color,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Colour (optional)',
                  prefixIcon: Icon(Icons.palette_outlined),
                ),
              ),
              const SizedBox(height: 18),
              _CapacityPicker(
                value: _capacity,
                onChanged: (v) => setState(() => _capacity = v),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _continue,
                child: const Text('Continue'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick segmented picker for seat capacity. Indian fleet is overwhelmingly
/// 4-seaters; 6 covers SUVs/Innovas. No need for a stepper.
class _CapacityPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _CapacityPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Text(
              'Passenger capacity',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Row(
            children: [
              for (final c in const [3, 4, 6])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text('$c seats'),
                      selected: value == c,
                      onSelected: (_) => onChanged(c),
                      selectedColor: AppTheme.brand,
                      labelStyle: TextStyle(
                        color: value == c ? Colors.white : AppTheme.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
