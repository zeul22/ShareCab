import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/payment.dart';
import '../routes.dart';
import '../services/ride_flow.dart';
import '../theme/app_theme.dart';

/// Each rider pays their own share. The user picks pay-now vs pay-after, and
/// a method. Real gateway integration is mocked behind [RideApi.completePayment].
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  PaymentTiming _timing = PaymentTiming.afterRide;
  PaymentMethod _method = PaymentMethod.upi;
  bool _busy = false;

  Future<void> _pay() async {
    setState(() => _busy = true);
    final flow = context.read<RideFlowState>();
    flow.preparePayment(timing: _timing, method: _method);
    await flow.completePayment();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(Routes.rideCompleted);
  }

  @override
  Widget build(BuildContext context) {
    final ride = context.watch<RideFlowState>().activeRide;
    if (ride == null) {
      return const Scaffold(body: Center(child: Text('No active ride.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.brandLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Your share of this ride',
                      style: TextStyle(
                        color: AppTheme.brandDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '₹${ride.perRiderFare.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.brandDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text('When do you want to pay?',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _Pill(
              selected: _timing == PaymentTiming.beforeRide,
              title: 'Pay now',
              subtitle: 'Settle before the ride starts.',
              onTap: () => setState(() => _timing = PaymentTiming.beforeRide),
            ),
            const SizedBox(height: 8),
            _Pill(
              selected: _timing == PaymentTiming.afterRide,
              title: 'Pay after drop',
              subtitle: 'You’ll be charged when the ride ends.',
              onTap: () => setState(() => _timing = PaymentTiming.afterRide),
            ),
            const SizedBox(height: 22),
            const Text('Method', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _MethodGrid(
              method: _method,
              onChanged: (m) => setState(() => _method = m),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _busy ? null : _pay,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(_timing == PaymentTiming.beforeRide
                      ? 'Pay ₹${ride.perRiderFare.toStringAsFixed(0)} now'
                      : 'Confirm — pay later'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Mock payment for the scaffold. Wire to a real gateway (Razorpay / Stripe) in production.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _Pill({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brandLight : const Color(0xFFF4F6F7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.brand : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? AppTheme.brand : Colors.black26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodGrid extends StatelessWidget {
  final PaymentMethod method;
  final ValueChanged<PaymentMethod> onChanged;
  const _MethodGrid({required this.method, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final items = <(PaymentMethod, IconData, String)>[
      (PaymentMethod.upi, Icons.account_balance_wallet, 'UPI'),
      (PaymentMethod.card, Icons.credit_card, 'Card'),
      (PaymentMethod.wallet, Icons.account_balance, 'Wallet'),
      (PaymentMethod.cash, Icons.money, 'Cash'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: items
          .map(
            (e) => InkWell(
              onTap: () => onChanged(e.$1),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: e.$1 == method ? AppTheme.brandLight : const Color(0xFFF4F6F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: e.$1 == method ? AppTheme.brand : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(e.$2, color: e.$1 == method ? AppTheme.brand : Colors.black54),
                    const SizedBox(width: 10),
                    Text(e.$3, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
