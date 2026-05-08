import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/place.dart';
import '../services/api/places_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_config.dart';
import '../widgets/place_search_field.dart';

/// Full-screen picker that returns a [Place] to the caller via Navigator.pop.
///
/// Two ways to choose a point:
///   1. Type into the Places autocomplete search bar (uses [PlacesService]).
///   2. Drag the map; the centered pin marks the selected point.
class MapPickerScreen extends StatefulWidget {
  final String title;
  final Place? initial;

  const MapPickerScreen({super.key, required this.title, this.initial});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _map;
  final _searchCtrl = TextEditingController();
  late final PlacesService _places;

  // Default to a sensible city center if no initial point was supplied.
  // Connaught Place, Delhi — easy to recognize and visually rich.
  static const LatLng _defaultCenter = LatLng(28.6315, 77.2167);

  late LatLng _center;
  String _address = '';

  @override
  void initState() {
    super.initState();
    _places = PlacesService(apiKey: ApiConfig.googleMapsKey);
    if (widget.initial != null) {
      _center = LatLng(widget.initial!.lat, widget.initial!.lng);
      _address = widget.initial!.address;
      _searchCtrl.text = widget.initial!.address;
    } else {
      _center = _defaultCenter;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _map?.dispose();
    _places.dispose();
    super.dispose();
  }

  void _onPlaceSelected(PlaceDetails details) {
    setState(() {
      _center = LatLng(details.lat, details.lng);
      _address = details.formattedAddress;
    });
    _map?.animateCamera(CameraUpdate.newLatLngZoom(_center, 16));
  }

  void _confirm() {
    Navigator.of(context).pop(
      Place(
        address: _address.isEmpty ? 'Pinned location' : _address,
        lat: _center.latitude,
        lng: _center.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 15),
            onMapCreated: (c) => _map = c,
            onCameraMove: (pos) => _center = pos.target,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Centered pin overlay.
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 32),
                child: Icon(Icons.location_pin, size: 48, color: AppTheme.brand),
              ),
            ),
          ),

          // Search bar + suggestions list.
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: PlaceSearchField(
                controller: _searchCtrl,
                service: _places,
                onPlaceSelected: _onPlaceSelected,
              ),
            ),
          ),

          // Confirm button.
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: ElevatedButton(
              onPressed: _confirm,
              child: Text('Confirm ${widget.title.toLowerCase()}'),
            ),
          ),
        ],
      ),
    );
  }
}
