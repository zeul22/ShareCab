import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/passenger.dart';
import '../models/ride.dart';
import '../routes.dart';
import '../services/api/ride_api.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

/// Post-match coordination screen for rider-only mode (no drivers on
/// platform yet). After accepting a match, the rider lands here instead
/// of the full driver-tracking flow. They can:
///
///   - See the co-rider's name + rating
///   - Open in-app chat to coordinate (pickup spot, which cab service)
///   - Tap "We're done" once they've met up and arranged their own
///     ride — closes the trip server-side, pops back to home.
///
/// When drivers start joining the platform, the [acceptProposal] flow
/// will route to RideConfirmationScreen instead (because the proposal
/// has a real driver assigned), and this screen quietly becomes unused.
class RiderCoordinationScreen extends StatefulWidget {
  const RiderCoordinationScreen({super.key});

  @override
  State<RiderCoordinationScreen> createState() =>
      _RiderCoordinationScreenState();
}

class _RiderCoordinationScreenState extends State<RiderCoordinationScreen> {
  bool _closing = false;
  String? _error;

  Future<void> _confirmAndClose(Ride ride) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Close this ride?'),
        content: const Text(
          "We'll mark your trip complete on ShareCab. You can still chat "
          'with your co-rider until they close their side too.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Keep open'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.brandDark),
            child: const Text("We're done"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _closing = true;
      _error = null;
    });
    try {
      final api = context.read<RideApi>();
      await api.closeRiderTrip(ride.id);
      if (!mounted) return;
      // Clear the local ride flow state so the home screen doesn't
      // restore us back into this screen via the resume flow.
      context.read<RideFlowState>().clearAfterClose();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Ride closed. Hope your co-rider was good company!'),
          duration: Duration(seconds: 3),
        ));
      Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _closing = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<RideFlowState>();
    final ride = flow.activeRide;
    if (ride == null) {
      // Nothing to coordinate — likely closed already, or we landed
      // here from a deep link without state. Just go home.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).popUntil(ModalRoute.withName(Routes.home));
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final coRiders = ride.proposal.coPassengers;
    final groupId = ride.proposal.groupId;

    return Scaffold(
      appBar: AppBar(
        title: const Text("You're matched"),
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderCard(coRiderCount: coRiders.length),
              const SizedBox(height: 18),
              const Text(
                'How this works right now',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const _NumberedList(
                items: [
                  'Drivers haven\'t joined ShareCab yet, so we just '
                      'connect you with your match.',
                  'Chat to agree on a pickup point and which cab app '
                      'you\'ll book together.',
                  'When the ride\'s done, tap "We\'re done" below — that '
                      'closes the trip on ShareCab.',
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Your co-rider',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              for (final p in coRiders) ...[
                _CoRiderTile(passenger: p),
                if (p != coRiders.last) const SizedBox(height: 8),
              ],
              if (coRiders.isEmpty)
                const Text(
                  'Co-rider details will appear here once the match '
                  'is fully revealed.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              const SizedBox(height: 20),
              if (groupId != null && groupId.isNotEmpty)
                _PrimaryAction(
                  icon: Icons.chat_bubble_outline,
                  label: 'Open chat',
                  onPressed: _closing
                      ? null
                      : () => Navigator.of(context).pushNamed(
                            Routes.chat,
                            arguments: groupId,
                          ),
                ),
              const SizedBox(height: 10),
              const _SecondaryHint(
                text: 'Phone numbers stay private — coordinate via chat.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _ErrorChip(message: _error!),
              ],
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: ElevatedButton(
            onPressed: _closing ? null : () => _confirmAndClose(ride),
            child: _closing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text("We're done — close ride"),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _HeaderCard extends StatelessWidget {
  final int coRiderCount;
  const _HeaderCard({required this.coRiderCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.brandLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppTheme.brand,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.handshake_outlined,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coRiderCount == 1
                      ? 'You\'re matched with 1 co-rider'
                      : 'You\'re matched with $coRiderCount co-riders',
                  style: const TextStyle(
                    color: AppTheme.brandDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Coordinate via chat and split the cab.',
                  style: TextStyle(color: AppTheme.brandDark, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoRiderTile extends StatelessWidget {
  final Passenger passenger;
  const _CoRiderTile({required this.passenger});

  @override
  Widget build(BuildContext context) {
    final initial = passenger.firstName.isNotEmpty
        ? passenger.firstName[0].toUpperCase()
        : '?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.brandLight,
            child: Text(
              initial,
              style: const TextStyle(
                color: AppTheme.brandDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passenger.firstName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.star, size: 13, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(
                      passenger.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.brandDark,
          side: const BorderSide(color: AppTheme.brand),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _SecondaryHint extends StatelessWidget {
  final String text;
  const _SecondaryHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.black45, fontSize: 12),
      ),
    );
  }
}

class _NumberedList extends StatelessWidget {
  final List<String> items;
  const _NumberedList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(
                  color: AppTheme.brand,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  items[i],
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          if (i < items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ErrorChip extends StatelessWidget {
  final String message;
  const _ErrorChip({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1C0C0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB00020), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB00020),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
