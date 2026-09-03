import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../theme/app_colors.dart';
import 'shield_store.dart';
import 'store_locator.dart';

/// The "Your SHIELD store" picker as a map.
///
/// Location is **required**: until the member grants it the map is replaced by
/// an enable-location gate, and [onLocationReady] fires `false` so the caller
/// can hold its submit button back. Once a fix lands the map shows every branch
/// as a pin plus a "you" dot, the nearest is pre-selected, and a distance-
/// ranked list under the map gives an exact tap target.
///
/// Uses OpenStreetMap tiles — no API key, no billing — so it renders the same
/// on the APK and the web build.
class StoreMapPicker extends StatefulWidget {
  final String? selectedId;
  final ValueChanged<ShieldStore> onSelected;

  /// `true` once a location fix is in hand and the map is showing; `false`
  /// while the gate is up.
  final ValueChanged<bool>? onLocationReady;

  /// Pre-select the nearest branch on the first fix when nothing is chosen yet.
  final bool autoPickNearest;

  const StoreMapPicker({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.onLocationReady,
    this.autoPickNearest = true,
  });

  @override
  State<StoreMapPicker> createState() => _StoreMapPickerState();
}

class _StoreMapPickerState extends State<StoreMapPicker>
    with WidgetsBindingObserver {
  final MapController _map = MapController();
  StoreLocationResult? _loc;
  LocationOutcome _outcome = LocationOutcome.denied;
  bool _busy = false;
  bool _expanded = false;

  bool get _ready => _loc?.ok ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The member may have just come back from the system settings screen.
    if (state == AppLifecycleState.resumed &&
        !_ready &&
        (_outcome == LocationOutcome.serviceOff ||
            _outcome == LocationOutcome.deniedForever)) {
      _locate();
    }
  }

  Future<void> _locate() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final result = await StoreLocator.locate();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _outcome = result.outcome;
      if (result.ok) {
        _loc = result;
        if (widget.autoPickNearest &&
            widget.selectedId == null &&
            result.nearest != null) {
          widget.onSelected(result.nearest!);
        }
      }
    });
    widget.onLocationReady?.call(result.ok);
    final p = result.position;
    if (result.ok && p != null) {
      _map.move(LatLng(p.latitude, p.longitude), 11);
    }
  }

  Future<void> _openSettings() async {
    if (_outcome == LocationOutcome.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ready ? _buildMap() : _buildGate();
  }

  // --- Gate --------------------------------------------------------------

  Widget _buildGate() {
    final (title, body) = switch (_outcome) {
      LocationOutcome.serviceOff => (
          'Location is switched off',
          'Turn on location on your device so we can show the SHIELD branches '
              'near you and pick the closest one.'
        ),
      LocationOutcome.deniedForever => (
          'Location permission is off',
          'Open settings and allow location for SHIELD. Choosing your branch '
              'on the map needs it.'
        ),
      _ => (
          'We need your location',
          'Your SHIELD branch is picked from the map by how close it is to you. '
              'Allow location to continue.'
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.pageTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.location_on_rounded,
              size: 34, color: AppColors.brandBlue),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          if (_outcome == LocationOutcome.serviceOff ||
              _outcome == LocationOutcome.deniedForever) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _openSettings,
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Open settings'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _locate,
              child: const Text('I have enabled it — try again'),
            ),
          ] else
            FilledButton.icon(
              onPressed: _busy ? null : _locate,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: Text(_busy ? 'Finding you…' : 'Enable location'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
        ],
      ),
    );
  }

  // --- Map + list ------------------------------------------------------

  Widget _buildMap() {
    final p = _loc!.position!;
    final me = LatLng(p.latitude, p.longitude);
    final ranked = _loc!.ranked;
    final visible = _expanded ? ranked : ranked.take(4).toList();

    void select(ShieldStore s) {
      widget.onSelected(s);
      if (s.hasLocation) {
        _map.move(LatLng(s.latitude!, s.longitude!), _map.camera.zoom);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 240,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: me,
                    initialZoom: 11,
                    minZoom: 8,
                    maxZoom: 17,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.pinchZoom |
                          InteractiveFlag.drag |
                          InteractiveFlag.doubleTapZoom |
                          InteractiveFlag.flingAnimation,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.zabnix.shield',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: me,
                          width: 22,
                          height: 22,
                          child: const _MeDot(),
                        ),
                        // Unselected branches first, the selected one last, so
                        // its label and taller pin sit on top of any it overlaps.
                        for (final s in [
                          for (final s in StoreDirectory.all)
                            if (s.hasLocation && s.id != widget.selectedId) s,
                          for (final s in StoreDirectory.all)
                            if (s.hasLocation && s.id == widget.selectedId) s,
                        ])
                          Marker(
                            point: LatLng(s.latitude!, s.longitude!),
                            width: 156,
                            height: 66,
                            // The pin's tip, not its top, marks the spot.
                            alignment: Alignment.bottomCenter,
                            child: _StorePin(
                              name: s.area,
                              selected: s.id == widget.selectedId,
                              onTap: () => select(s),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _RoundButton(
                    icon: Icons.my_location_rounded,
                    onTap: () => _map.move(me, 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final s in visible) ...[
          _StoreRow(
            store: s,
            selected: s.id == widget.selectedId,
            isNearest: s.id == _loc!.nearest?.id,
            distanceLabel: s.hasLocation
                ? StoreLocator.label(s.distanceKmFrom(p.latitude, p.longitude)!)
                : null,
            onTap: () => select(s),
          ),
          const SizedBox(height: 10),
        ],
        if (ranked.length > visible.length || _expanded)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandBlue,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _expanded
                    ? 'Show fewer branches'
                    : 'Show all ${ranked.length} branches',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.brandBlue,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlue.withValues(alpha: 0.4),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

/// A branch marker: the store name on a small white tag, sitting directly above
/// a red map pin whose tip marks the branch. The selected branch gets a deeper
/// red, a bolder tag and a larger pin so it stands out from the rest.
class _StorePin extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _StorePin({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  /// Map-pin red, and the deeper red for the chosen branch.
  static const Color _red = Color(0xFFE23744);
  static const Color _redDeep = Color(0xFFC0182A);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 154),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? _redDeep : const Color(0x33000000),
                  width: selected ? 1.2 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.15,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: selected ? _redDeep : AppColors.textDark,
                ),
              ),
            ),
          ),
          const SizedBox(height: 1),
          Icon(
            Icons.location_on,
            size: selected ? 40 : 30,
            color: selected ? _redDeep : _red,
            shadows: const [
              Shadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: AppColors.brandBlue),
        ),
      ),
    );
  }
}

class _StoreRow extends StatelessWidget {
  final ShieldStore store;
  final bool selected;
  final bool isNearest;
  final String? distanceLabel;
  final VoidCallback onTap;

  const _StoreRow({
    required this.store,
    required this.selected,
    required this.isNearest,
    required this.distanceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.offerTint : AppColors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.brandBlue : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 21,
                color: selected ? AppColors.brandBlue : AppColors.textMuted,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      store.addressLine,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: AppColors.textBody,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (isNearest)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.brandGreenDeep,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Nearest',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        if (distanceLabel != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.near_me_rounded,
                                  size: 12, color: AppColors.brandBlue),
                              const SizedBox(width: 3),
                              Text(
                                '$distanceLabel away',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brandBlue,
                                ),
                              ),
                            ],
                          ),
                        Text(
                          store.hours,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
