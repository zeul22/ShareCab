import 'package:flutter/material.dart';

import '../models/match_proposal.dart';
import '../models/route_stop.dart';
import '../theme/app_theme.dart';

/// Detailed view of the stop sequence for a proposal. Reached from the
/// match-result card; takes a [MatchProposal] as `arguments`.
class RouteStopsScreen extends StatelessWidget {
  const RouteStopsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final proposal = ModalRoute.of(context)!.settings.arguments as MatchProposal;
    return Scaffold(
      appBar: AppBar(title: const Text('Route & stops')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${proposal.stops.length} stops · ${proposal.distanceKm.toStringAsFixed(1)} km · ${proposal.durationMin} min',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ...List.generate(proposal.stops.length, (i) {
              final s = proposal.stops[i];
              final isLast = i == proposal.stops.length - 1;
              return _StopTile(stop: s, isLast: isLast);
            }),
          ],
        ),
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  final RouteStop stop;
  final bool isLast;
  const _StopTile({required this.stop, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final isPickup = stop.kind == StopKind.pickup;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: isPickup ? AppTheme.brand : Colors.black87,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: Colors.black12),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isPickup ? 'Pickup · ${stop.passengerFirstName}' : 'Drop · ${stop.passengerFirstName}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        '+${stop.etaFromStartMin} min',
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stop.place.address.isEmpty ? '${stop.place.lat.toStringAsFixed(4)}, ${stop.place.lng.toStringAsFixed(4)}' : stop.place.address,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
