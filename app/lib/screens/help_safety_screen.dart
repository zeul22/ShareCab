import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class HelpSafetyScreen extends StatelessWidget {
  const HelpSafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & safety')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            _SosBanner(),
            SizedBox(height: 16),
            _Header('On every ride'),
            _Item(
              icon: Icons.verified_user_outlined,
              title: 'Verified drivers',
              subtitle: 'License, vehicle, and background-checked.',
            ),
            _Item(
              icon: Icons.location_on_outlined,
              title: 'Live tracking',
              subtitle: 'Share trip status with anyone in one tap.',
            ),
            _Item(
              icon: Icons.numbers,
              title: 'Pickup OTP',
              subtitle: 'Both rider and driver verify each other.',
            ),
            _Item(
              icon: Icons.people_outline,
              title: 'Phone-verified co-riders',
              subtitle: 'No anonymous shares — every rider is a real account.',
            ),
            SizedBox(height: 16),
            _Header('Get help'),
            _Item(
              icon: Icons.email_outlined,
              title: 'Email support',
              subtitle: 'anandrahul044@gmail.com',
            ),
            _Item(
              icon: Icons.phone_outlined,
              title: '24/7 support line',
              subtitle: 'Call from inside an active ride.',
            ),
          ],
        ),
      ),
    );
  }
}

class _SosBanner extends StatelessWidget {
  const _SosBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield, color: Colors.red),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'In an emergency, tap SOS during a ride. We notify your contacts and our 24/7 team with your live location.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      );
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _Item(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        const TextStyle(color: Colors.black54, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
