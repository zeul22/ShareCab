import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/country.dart';
import '../routes.dart';
import '../services/api/mock_auth_api.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/country_picker_bottom_sheet.dart';

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
  // Defaults to India — picker is one tap away if the user is overseas.
  // Stored separately from the digits field so MSG91 always receives a
  // properly-prefixed E.164 number even if the user types nothing extra.
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

  /// Combine the picked dial code with the digits the user typed into
  /// the final E.164 string we send to MSG91 (`+91XXXXXXXXXX` etc.).
  /// Strips any non-digit characters from the typed value and removes a
  /// leading `0` (common Indian habit — phones are stored without it).
  String _composeE164() {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final stripped = digits.startsWith('0') ? digits.substring(1) : digits;
    return '${_country.prefix}$stripped';
  }

  Future<void> _send() async {
    // Drop the keyboard the moment the user commits to sending — iOS's
    // phone numpad has no return key, so without this it'd hover over
    // the "Send OTP" button while the request is in flight.
    FocusScope.of(context).unfocus();
    final e164 = _composeE164();
    // Cheapest possible validation — MSG91 + zod on the backend do the
    // real check. We just block obviously-empty / 1-2 digit submits so
    // the user doesn't pay for the round-trip to find out.
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
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^[A-Z]\w+: '), ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tap-to-fill: drop the chosen demo phone into the input AND immediately
  /// request the OTP. Demo riders are seeded as Indian numbers, so force
  /// the country picker back to India before composing.
  Future<void> _useDemoRider(String phone) async {
    _phone.text = phone;
    setState(() {
      _country = Country.defaultCountry;
      _error = null;
    });
    await _send();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Tap anywhere outside the phone field to drop the keyboard. iOS's
      // phone numpad has no return key, so without this the user has no
      // way to dismiss it short of submitting. HitTestBehavior.opaque
      // means empty regions (the headline, demo panel, gaps between
      // widgets) still register taps.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            // Dragging the scroll view also dismisses the keyboard — a
            // gesture iOS users expect since it's the system-wide
            // pattern for forms that don't have a return key.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              // App icon tile. Centered horizontally on its own line —
              // Align opts out of the parent Column's
              // `crossAxisAlignment: stretch`, so the tile keeps its
              // natural 56x56 size instead of getting blown out to
              // full width and squishing the icon.
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
                'Welcome to ShareCab',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter your phone number to log in or create an account.',
                style: TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 28),
              // Country picker on the left of the digits field. The
              // dial code is owned by the picker so the input only ever
              // accepts the local number — no need to remember "+91".
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
                        // Digits only — the dial code is supplied by the picker.
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

/// Country-code prefix button shown to the left of the phone digits
/// field. Deliberately text-only (no flag emoji) because flag glyphs
/// don't render on every device — when they fail you get two tofu boxes
/// per flag which blow the chip's width out and squeeze the input next
/// to it. The bottom-sheet picker shows country names, which is enough
/// for users to find the right entry.
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
        // 56px matches the default Material 3 TextField height so the
        // chip and the phone input align cleanly on the same row.
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
