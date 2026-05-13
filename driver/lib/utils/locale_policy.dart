import 'dart:ui';

import 'package:flutter/widgets.dart';

/// Locale policy for ShareCab's India-first rollout.
///
/// Keep this in sync with the rider app until the two Flutter apps share a
/// common package.
class ShareCabLocalePolicy {
  const ShareCabLocalePolicy._();

  static const fallbackLocale = Locale('en');

  static const supportedLocales = <Locale>[
    Locale('en'), // English
    Locale('hi'), // Hindi
    Locale('as'), // Assamese
    Locale('bn'), // Bengali
    Locale('gu'), // Gujarati
    Locale('kn'), // Kannada
    Locale('ml'), // Malayalam
    Locale('mr'), // Marathi
    Locale('ne'), // Nepali
    Locale('or'), // Odia
    Locale('pa'), // Punjabi
    Locale('ta'), // Tamil
    Locale('te'), // Telugu
    Locale('ur'), // Urdu
  ];

  static const supportedLanguageCodes = <String>{
    'en',
    'hi',
    'as',
    'bn',
    'gu',
    'kn',
    'ml',
    'mr',
    'ne',
    'or',
    'pa',
    'ta',
    'te',
    'ur',
  };

  static Locale resolve(Locale? deviceLocale, Iterable<Locale> supported) {
    if (deviceLocale == null) return fallbackLocale;

    for (final locale in supported) {
      if (locale.languageCode == deviceLocale.languageCode &&
          locale.countryCode == deviceLocale.countryCode) {
        return locale;
      }
    }
    for (final locale in supported) {
      if (locale.languageCode == deviceLocale.languageCode) {
        return locale;
      }
    }
    return fallbackLocale;
  }

  static String resolveLanguageCode(String? languageCode) {
    if (languageCode != null && supportedLanguageCodes.contains(languageCode)) {
      return languageCode;
    }
    return fallbackLocale.languageCode;
  }
}
