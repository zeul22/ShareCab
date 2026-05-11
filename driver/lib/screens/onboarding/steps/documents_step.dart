import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_theme.dart';
import '../onboarding_state.dart';

/// Step 3 — Document upload. UX-complete (driver sees the same three rows
/// they get in Rapido/Uber) but uploads are NOT wired to the backend yet —
/// the `/drivers/onboard` endpoint accepts text fields only. We capture
/// local file paths in [OnboardingState] so a future migration can add the
/// multipart upload without changing the wizard.
class DocumentsStep extends StatefulWidget {
  final OnboardingState state;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  const DocumentsStep({
    super.key,
    required this.state,
    required this.onContinue,
    required this.onBack,
  });

  @override
  State<DocumentsStep> createState() => _DocumentsStepState();
}

class _DocumentsStepState extends State<DocumentsStep> {
  final _picker = ImagePicker();

  Future<void> _pick(_DocKind kind) async {
    // Use the camera by default (drivers usually photograph the document
    // on the spot rather than dig through their gallery). Falls back to
    // gallery on platforms where the camera isn't available.
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
    } catch (_) {
      try {
        picked = await _picker.pickImage(source: ImageSource.gallery);
      } catch (_) {
        return;
      }
    }
    if (picked == null) return;
    setState(() {
      switch (kind) {
        case _DocKind.license:
          widget.state.licensePhotoPath = picked!.path;
          break;
        case _DocKind.rc:
          widget.state.rcPhotoPath = picked!.path;
          break;
        case _DocKind.selfie:
          widget.state.selfiePhotoPath = picked!.path;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Upload documents',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              "Photos are reviewed by our ops team before you can go online. "
              "Make sure all four corners and the text are clearly visible.",
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                children: [
                  _DocRow(
                    title: 'Driving licence',
                    subtitle: 'Front side, with photo and number visible',
                    path: widget.state.licensePhotoPath,
                    onPick: () => _pick(_DocKind.license),
                  ),
                  const SizedBox(height: 12),
                  _DocRow(
                    title: 'Vehicle RC',
                    subtitle: 'Page showing the registration number',
                    path: widget.state.rcPhotoPath,
                    onPick: () => _pick(_DocKind.rc),
                  ),
                  const SizedBox(height: 12),
                  _DocRow(
                    title: 'Selfie with car',
                    subtitle: 'For ops verification',
                    path: widget.state.selfiePhotoPath,
                    onPick: () => _pick(_DocKind.selfie),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.brandLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: AppTheme.brandDark),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'You can skip uploads for now and add them later '
                            'from your profile. Your account will stay in '
                            'review until all three are submitted.',
                            style: TextStyle(
                              color: AppTheme.brandDark,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: widget.onContinue,
              child: const Text('Continue'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

enum _DocKind { license, rc, selfie }

class _DocRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? path;
  final VoidCallback onPick;

  const _DocRow({
    required this.title,
    required this.subtitle,
    required this.path,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final attached = path != null;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6F7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: attached ? AppTheme.brand : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: attached ? AppTheme.brandLight : Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                attached ? Icons.check_circle : Icons.upload_file_outlined,
                color: attached ? AppTheme.brand : Colors.black45,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    attached ? 'Attached — tap to retake' : subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: attached ? AppTheme.brand : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}
