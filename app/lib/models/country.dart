/// Country dial codes for the login flow's phone-number picker.
///
/// We ship a hand-picked subset of ~30 countries (covering India + major
/// English-speaking markets + the Gulf and SE Asian diaspora MSG91 is
/// most likely to be sending OTPs to) rather than pulling the full ISO
/// 3166 list. Keeps the binary small and the picker scrollable without
/// search; users who need a country we don't list can ask support.
///
/// `flag` is the Unicode regional-indicator pair for the ISO code,
/// rendered as a coloured flag emoji on every platform Flutter targets.
class Country {
  final String name;
  /// ISO 3166-1 alpha-2 code, e.g. "IN".
  final String code;
  /// Dial code WITHOUT the leading `+`, e.g. "91". The picker prepends
  /// the `+` when displaying / when assembling the final E.164 number.
  final String dialCode;
  /// Display label like "🇮🇳" — derived from [code] via Unicode regional
  /// indicators.
  final String flag;

  const Country({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
  });

  /// "+91" — what we prepend to the user's digits to build E.164.
  String get prefix => '+$dialCode';

  /// Default for new sessions. India-first since that's our launch market.
  static const Country defaultCountry = Country(
    name: 'India',
    code: 'IN',
    dialCode: '91',
    flag: '🇮🇳',
  );

  /// The full picker list. Ordered: India first (default), then the
  /// other most-likely-to-be-used countries roughly by Indian diaspora
  /// concentration + major English markets, then alphabetical for the
  /// rest. The first ~12 cover ~95% of real-world picks.
  static const List<Country> all = [
    Country(name: 'India', code: 'IN', dialCode: '91', flag: '🇮🇳'),
    Country(name: 'United States', code: 'US', dialCode: '1', flag: '🇺🇸'),
    Country(name: 'United Kingdom', code: 'GB', dialCode: '44', flag: '🇬🇧'),
    Country(name: 'United Arab Emirates', code: 'AE', dialCode: '971', flag: '🇦🇪'),
    Country(name: 'Canada', code: 'CA', dialCode: '1', flag: '🇨🇦'),
    Country(name: 'Australia', code: 'AU', dialCode: '61', flag: '🇦🇺'),
    Country(name: 'Singapore', code: 'SG', dialCode: '65', flag: '🇸🇬'),
    Country(name: 'Saudi Arabia', code: 'SA', dialCode: '966', flag: '🇸🇦'),
    Country(name: 'Germany', code: 'DE', dialCode: '49', flag: '🇩🇪'),
    Country(name: 'Nepal', code: 'NP', dialCode: '977', flag: '🇳🇵'),
    Country(name: 'Bangladesh', code: 'BD', dialCode: '880', flag: '🇧🇩'),
    Country(name: 'Sri Lanka', code: 'LK', dialCode: '94', flag: '🇱🇰'),
    Country(name: 'Pakistan', code: 'PK', dialCode: '92', flag: '🇵🇰'),
    Country(name: 'Malaysia', code: 'MY', dialCode: '60', flag: '🇲🇾'),
    Country(name: 'Thailand', code: 'TH', dialCode: '66', flag: '🇹🇭'),
    Country(name: 'Indonesia', code: 'ID', dialCode: '62', flag: '🇮🇩'),
    Country(name: 'Philippines', code: 'PH', dialCode: '63', flag: '🇵🇭'),
    Country(name: 'France', code: 'FR', dialCode: '33', flag: '🇫🇷'),
    Country(name: 'Japan', code: 'JP', dialCode: '81', flag: '🇯🇵'),
    Country(name: 'New Zealand', code: 'NZ', dialCode: '64', flag: '🇳🇿'),
    Country(name: 'Hong Kong', code: 'HK', dialCode: '852', flag: '🇭🇰'),
    Country(name: 'South Korea', code: 'KR', dialCode: '82', flag: '🇰🇷'),
    Country(name: 'Qatar', code: 'QA', dialCode: '974', flag: '🇶🇦'),
    Country(name: 'Bahrain', code: 'BH', dialCode: '973', flag: '🇧🇭'),
    Country(name: 'Kuwait', code: 'KW', dialCode: '965', flag: '🇰🇼'),
    Country(name: 'Oman', code: 'OM', dialCode: '968', flag: '🇴🇲'),
    Country(name: 'South Africa', code: 'ZA', dialCode: '27', flag: '🇿🇦'),
    Country(name: 'Netherlands', code: 'NL', dialCode: '31', flag: '🇳🇱'),
    Country(name: 'Ireland', code: 'IE', dialCode: '353', flag: '🇮🇪'),
    Country(name: 'Switzerland', code: 'CH', dialCode: '41', flag: '🇨🇭'),
    Country(name: 'Italy', code: 'IT', dialCode: '39', flag: '🇮🇹'),
    Country(name: 'Spain', code: 'ES', dialCode: '34', flag: '🇪🇸'),
    Country(name: 'China', code: 'CN', dialCode: '86', flag: '🇨🇳'),
    Country(name: 'Brazil', code: 'BR', dialCode: '55', flag: '🇧🇷'),
    Country(name: 'Mexico', code: 'MX', dialCode: '52', flag: '🇲🇽'),
    Country(name: 'Turkey', code: 'TR', dialCode: '90', flag: '🇹🇷'),
    Country(name: 'Israel', code: 'IL', dialCode: '972', flag: '🇮🇱'),
    Country(name: 'Vietnam', code: 'VN', dialCode: '84', flag: '🇻🇳'),
    Country(name: 'Egypt', code: 'EG', dialCode: '20', flag: '🇪🇬'),
    Country(name: 'Kenya', code: 'KE', dialCode: '254', flag: '🇰🇪'),
    Country(name: 'Nigeria', code: 'NG', dialCode: '234', flag: '🇳🇬'),
  ];

  /// Search by name (case-insensitive), ISO code, or dial code.
  /// Returns the unfiltered list when the query is empty / whitespace.
  static List<Country> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    // Allow searching with a leading `+` so users can type "+44" directly.
    final dialQ = q.startsWith('+') ? q.substring(1) : q;
    return all.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.code.toLowerCase().contains(q) ||
          c.dialCode.contains(dialQ);
    }).toList(growable: false);
  }
}
