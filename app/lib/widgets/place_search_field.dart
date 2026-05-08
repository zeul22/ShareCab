import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api/places_service.dart';
import '../theme/app_theme.dart';

/// Replacement for `GooglePlaceAutoCompleteTextField` that we control end-to-end.
///
/// Behavior:
///   - 400ms debounce on input.
///   - Each keystroke after debounce calls [PlacesService.autocomplete].
///   - Tapping a suggestion fetches details and calls [onPlaceSelected] with a
///     resolved [PlaceDetails] (place id + lat/lng + address).
///   - Errors render inline as a small banner — never crash the host screen.
class PlaceSearchField extends StatefulWidget {
  final TextEditingController controller;
  final PlacesService service;
  final ValueChanged<PlaceDetails> onPlaceSelected;
  final String hintText;

  const PlaceSearchField({
    super.key,
    required this.controller,
    required this.service,
    required this.onPlaceSelected,
    this.hintText = 'Search address',
  });

  @override
  State<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<PlaceSearchField> {
  Timer? _debounce;
  List<PlacePrediction> _predictions = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(text));
  }

  Future<void> _search(String text) async {
    final query = text.trim();
    if (query.isEmpty) {
      setState(() {
        _predictions = const [];
        _busy = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final preds = await widget.service.autocomplete(query);
      if (!mounted) return;
      setState(() {
        _predictions = preds;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _predictions = const [];
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _select(PlacePrediction p) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final details = await widget.service.details(p.placeId);
      if (!mounted) return;
      if (details != null) {
        widget.controller.text = p.description;
        widget.controller.selection = TextSelection.fromPosition(
          TextPosition(offset: widget.controller.text.length),
        );
        setState(() => _predictions = const []);
        widget.onPlaceSelected(details);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() {
    widget.controller.clear();
    setState(() {
      _predictions = const [];
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _clear,
                      )
                    : null),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
        ),
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF1C0C0)),
            ),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB00020), fontSize: 12, height: 1.35),
            ),
          ),
        if (_predictions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
            ),
            child: Material(
              color: Colors.transparent,
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _predictions.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 50, endIndent: 12),
                itemBuilder: (_, i) {
                  final p = _predictions[i];
                  return ListTile(
                    leading: const Icon(Icons.place_outlined, color: AppTheme.brand),
                    title: Text(
                      p.primaryText.isNotEmpty ? p.primaryText : p.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: p.secondaryText.isNotEmpty
                        ? Text(
                            p.secondaryText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                    onTap: () => _select(p),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
