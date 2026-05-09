import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/api/mock_auth_api.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

const _demoRiderEntries = [
  ('Demo Rider 1', '9990000101'),
  ('Demo Rider 2', '9990000102'),
];

/// Step 1 of the auth flow: collect a phone number and request an OTP.
class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().requestOtp(_phone.text);
      if (!mounted) return;
      Navigator.of(context).pushNamed(Routes.otpVerify);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^[A-Z]\w+: '), ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tap-to-fill: drop the chosen demo phone into the input AND immediately
  /// request the OTP. Two taps total (this + demo OTP on the next screen) to
  /// log in as the picked rider.
  Future<void> _useDemoRider(String phone) async {
    _phone.text = phone;
    setState(() => _error = null);
    await _send();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brand,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'S',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Welcome to ShareCab',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter your phone number to log in or create an account.',
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                  LengthLimitingTextInputFormatter(16),
                ],
                autofocus: true,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 18),
              _DemoAccountsPanel(
                onUseDemo: _busy ? null : _useDemoRider,
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
          child: ElevatedButton(
            onPressed: _busy ? null : _send,
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('Send OTP'),
          ),
        ),
      ),
    );
  }
}

/// Panel listing the seeded demo riders. Tap any row to autofill the phone
/// and request an OTP — the next screen pre-fills [MockAuthApi.demoOtp].
/// Use two phones across two devices to exercise the matching flow.
class _DemoAccountsPanel extends StatelessWidget {
  final ValueChanged<String>? onUseDemo;
  const _DemoAccountsPanel({required this.onUseDemo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.brandLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 20, color: AppTheme.brandDark),
              SizedBox(width: 8),
              Text(
                'Demo riders',
                style: TextStyle(
                  color: AppTheme.brandDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              Spacer(),
              Text('OTP ', style: TextStyle(color: AppTheme.brandDark, fontSize: 12)),
              Text(
                MockAuthApi.demoOtp,
                style: TextStyle(
                  color: AppTheme.brandDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final entry in _demoRiderEntries) ...[
            _DemoRiderRow(
              label: entry.$1,
              phone: entry.$2,
              onTap: onUseDemo == null ? null : () => onUseDemo!(entry.$2),
            ),
            if (entry != _demoRiderEntries.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _DemoRiderRow extends StatelessWidget {
  final String label;
  final String phone;
  final VoidCallback? onTap;

  const _DemoRiderRow({
    required this.label,
    required this.phone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.brandDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                phone,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Copy phone',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: phone));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied $phone'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 18, color: AppTheme.brand),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.brandLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.flash_on, size: 16, color: AppTheme.brand),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
