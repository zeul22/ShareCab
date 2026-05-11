import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/api/driver_api.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Step 2 of the auth flow: enter the 6-digit OTP. After verify we hit
/// `/drivers/me` to decide whether the user goes to the onboarding
/// wizard, the pending-review screen, or the home dashboard — same
/// decision tree as SplashScreen, just for the post-login transition.
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

      // Decide the post-login destination by asking the backend for
      // the driver record. Splash uses the same logic on cold start.
      final driverApi = context.read<DriverApi>();
      final profile = await driverApi.getMyDriverOrNull();
      if (!mounted) return;

      final String dest;
      if (profile == null) {
        dest = Routes.onboarding;
      } else if (profile.verificationStatus == 'approved') {
        dest = Routes.home;
      } else {
        dest = Routes.pendingReview;
      }
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
                  style:
                      const TextStyle(color: Colors.black54, height: 1.4),
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
                Text(_error!,
                    style:
                        const TextStyle(color: Colors.red, fontSize: 13)),
              ],
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
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Verify & continue'),
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
