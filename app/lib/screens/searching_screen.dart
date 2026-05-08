import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

/// Active search state. Kicks off the search and routes to the match-result
/// screen as soon as proposals arrive.
class SearchingScreen extends StatefulWidget {
  const SearchingScreen({super.key});

  @override
  State<SearchingScreen> createState() => _SearchingScreenState();
}

class _SearchingScreenState extends State<SearchingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<RideFlowState>().startSearch();
      if (!mounted) return;
      final flow = context.read<RideFlowState>();
      if (flow.stage == FlowStage.proposing && flow.proposals.isNotEmpty) {
        Navigator.of(context).pushReplacementNamed(Routes.matchResult);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<RideFlowState>();
    final empty = flow.stage == FlowStage.searching && flow.proposals.isEmpty;
    final airport = flow.search.airportArrivalMode;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            context.read<RideFlowState>().clear();
            Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(strokeWidth: 4, color: AppTheme.brand),
              ),
              const SizedBox(height: 24),
              Text(
                airport
                    ? 'Looking for landing co-passengers…'
                    : 'Finding compatible co-passengers…',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Checking nearby riders, vehicle capacity, and luggage space.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              if (empty) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'No match yet. Keep searching, or try the random-compatible mode for faster results.',
                    style: TextStyle(color: Color(0xFF8A6D00)),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => context.read<RideFlowState>().retrySearch(),
                  child: const Text('Search again'),
                ),
              ],
              if (flow.error != null) ...[
                const SizedBox(height: 18),
                Text(flow.error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
