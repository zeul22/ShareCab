import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ride_search.dart';
import '../routes.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

/// Lets the user choose how they want to be matched.
class MatchPreferenceScreen extends StatelessWidget {
  const MatchPreferenceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<RideFlowState>();
    return Scaffold(
      appBar: AppBar(title: const Text('How should we match you?')),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OptionCard(
                title: 'Nearby destination match',
                description:
                    'Pair with riders whose drop-off is within 2–4 km of yours. Best when you know exactly where you’re going.',
                selected: flow.search.preference == MatchPreference.destinationNearby,
                onTap: () => context
                    .read<RideFlowState>()
                    .setPreference(MatchPreference.destinationNearby),
                icon: Icons.flag_outlined,
              ),
              const SizedBox(height: 12),
              _OptionCard(
                title: 'Random compatible match',
                description:
                    'Auto-allocate to any group going your way — same vehicle, room for your bags, '
                    'and route makes sense. Faster matches at busy times.',
                selected: flow.search.preference == MatchPreference.randomCompatible,
                onTap: () => context
                    .read<RideFlowState>()
                    .setPreference(MatchPreference.randomCompatible),
                icon: Icons.shuffle,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pushNamed(Routes.searching),
            child: const Text('Find a match'),
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;

  const _OptionCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brandLight : const Color(0xFFF4F6F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.brand : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.black54, height: 1.35),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? AppTheme.brand : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }
}
