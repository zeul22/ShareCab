import 'package:flutter/material.dart';

import '../models/country.dart';
import '../theme/app_theme.dart';

/// Bottom sheet for picking a phone-number country/dial code. Search by
/// name, ISO code, or dial code (with or without a leading "+").
///
/// Caller is responsible for [showModalBottomSheet]; we just expose the
/// widget. Tapping a row pops the sheet with that [Country] as the
/// result, so the caller does:
///   final country = await showModalBottomSheet<Country>(...)
class CountryPickerBottomSheet extends StatefulWidget {
  /// Currently-selected country, highlighted in the list.
  final Country selected;
  const CountryPickerBottomSheet({super.key, required this.selected});

  /// Convenience launcher — handles the showModalBottomSheet plumbing so
  /// the caller is just `final c = await CountryPickerBottomSheet.show(...)`.
  static Future<Country?> show(
    BuildContext context, {
    required Country selected,
  }) {
    return showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CountryPickerBottomSheet(selected: selected),
    );
  }

  @override
  State<CountryPickerBottomSheet> createState() => _CountryPickerBottomSheetState();
}

class _CountryPickerBottomSheetState extends State<CountryPickerBottomSheet> {
  final _searchCtrl = TextEditingController();
  late List<Country> _filtered = Country.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    setState(() => _filtered = Country.search(q));
  }

  @override
  Widget build(BuildContext context) {
    // Sheet takes ~85% of viewport so the keyboard fits comfortably when
    // the search field is focused, but doesn't cover the entire screen.
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grab handle — standard iOS / Material 3 affordance.
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select country',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: false,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search by country, code, or +91',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          'No matches',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final c = _filtered[i];
                        final isSelected = c.code == widget.selected.code &&
                            c.dialCode == widget.selected.dialCode;
                        return ListTile(
                          dense: true,
                          // ISO 2-letter code in a small tile. Renders
                          // reliably everywhere (unlike flag emojis),
                          // and gives users a scannable visual marker.
                          leading: Container(
                            width: 36,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.brandLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              c.code,
                              style: const TextStyle(
                                color: AppTheme.brandDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          title: Text(
                            c.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: Text(
                            c.prefix,
                            style: TextStyle(
                              color: isSelected
                                  ? AppTheme.brandDark
                                  : Colors.black54,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          selected: isSelected,
                          selectedTileColor: AppTheme.brandLight,
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
