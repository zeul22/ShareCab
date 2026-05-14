import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// First-time rider onboarding — collects name + email after OTP verify.
/// Routed to from the splash + OTP-verify flows when the backend reports
/// `profileCompleted: false` on the signed-in user. Submits via
/// [AuthService.updateMyProfile] (PATCH /api/users/:id), which mutates
/// the persisted session in place so [AppUser.profileCompleted] flips to
/// true and subsequent app launches skip this screen.
///
/// Back is suppressed — the rider already verified their phone, the
/// only way forward is filling this form. (Letting them back out
/// would leave them stuck on the phone-entry screen with an active
/// session.)
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  // Same regex pattern as the backend's profileUpdateSchema. Accepts
  // letters (including Unicode for Indian-language names), spaces,
  // apostrophes, dots, hyphens. Caught here too so users get instant
  // feedback instead of a server round-trip.
  static final _nameRegex = RegExp(r"^[\p{L}][\p{L}\s.'-]*$", unicode: true);
  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  String? _validateName(String? v) {
    final t = (v ?? '').trim();
    if (t.length < 2) return 'Enter your full name';
    if (t.length > 60) return 'Name is too long';
    if (!_nameRegex.hasMatch(t)) return 'Name has invalid characters';
    return null;
  }

  String? _validateEmail(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Enter your email';
    if (!_emailRegex.hasMatch(t)) return 'Enter a valid email';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().updateMyProfile(
            name: _name.text.trim(),
            email: _email.text.trim().toLowerCase(),
          );
      if (!mounted) return;
      // Burn the back stack — onboarding is one-way, no value in
      // letting the user pop back to it after they've completed it.
      Navigator.of(context)
          .pushNamedAndRemoveUntil(Routes.home, (_) => false);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^[A-Z]\w+: '), '');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.watch<AuthService>().user?.phone ?? '';

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Welcome to ShareCab',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "We just need a few details. We'll never share these "
                    'with your co-rider unless you start a ride together.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Phone already known — show it as a read-only chip so
                  // the user knows which account they're completing.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.brandLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppTheme.brand, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Phone verified: $phone',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.brandDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      hintText: 'e.g. Asha Sharma',
                      counterText: '',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: _validateName,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    inputFormatters: [
                      // Reject whitespace — emails don't have any, and
                      // typing a space mid-flow is almost always a typo.
                      FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: _validateEmail,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFD6D6)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Color(0xFFB00020), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFB00020),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Continue',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'By continuing you agree to ShareCab\'s Terms & '
                    'Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
