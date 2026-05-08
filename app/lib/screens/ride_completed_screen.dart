import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

class RideCompletedScreen extends StatelessWidget {
  const RideCompletedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ride = context.watch<RideFlowState>().activeRide;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: AppTheme.brandLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    color: AppTheme.brand, size: 50),
              ),
              const SizedBox(height: 18),
              const Text(
                'Ride completed',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Thanks for sharing — every shared ride saves money and keeps a car off the road.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              if (ride != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6F7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      _Row(label: 'Your share', value: '₹${ride.perRiderFare.toStringAsFixed(0)}'),
                      const Divider(height: 16),
                      _Row(label: 'Riders', value: '${ride.proposal.riderCount}'),
                      const Divider(height: 16),
                      _Row(label: 'Driver', value: ride.driver.name),
                    ],
                  ),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pushReplacementNamed(Routes.rating),
                child: const Text('Rate your ride'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  context.read<RideFlowState>().clear();
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil(Routes.home, (_) => false);
                },
                child: const Text('Skip — back to home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
