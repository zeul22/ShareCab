import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/api/mock_auth_api.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

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

  /// Tap-to-fill: drop the demo phone into the input AND immediately request
  /// the OTP. Two taps total (this + demo OTP on the next screen) to log in.
  Future<void> _useDemoPhone() async {
    _phone.text = MockAuthApi.demoPhone;
    setState(() => _error = null);
    await _send();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
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
              ElevatedButton(
                onPressed: _busy ? null : _send,
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Send OTP'),
              ),
              const SizedBox(height: 18),
              _DemoHint(onUseDemo: _busy ? null : _useDemoPhone),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoHint extends StatelessWidget {
  final VoidCallback? onUseDemo;
  const _DemoHint({required this.onUseDemo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppTheme.brandLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.lightbulb_outline, size: 20, color: AppTheme.brandDark),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demo login',
                  style: TextStyle(
                    color: AppTheme.brandDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      color: AppTheme.brandDark,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(text: 'Phone '),
                      TextSpan(
                        text: MockAuthApi.demoPhone,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: '   ·   OTP '),
                      TextSpan(
                        text: MockAuthApi.demoOtp,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tap to autofill the phone AND immediately send the OTP.
          IconButton(
            tooltip: 'Use demo phone',
            onPressed: onUseDemo,
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
              ),
              child: const Icon(Icons.flash_on, size: 18, color: AppTheme.brand),
            ),
          ),
        ],
      ),
    );
  }
}
