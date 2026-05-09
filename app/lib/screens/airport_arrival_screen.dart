import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

/// "Find match after plane lands" entry point.
///
/// User picks an arrival time; we open the search session anchored to that
/// time so they get matched with co-passengers who are also landing in the
/// same window. After confirming, the user is sent into the standard plan
/// flow (Pickup will default to the airport in a real impl).
class AirportArrivalScreen extends StatefulWidget {
  const AirportArrivalScreen({super.key});

  @override
  State<AirportArrivalScreen> createState() => _AirportArrivalScreenState();
}

class _AirportArrivalScreenState extends State<AirportArrivalScreen> {
  DateTime? _landsAt;

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: now.hour, minute: now.minute),
      helpText: 'When does your flight land?',
    );
    if (picked == null) return;
    final candidate = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    setState(() {
      _landsAt = candidate.isBefore(now) ? candidate.add(const Duration(days: 1)) : candidate;
    });
  }

  void _continue() {
    if (_landsAt == null) return;
    context.read<RideFlowState>().setAirportMode(enabled: true, landsAt: _landsAt);
    Navigator.of(context).pushReplacementNamed(Routes.planRide);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find match after landing')),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Travelling from the airport?',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tell us when you land and we’ll start looking for shareable rides at that time. '
                'Most matches happen when many passengers are searching together.',
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.brandLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.flight_land, color: AppTheme.brandDark),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _landsAt == null
                            ? 'Pick your landing time'
                            : 'Landing at ${TimeOfDay.fromDateTime(_landsAt!).format(context)}',
                        style: const TextStyle(
                          color: AppTheme.brandDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(onPressed: _pickTime, child: const Text('Change')),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: _landsAt == null ? null : _continue,
                child: const Text('Continue'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Skip — book now instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
