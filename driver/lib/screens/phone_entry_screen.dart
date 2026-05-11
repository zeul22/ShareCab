import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/country.dart';
import '../routes.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_config.dart';
import '../widgets/country_picker_bottom_sheet.dart';

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
  Country _country = Country.defaultCountry;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickCountry() async {
    final picked = await CountryPickerBottomSheet.show(
      context,
      selected: _country,
    );
    if (picked != null && picked.code != _country.code) {
      setState(() => _country = picked);
    }
  }

  String _composeE164() {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final stripped = digits.startsWith('0') ? digits.substring(1) : digits;
    return '${_country.prefix}$stripped';
  }

  Future<void> _send() async {
    final e164 = _composeE164();
    final localDigits = e164.length - _country.prefix.length;
    if (localDigits < 5) {
      setState(() => _error = 'Enter a valid phone number');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().requestOtp(e164);
      if (!mounted) return;
      Navigator.of(context).pushNamed(Routes.otpVerify);
    } catch (e) {
      setState(() =>
          _error = e.toString().replaceFirst(RegExp(r'^[A-Z]\w+: '), ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              Align(
                alignment: Alignment.center,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/appIcon.png',
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Drive with ShareCab',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sign in with your phone to start earning. New drivers will '
                'complete a quick verification next.',
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CountryCodeButton(
                    country: _country,
                    onTap: _busy ? null : _pickCountry,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(14),
                      ],
                      autofocus: true,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style:
                        const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 18),
              if (!ApiConfig.msg91Enabled) const _DevModeHint(),
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
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('Send OTP'),
          ),
        ),
      ),
    );
  }
}

class _DevModeHint extends StatelessWidget {
  const _DevModeHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.brandLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.lightbulb_outline,
              size: 20, color: AppTheme.brandDark),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Dev mode: any 10-digit Indian number works. Use OTP 123456 on '
              'the next screen.',
              style: TextStyle(
                color: AppTheme.brandDark,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryCodeButton extends StatelessWidget {
  final Country country;
  final VoidCallback? onTap;
  const _CountryCodeButton({required this.country, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.brandLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              country.prefix,
              style: const TextStyle(
                color: AppTheme.brandDark,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down,
              color: AppTheme.brandDark,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
