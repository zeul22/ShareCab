// Smoke test: the app boots into the splash screen without throwing.
// Real integration testing (OTP flow, onboarding, etc.) is out of scope
// for the v1 driver app — kept here so `flutter test` exits cleanly.

import 'package:flutter_test/flutter_test.dart';

import 'package:sharecab_driver/main.dart';

void main() {
  testWidgets('App boots into splash', (WidgetTester tester) async {
    await tester.pumpWidget(const ShareCabDriverApp());
    // Splash renders the brand heading.
    expect(find.text('ShareCab Driver'), findsOneWidget);
  });
}
