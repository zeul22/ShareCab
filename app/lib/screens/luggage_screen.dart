import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/luggage.dart';
import '../routes.dart';
import '../services/matching/luggage_rules.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

/// User declares their luggage so the matching engine can size the cab and
/// reserve enough boot space.
class LuggageScreen extends StatefulWidget {
  const LuggageScreen({super.key});

  @override
  State<LuggageScreen> createState() => _LuggageScreenState();
}

class _LuggageScreenState extends State<LuggageScreen> {
  late LuggageProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = context.read<RideFlowState>().search.luggage;
  }

  void _continue() {
    context.read<RideFlowState>().setLuggage(_profile);
    Navigator.of(context).pushNamed(Routes.matchPreference);
  }

  @override
  Widget build(BuildContext context) {
    final seats = LuggageRules.seatsConsumed(_profile);

    return Scaffold(
      appBar: AppBar(title: const Text('What are you carrying?')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Bags help us pick the right cab and reserve boot space.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              _Counter(
                title: 'Handbag / laptop bag',
                subtitle: 'Carried on lap. Doesn’t take a seat.',
                count: _profile.handbagCount,
                onChanged: (v) => setState(() => _profile = _profile.copyWith(handbagCount: v)),
              ),
              const SizedBox(height: 12),
              _Counter(
                title: 'Cabin trolley',
                subtitle: '2 cabin bags = 1 luggage seat.',
                count: _profile.trolleyLightCount,
                onChanged: (v) =>
                    setState(() => _profile = _profile.copyWith(trolleyLightCount: v)),
              ),
              const SizedBox(height: 12),
              _Counter(
                title: 'Large suitcase',
                subtitle: 'Each large bag = 1 luggage seat.',
                count: _profile.trolleyHeavyCount,
                onChanged: (v) =>
                    setState(() => _profile = _profile.copyWith(trolleyHeavyCount: v)),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.brandLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.work_outline, color: AppTheme.brandDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        seats == 0
                            ? 'No luggage seats needed'
                            : '$seats luggage seat${seats == 1 ? '' : 's'} needed',
                        style: const TextStyle(
                          color: AppTheme.brandDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      LuggageRules.describe(_profile),
                      style: const TextStyle(color: AppTheme.brandDark, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              ElevatedButton(onPressed: _continue, child: const Text('Continue')),
            ],
          ),
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final ValueChanged<int> onChanged;

  const _Counter({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: count == 0 ? null : () => onChanged(count - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
          IconButton(
            onPressed: count >= 9 ? null : () => onChanged(count + 1),
            icon: const Icon(Icons.add_circle_outline, color: AppTheme.brand),
          ),
        ],
      ),
    );
  }
}
