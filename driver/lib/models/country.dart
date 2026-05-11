/// Country dial codes for the login flow's phone-number picker. Subset
/// of ~30 countries (India-first since that's our launch market), matching
/// the rider app so both clients hand identical E.164 phones to the
/// backend.
class Country {
  final String name;
  final String code;
  final String dialCode;
  final String flag;

  const Country({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
  });

  String get prefix => '+$dialCode';

  static const Country defaultCountry = Country(
    name: 'India',
    code: 'IN',
    dialCode: '91',
    flag: '🇮🇳',
  );

  static const List<Country> all = [
    Country(name: 'India', code: 'IN', dialCode: '91', flag: '🇮🇳'),
    Country(name: 'United States', code: 'US', dialCode: '1', flag: '🇺🇸'),
    Country(name: 'United Kingdom', code: 'GB', dialCode: '44', flag: '🇬🇧'),
    Country(name: 'United Arab Emirates', code: 'AE', dialCode: '971', flag: '🇦🇪'),
    Country(name: 'Canada', code: 'CA', dialCode: '1', flag: '🇨🇦'),
    Country(name: 'Australia', code: 'AU', dialCode: '61', flag: '🇦🇺'),
    Country(name: 'Singapore', code: 'SG', dialCode: '65', flag: '🇸🇬'),
    Country(name: 'Saudi Arabia', code: 'SA', dialCode: '966', flag: '🇸🇦'),
    Country(name: 'Nepal', code: 'NP', dialCode: '977', flag: '🇳🇵'),
    Country(name: 'Bangladesh', code: 'BD', dialCode: '880', flag: '🇧🇩'),
    Country(name: 'Sri Lanka', code: 'LK', dialCode: '94', flag: '🇱🇰'),
  ];

  static List<Country> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    final dialQ = q.startsWith('+') ? q.substring(1) : q;
    return all.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.code.toLowerCase().contains(q) ||
          c.dialCode.contains(dialQ);
    }).toList(growable: false);
  }
}
