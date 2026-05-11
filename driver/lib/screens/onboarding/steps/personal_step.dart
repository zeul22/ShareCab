import 'package:flutter/material.dart';

import '../onboarding_state.dart';

/// Step 1 — Personal details. Keep it short: only name is required, email
/// is optional. The phone is already verified, so we don't ask again.
class PersonalStep extends StatefulWidget {
  final OnboardingState state;
  final VoidCallback onContinue;

  const PersonalStep({
    super.key,
    required this.state,
    required this.onContinue,
  });

  @override
  State<PersonalStep> createState() => _PersonalStepState();
}

class _PersonalStepState extends State<PersonalStep> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.state.fullName);
  late final TextEditingController _email =
      TextEditingController(text: widget.state.email);

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    widget.state.fullName = _name.text.trim();
    widget.state.email = _email.text.trim();
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tell us about yourself',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Use the name on your driving licence so we can match the '
              'documents you upload next.',
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.length < 2) return 'Enter your full name';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (optional)',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return null;
                if (!t.contains('@') || !t.contains('.')) {
                  return 'Enter a valid email';
                }
                return null;
              },
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _continue,
              child: const Text('Continue'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
