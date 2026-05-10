import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/api/mock_auth_api.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_config.dart';

/// Step 2 of the auth flow: enter the 6-digit OTP. Auto-submits when full.
/// Includes a 30-second cool-down before the user can resend.
class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({super.key});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _otp = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;

  Timer? _resendTimer;
  int _resendSecondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _startResendCooldown();
  }

  @override
  void dispose() {
    _otp.dispose();
    _focus.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendSecondsLeft = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _resendSecondsLeft--);
      if (_resendSecondsLeft <= 0) t.cancel();
    });
  }

  Future<void> _verify(String otp) async {
    if (otp.length < 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      await auth.verifyOtp(otp);
      if (!mounted) return;
      // Route by role so a driver lands on DriverHome instead of the rider
      // home (and vice-versa). Single source of truth in Routes.homeForRole
      // — splash uses the same helper.
      final dest = Routes.homeForRole(auth.user?.role);
      Navigator.of(context).pushNamedAndRemoveUntil(dest, (_) => false);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^[A-Z]\w+: '), '');
        _busy = false;
      });
      _otp.clear();
      _focus.requestFocus();
    }
  }

  Future<void> _resend() async {
    final phone = context.read<AuthService>().pendingPhone;
    if (phone == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AuthService>().requestOtp(phone);
      _startResendCooldown();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.watch<AuthService>().pendingPhone ?? '';
    final canResend = _resendSecondsLeft <= 0 && !_busy;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            context.read<AuthService>().cancelOtp();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Verify your phone',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  style: const TextStyle(color: Colors.black54, height: 1.4),
                  children: [
                    const TextSpan(text: 'Enter the 6-digit code sent to '),
                    TextSpan(
                      text: phone,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _otp,
                focusNode: _focus,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 12,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                ),
                onChanged: (v) {
                  if (v.length == 6) _verify(v);
                },
                onSubmitted: _verify,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 14),
              // Demo-OTP hint is dev-mode only. With MSG91 wired up the
              // real OTP arrives via SMS, so showing a "use demo OTP"
              // button would just lead users into a guaranteed failure.
              if (!ApiConfig.msg91Enabled)
                _DemoOtpHint(
                  onUseDemo: _busy
                      ? null
                      : () {
                          _otp.text = MockAuthApi.demoOtp;
                          // Bypass the on-change auto-submit listener (it only
                          // fires on user typing) and verify directly.
                          _verify(MockAuthApi.demoOtp);
                        },
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
                onPressed: _busy ? null : () => _verify(_otp.text),
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Verify & log in'),
              ),
              TextButton(
                onPressed: canResend ? _resend : null,
                child: Text(
                  canResend
                      ? 'Resend OTP'
                      : 'Resend in ${_resendSecondsLeft}s',
                  style: TextStyle(
                    color: canResend ? AppTheme.brand : Colors.black45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoOtpHint extends StatelessWidget {
  final VoidCallback? onUseDemo;
  const _DemoOtpHint({required this.onUseDemo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.brandLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, size: 20, color: AppTheme.brandDark),
          const SizedBox(width: 10),
          const Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  color: AppTheme.brandDark,
                  fontSize: 13,
                  height: 1.4,
                ),
                children: [
                  TextSpan(text: 'Demo OTP  '),
                  TextSpan(
                    text: MockAuthApi.demoOtp,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
          // Tap to autofill the OTP — auto-submits since the field reaches 6 digits.
          IconButton(
            tooltip: 'Use demo OTP',
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
