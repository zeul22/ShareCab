import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routes.dart';
import '../services/api/driver_api.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Landing screen for drivers whose application is awaiting ops approval.
/// Pull-to-refresh re-checks status — when it flips to 'approved', we
/// auto-jump to the home dashboard so the driver doesn't have to log out
/// and back in.
class PendingReviewScreen extends StatefulWidget {
  const PendingReviewScreen({super.key});

  @override
  State<PendingReviewScreen> createState() => _PendingReviewScreenState();
}

class _PendingReviewScreenState extends State<PendingReviewScreen> {
  bool _checking = false;

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final profile = await context.read<DriverApi>().getMyDriverOrNull();
      if (!mounted) return;
      if (profile != null && profile.verificationStatus == 'approved') {
        Navigator.of(context)
            .pushNamedAndRemoveUntil(Routes.home, (_) => false);
      }
    } catch (_) {
      // Silent — the empty-state copy already explains "we'll notify you".
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _logout() async {
    await context.read<AuthService>().logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(Routes.phoneEntry, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.watch<AuthService>().user?.phone ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Application status',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _logout,
            child: const Text(
              'Log out',
              style: TextStyle(
                  color: AppTheme.brand, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppTheme.brand,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: AppTheme.brandLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.hourglass_bottom,
                  size: 48,
                  color: AppTheme.brandDark,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Verification in progress',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              "Thanks for signing up. Our ops team is reviewing the details "
              "for $phone. You'll be able to go online as soon as we approve "
              "you — usually within 24 hours.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.black54, height: 1.5, fontSize: 14),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.brandLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      color: AppTheme.brandDark, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pull down to refresh once you receive the approval '
                      "notification — we'll take you straight to the dashboard.",
                      style: TextStyle(
                        color: AppTheme.brandDark,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _checking ? null : _refresh,
              icon: _checking
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('Check status'),
            ),
          ],
        ),
      ),
    );
  }
}
